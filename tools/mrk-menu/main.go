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

// usage mirrors mrk-status's, and its key list is taken from viewHelp so the
// two cannot drift. mrk-menu was the only one of the three TUIs with no --help:
// it tried to open a TTY, failed, and exited 1, which is a confusing answer to
// a reasonable question.
func usage() {
	fmt.Print(`mrk-menu — interactive launcher for mrk commands

Usage:
  mrk-menu            Open the TUI launcher
  mrk-menu --help     Show this help

TUI keys:
  j  k  ↑  ↓          Navigate
  enter  →  l         Select / launch
  esc  ←  h           Back
  /                   Filter all items
  1 – 9               Jump to a numbered entry
  ?                   Toggle the in-app help
  q  ctrl-c           Quit

Running a destructive item asks for confirmation first: nuke-mrk requires the
word "nuke" typed exactly, and anything else cancels.
`)
}

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		usage()
		return
	}

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
