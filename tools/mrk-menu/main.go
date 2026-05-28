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
	opts := []tea.ProgramOption{tea.WithAltScreen()}
	if tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0); err == nil {
		defer tty.Close()
		opts = append(opts, tea.WithInput(tty), tea.WithOutput(tty))
	}
	p := tea.NewProgram(initialModel(), opts...)
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
