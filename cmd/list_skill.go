package cmd

import (
	"fmt"
	"os"

	"github.com/nacos-group/nacos-cli/internal/help"
	"github.com/nacos-group/nacos-cli/internal/listformat"
	"github.com/nacos-group/nacos-cli/internal/skill"
	"github.com/nacos-group/nacos-cli/internal/util"
	"github.com/spf13/cobra"
)

var (
	skillListPage   int
	skillListSize   int
	skillListName   string
	skillListFormat string
)

var listSkillCmd = &cobra.Command{
	Use:   "skill-list",
	Short: "List all skills",
	Long:  help.SkillList.FormatForCLI("nacos-cli"),
	Run: func(cmd *cobra.Command, args []string) {
		checkError(listformat.ValidateFormat(skillListFormat))

		// Create Nacos client
		nacosClient := mustNewNacosClient()

		// Create skill service
		skillService := skill.NewSkillService(nacosClient)

		// List skills
		skills, totalCount, err := skillService.ListSkills(skillListName, skillListPage, skillListSize)
		checkError(err)

		if listformat.NormalizeFormat(skillListFormat) == listformat.FormatJSON {
			checkError(listformat.WriteJSON(os.Stdout, map[string]interface{}{
				"totalCount": totalCount,
				"page":       skillListPage,
				"size":       skillListSize,
				"items":      skills,
			}))
			return
		}

		// Display results
		if len(skills) == 0 {
			fmt.Println("No skills found")
			return
		}

		asciiMode := os.Getenv("NO_UNICODE_OUTPUT") != ""
		separator := util.SeparatorLine(79, asciiMode)

		fmt.Printf("Skill List (Total: %d)\n", totalCount)
		fmt.Println(separator)
		for i, skill := range skills {
			if skill.Description != "" {
				desc := listformat.TruncateDesc(skill.Description, listformat.DefaultDescLimit)
				fmt.Printf("%3d. %s - %s\n", i+1, skill.Name, desc)
			} else {
				fmt.Printf("%3d. %s\n", i+1, skill.Name)
			}
		}
	},
}

func init() {
	listSkillCmd.Flags().IntVar(&skillListPage, "page", 1, "Page number (default: 1)")
	listSkillCmd.Flags().IntVar(&skillListSize, "size", 20, "Page size (default: 20)")
	listSkillCmd.Flags().StringVar(&skillListName, "name", "", "Filter by skill name (supports wildcard *)")
	listSkillCmd.Flags().StringVar(&skillListFormat, "format", listformat.FormatText, "Output format: text or json")
	rootCmd.AddCommand(listSkillCmd)
}
