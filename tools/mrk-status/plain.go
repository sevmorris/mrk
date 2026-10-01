package main

import (
	"fmt"
	"io"
	"strings"
)

// summary is the header's verdict on a set of panels.
func summary(groups []group) (string, severity) {
	warns, errs := 0, 0
	for _, g := range groups {
		switch g.sev {
		case sevWarn:
			warns++
		case sevErr:
			errs++
		}
	}
	var parts []string
	if errs > 0 {
		parts = append(parts, plural(errs, "error", "errors"))
	}
	if warns > 0 {
		parts = append(parts, plural(warns, "warning", "warnings"))
	}
	switch {
	case errs > 0:
		return strings.Join(parts, ", "), sevErr
	case warns > 0:
		return strings.Join(parts, ", "), sevWarn
	}
	return "all clear", sevOK
}

// renderPlain prints the panels as text: the dashboard for a shell with no
// terminal to draw in, and what scripts/status and make status print. Until
// 2026-09-30 scripts/status was a second implementation of the checks in bash.
// lipgloss colours the output only when stdout is a terminal.
func renderPlain(w io.Writer, groups []group) {
	verdict, vsev := summary(groups)
	fmt.Fprintf(w, "%s  %s\n", styleTitle.Render("mrk-status"), sevStyle(vsev).Render(verdict))
	for _, g := range groups {
		fmt.Fprintf(w, "\n%s %s\n", sevStyle(g.sev).Render(g.sev.icon()), styleTitle.Render(g.name))
		for _, l := range g.lines {
			line := "    " + sevStyle(l.sev).Render(l.sev.icon()) + " " + l.text
			if l.fix != "" {
				line += styleDim.Render("  → " + l.fix)
			}
			fmt.Fprintln(w, line)
		}
	}
}
