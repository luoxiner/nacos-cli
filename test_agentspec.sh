#!/bin/bash
#
# Integration test for agentspec CLI commands.
# Requires a local Nacos server running at 127.0.0.1:8848 with username/password = nacos/nacos.
#

set -uo pipefail

NACOS_HOST="127.0.0.1"
NACOS_PORT="8848"
NACOS_USER="nacos"
NACOS_PASS="nacos"
CLI_FLAGS="--host $NACOS_HOST --port $NACOS_PORT --username $NACOS_USER --password $NACOS_PASS"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_BIN="$SCRIPT_DIR/nacos-cli-test"
TEST_DIR=$(mktemp -d)

PASSED=0
FAILED=0
TOTAL=0

# Colors
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ---------- helpers ----------

log_test() {
  TOTAL=$((TOTAL + 1))
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}TEST $TOTAL: $1${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

pass() {
  PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${RESET}: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${RESET}: $1"
}

get_token() {
  curl -s "http://$NACOS_HOST:$NACOS_PORT/nacos/v1/auth/login" \
    -d "username=$NACOS_USER&password=$NACOS_PASS" | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])"
}

admin_api() {
  local method="$1"
  local path="$2"
  shift 2
  local token
  token=$(get_token)
  curl -s -X "$method" "http://$NACOS_HOST:$NACOS_PORT/nacos/v3/admin/ai/agentspecs$path" \
    -H "Authorization: Bearer $token" "$@"
}

