package listformat

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/nacos-group/nacos-cli/internal/agentspec"
	"github.com/nacos-group/nacos-cli/internal/skill"
)

const (
	DefaultDescLimit = 200
	FormatText       = "text"
	FormatJSON       = "json"
)

// NormalizeFormat converts an empty format to the default and lowercases values.
func NormalizeFormat(format string) string {
	if strings.TrimSpace(format) == "" {
		return FormatText
	}
	return strings.ToLower(strings.TrimSpace(format))
}

// ValidateFormat checks whether a list output format is supported.
func ValidateFormat(format string) error {
	switch NormalizeFormat(format) {
	case FormatText, FormatJSON:
		return nil
	default:
		return fmt.Errorf("unsupported format %q, supported values: %s, %s", format, FormatText, FormatJSON)
	}
}

// TruncateDesc truncates description to maxLen and appends ...... if needed.
func TruncateDesc(desc string, maxLen int) string {
	runes := []rune(desc)
	if len(runes) <= maxLen {
		return desc
	}
	return string(runes[:maxLen]) + "......"
}

// WriteJSON pretty-prints a JSON payload with a trailing newline.
func WriteJSON(w io.Writer, payload interface{}) error {
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(payload)
}

// NameDescriptionItem is the normalized JSON item shape for list commands.
type NameDescriptionItem struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// SkillItems converts skill list results to the normalized JSON shape.
func SkillItems(skills []skill.SkillListItem) []NameDescriptionItem {
	items := make([]NameDescriptionItem, 0, len(skills))
	for _, item := range skills {
		items = append(items, NameDescriptionItem{
			Name:        item.Name,
			Description: item.Description,
		})
	}
	return items
}

// AgentSpecItems converts agent spec list results to the normalized JSON shape.
func AgentSpecItems(specs []agentspec.AgentSpecListItem) []NameDescriptionItem {
	items := make([]NameDescriptionItem, 0, len(specs))
	for _, item := range specs {
		desc := ""
		if item.Description != nil {
			desc = *item.Description
		}
		items = append(items, NameDescriptionItem{
			Name:        item.Name,
			Description: desc,
		})
	}
	return items
}
