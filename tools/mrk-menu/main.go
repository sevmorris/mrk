package main

import (
	"fmt"
	"io"
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
func usage(w io.Writer) {
	fmt.Fprint(w, `mrk-menu — interactive launcher for mrk commands

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

// parseArgs decides what to do with the command line. It returns help=true when
// usage was asked for, and bad set to the argument to refuse. Extracted from
// main so the decision is testable without os.Exit.
//
// The default arm is the point. main used to compare os.Args[1] against
// "--help" and "-h" and fall straight through on anything else, so
// `mrk-menu --bogus` opened the TUI with the flag discarded — the same shape
// as the eight commands in audit/14 P-9. An extra argument was dropped too.
func parseArgs(args []string) (help bool, bad string) {
	if len(args) == 0 {
		return false, ""
	}
	if len(args) > 1 {
		return false, args[1]
	}
	switch args[0] {
	case "--help", "-h":
		return true, ""
	default:
		return false, args[0]
	}
}

func main() {
	help, bad := parseArgs(os.Args[1:])
	switch {
	case bad != "":
		usage(os.Stderr)
		fmt.Fprintf(os.Stderr, "\nunknown argument: %s\n", bad)
		os.Exit(2)
	case help:
		usage(os.Stdout)
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