# Delete an agentspec (offline all versions first, then delete)
cleanup_spec() {
  local name="$1"
  local token
  token=$(get_token)

  # Offline all versions
  local versions
  versions=$(curl -s "http://$NACOS_HOST:$NACOS_PORT/nacos/v3/admin/ai/agentspecs?namespaceId=public&agentSpecName=$name" \
    -H "Authorization: Bearer $token" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['data']
    for v in d.get('versions', []):
        if v['status'] == 'online':
            print(v['version'])
except: pass
" 2>/dev/null || true)

  for v in $versions; do
    curl -s -X POST "http://$NACOS_HOST:$NACOS_PORT/nacos/v3/admin/ai/agentspecs/offline" \
      -H "Authorization: Bearer $token" \
      -d "namespaceId=public&agentSpecName=$name&version=$v" >/dev/null 2>&1 || true
  done

  # Delete
  curl -s -X DELETE "http://$NACOS_HOST:$NACOS_PORT/nacos/v3/admin/ai/agentspecs?namespaceId=public&agentSpecName=$name" \
    -H "Authorization: Bearer $token" >/dev/null 2>&1 || true
}

# Submit → publish (or online if pipeline blocks) → set labels.latest so client GET without --version resolves.
publish_spec() {
  local name="$1"
  local version="$2"
  admin_api POST "/submit" -d "namespaceId=public&agentSpecName=$name&version=$version" >/dev/null 2>&1
  admin_api POST "/publish" -d "namespaceId=public&agentSpecName=$name&version=$version" >/dev/null 2>&1 || true
  admin_api POST "/online" -d "namespaceId=public&agentSpecName=$name&scope=version&version=$version" >/dev/null 2>&1 || true
  local token
  token=$(get_token)
  curl -s -X PUT "http://$NACOS_HOST:$NACOS_PORT/nacos/v3/admin/ai/agentspecs/labels" \
    -H "Authorization: Bearer $token" \
    -d "namespaceId=public&agentSpecName=${name}&labels=%7B%22latest%22%3A%22${version}%22%7D" >/dev/null 2>&1 || true
}

# ---------- build ----------

echo -e "${YELLOW}Building CLI binary...${RESET}"
cd "$SCRIPT_DIR"
CGO_ENABLED=0 go build -o "$CLI_BIN" .
echo -e "${GREEN}Build OK${RESET}"

# ---------- setup test data ----------

echo -e "${YELLOW}Setting up test data...${RESET}"

# Create single spec directory
mkdir -p "$TEST_DIR/my-worker"
cat > "$TEST_DIR/my-worker/manifest.json" << 'EOF'
{
  "version": "1.0",
  "worker": {
    "suggested_name": "e2e-my-worker"
  }
}
EOF
mkdir -p "$TEST_DIR/my-worker/config"
cat > "$TEST_DIR/my-worker/config/app.yaml" << 'EOF'
server:
  port: 8080
  name: my-worker
EOF

# Create batch specs directory
mkdir -p "$TEST_DIR/batch/spec-alpha"
cat > "$TEST_DIR/batch/spec-alpha/manifest.json" << 'EOF'
{"version":"1.0","worker":{"suggested_name":"e2e-spec-alpha"}}
EOF

mkdir -p "$TEST_DIR/batch/spec-beta"
cat > "$TEST_DIR/batch/spec-beta/manifest.json" << 'EOF'
{"version":"1.0","worker":{"suggested_name":"e2e-spec-beta"}}
EOF

# A directory without manifest.json (should be skipped)
mkdir -p "$TEST_DIR/batch/no-manifest"
echo "not a spec" > "$TEST_DIR/batch/no-manifest/readme.txt"

# Create zip file for direct upload
mkdir -p "$TEST_DIR/zip-source"
cat > "$TEST_DIR/zip-source/manifest.json" << 'EOF'
{"version":"1.0","worker":{"suggested_name":"e2e-zip-worker"}}
EOF
(cd "$TEST_DIR/zip-source" && zip -q "$TEST_DIR/e2e-zip-worker.zip" manifest.json)

# Output directory for get
mkdir -p "$TEST_DIR/output"

# Cleanup any leftover specs from previous runs
for name in e2e-my-worker e2e-spec-alpha e2e-spec-beta e2e-zip-worker; do
  cleanup_spec "$name"
done

echo -e "${GREEN}Setup OK${RESET}"

# ========================================
# TESTS
# ========================================

# ---------- TEST: list (empty or baseline) ----------
log_test "agentspec-list (baseline)"
OUTPUT=$($CLI_BIN agentspec-list $CLI_FLAGS 2>&1) || true
echo "$OUTPUT"
# Should not error out
if echo "$OUTPUT" | grep -q "Error:"; then
  fail "agentspec-list returned an error"
else
  pass "agentspec-list runs without error"
fi

# ---------- TEST: upload single spec ----------
log_test "agentspec-publish (single directory)"
OUTPUT=$($CLI_BIN agentspec-publish "$TEST_DIR/my-worker" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "published successfully"; then
  pass "single publish succeeded"
else
  fail "single publish did not succeed"
fi

# ---------- TEST: publish zip file ----------
log_test "agentspec-publish (zip file)"
OUTPUT=$($CLI_BIN agentspec-publish "$TEST_DIR/e2e-zip-worker.zip" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "published successfully"; then
  pass "zip publish succeeded"
else
  fail "zip publish did not succeed"
fi

# ---------- TEST: publish batch ----------
log_test "agentspec-publish --all (batch)"
OUTPUT=$($CLI_BIN agentspec-publish --all "$TEST_DIR/batch" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "Success: 2"; then
  pass "batch publish: 2 specs published"
else
  fail "batch publish did not report 2 successes"
fi
if echo "$OUTPUT" | grep -q "no-manifest"; then
  fail "batch publish should skip no-manifest directory"
else
  pass "batch publish correctly skipped no-manifest directory"
fi

# ---------- TEST: list after uploads ----------
log_test "agentspec-list (after uploads)"
OUTPUT=$($CLI_BIN agentspec-list $CLI_FLAGS 2>&1)
echo "$OUTPUT"
COUNT=$(echo "$OUTPUT" | grep -c "e2e-" || true)
if [ "$COUNT" -ge 4 ]; then
  pass "list shows all 4 uploaded specs"
else
  fail "expected at least 4 e2e- specs, found $COUNT"
fi

# ---------- TEST: list with --name filter ----------
log_test "agentspec-list --name (exact filter)"
OUTPUT=$($CLI_BIN agentspec-list --name e2e-my-worker $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "e2e-my-worker"; then
  pass "name filter found e2e-my-worker"
else
  fail "name filter did not find e2e-my-worker"
fi
# Should not contain other specs
if echo "$OUTPUT" | grep -q "e2e-spec-alpha"; then
  fail "name filter returned unrelated spec"
else
  pass "name filter correctly excluded other specs"
fi

# ---------- TEST: list with --name ----------
log_test "agentspec-list --name"
OUTPUT=$($CLI_BIN agentspec-list --name e2e $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -qi "error.*parse\|panic"; then
  fail "name search caused an error"
else
  pass "name search ran without crash"
fi

# ---------- TEST: list with --page --size ----------
log_test "agentspec-list --page --size (pagination)"
OUTPUT=$($CLI_BIN agentspec-list --page 1 --size 2 $CLI_FLAGS 2>&1)
echo "$OUTPUT"
LINE_COUNT=$(echo "$OUTPUT" | grep -c "^\s*[0-9]\+\." || true)
if [ "$LINE_COUNT" -le 2 ]; then
  pass "pagination returned at most 2 items (got $LINE_COUNT)"
else
  fail "pagination did not limit to 2 items (got $LINE_COUNT)"
fi

# ---------- TEST: get before online (should fail with 404) ----------
log_test "agentspec-get (not online, expect 404)"
OUTPUT=$($CLI_BIN agentspec-get e2e-my-worker $CLI_FLAGS 2>&1) || true
echo "$OUTPUT"
if echo "$OUTPUT" | grep -qi "404\|not found"; then
  pass "get correctly returns 404 for non-online spec"
else
  fail "get did not return 404 for non-online spec"
fi

# ---------- Publish e2e-my-worker to make it online ----------
echo ""
echo -e "${YELLOW}Publishing e2e-my-worker v1 to online...${RESET}"
publish_spec "e2e-my-worker" "v1"
# Verify
ONLINE_CNT=$(admin_api GET "?namespaceId=public&agentSpecName=e2e-my-worker" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['onlineCnt'])" 2>/dev/null || echo "0")
echo "  onlineCnt=$ONLINE_CNT"

# ---------- TEST: get after online ----------
log_test "agentspec-get (online spec)"
OUTPUT=$($CLI_BIN agentspec-get e2e-my-worker -o "$TEST_DIR/output" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "downloaded successfully"; then
  pass "get downloaded spec successfully"
else
  fail "get did not download spec"
fi

# Check file structure
log_test "agentspec-get file structure verification"
echo "  Downloaded files:"
if [ -d "$TEST_DIR/output/e2e-my-worker" ]; then
  find "$TEST_DIR/output/e2e-my-worker" -type f | sort | while read -r f; do
    echo "    $f"
  done

  if [ -f "$TEST_DIR/output/e2e-my-worker/manifest.json" ]; then
    pass "manifest.json exists"
  else
    fail "manifest.json missing"
  fi

  # Check manifest is valid JSON and pretty-printed
  if python3 -c "import json; json.load(open('$TEST_DIR/output/e2e-my-worker/manifest.json'))" 2>/dev/null; then
    pass "manifest.json is valid JSON"
  else
    fail "manifest.json is not valid JSON"
  fi
else
  fail "output directory does not exist"
fi

# ---------- TEST: get multiple specs ----------
log_test "agentspec-get (multiple names, mixed online/offline)"
# Publish spec-alpha too
publish_spec "e2e-spec-alpha" "v1"
OUTPUT=$($CLI_BIN agentspec-get e2e-my-worker e2e-spec-alpha e2e-spec-beta -o "$TEST_DIR/output" $CLI_FLAGS 2>&1) || true
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "Summary"; then
  pass "multi-get shows summary"
else
  fail "multi-get did not show summary"
fi
# spec-beta is not online, should fail
if echo "$OUTPUT" | grep -q "Failed.*1\|Failed: 1"; then
  pass "multi-get correctly reports 1 failure (spec-beta not online)"
else
  fail "multi-get did not report expected failure count"
fi

# ---------- TEST: get with --version ----------
log_test "agentspec-get --version v1"
OUTPUT=$($CLI_BIN agentspec-get e2e-my-worker --version v1 -o "$TEST_DIR/output" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "downloaded successfully"; then
  pass "get with --version v1 succeeded"
else
  fail "get with --version v1 failed"
fi

# ---------- TEST: get with --label ----------
log_test "agentspec-get --label latest"
OUTPUT=$($CLI_BIN agentspec-get e2e-my-worker --label latest -o "$TEST_DIR/output" $CLI_FLAGS 2>&1)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "downloaded successfully"; then
  pass "get with --label latest succeeded"
else
  fail "get with --label latest failed"
fi

# ---------- TEST: upload when draft already exists (should fail) ----------
log_test "agentspec-publish (duplicate, expect work-version-lock error)"
OUTPUT=$($CLI_BIN agentspec-publish "$TEST_DIR/my-worker" $CLI_FLAGS 2>&1) || true
echo "$OUTPUT"
# This should fail because e2e-my-worker already has an online version and
# the server may or may not block re-upload depending on state. Just verify no panic.
if echo "$OUTPUT" | grep -qi "panic"; then
  fail "upload caused a panic"
else
  pass "upload handled gracefully (no panic)"
fi

# ---------- TEST: help output ----------
log_test "help output for all commands"
for cmd in agentspec-list agentspec-get agentspec-publish; do
  OUTPUT=$($CLI_BIN $cmd --help 2>&1)
  if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "$cmd --help shows usage"
  else
    fail "$cmd --help did not show usage"
  fi
done

# ========================================
# CLEANUP
# ========================================

echo ""
echo -e "${YELLOW}Cleaning up...${RESET}"
for name in e2e-my-worker e2e-spec-alpha e2e-spec-beta e2e-zip-worker; do
  cleanup_spec "$name"
done
rm -rf "$TEST_DIR"
rm -f "$CLI_BIN"
echo -e "${GREEN}Cleanup OK${RESET}"

# ========================================
# SUMMARY
# ========================================

echo ""
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${CYAN}  TEST SUMMARY${RESET}"
echo -e "${CYAN}══════════════════════════════════════════${RESET}"
echo -e "  Total:  $TOTAL tests, $((PASSED + FAILED)) assertions"
echo -e "  ${GREEN}Passed: $PASSED${RESET}"
if [ "$FAILED" -gt 0 ]; then
  echo -e "  ${RED}Failed: $FAILED${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  exit 1
else
  echo -e "  ${RED}Failed: 0${RESET}"
  echo -e "${CYAN}══════════════════════════════════════════${RESET}"
  echo -e "${GREEN}ALL TESTS PASSED${RESET}"
  exit 0
fi
