package listformat

import (
	"strings"
	"testing"

	"github.com/nacos-group/nacos-cli/internal/agentspec"
	"github.com/nacos-group/nacos-cli/internal/skill"
)

func TestSkillItemsKeepsFullDescription(t *testing.T) {
	longDesc := strings.Repeat("skill-description-", 20)
	items := SkillItems([]skill.SkillListItem{
		{
			Name:        "find-skills",
			Description: longDesc,
		},
	})

	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}
	if items[0].Name != "find-skills" {
		t.Fatalf("expected name to be preserved, got %q", items[0].Name)
	}
	if items[0].Description != longDesc {
		t.Fatalf("expected full description to be preserved")
	}
}

func TestAgentSpecItemsKeepsFullDescription(t *testing.T) {
	longDesc := strings.Repeat("agentspec-description-", 20)
	items := AgentSpecItems([]agentspec.AgentSpecListItem{
		{
			Name:        "zk-manager",
			Description: &longDesc,
		},
	})

	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}
	if items[0].Name != "zk-manager" {
		t.Fatalf("expected name to be preserved, got %q", items[0].Name)
	}
	if items[0].Description != longDesc {
		t.Fatalf("expected full description to be preserved")
	}
}

func TestAgentSpecItemsHandlesNilDescription(t *testing.T) {
	items := AgentSpecItems([]agentspec.AgentSpecListItem{
		{
			Name:        "zk-manager",
			Description: nil,
		},
	})

	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}
	if items[0].Description != "" {
		t.Fatalf("expected empty description for nil source, got %q", items[0].Description)
	}
}
