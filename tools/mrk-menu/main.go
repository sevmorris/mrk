package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

// Version and GitSHA are populated at build time via -ldflags.
// Defaults below are used for `go run` / unset builds.
var (
	Version = "dev"
	GitSHA  = "unknown"
)

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
