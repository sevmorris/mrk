package main

import (
	"encoding/json"
	"io"
)

// jsonSchema is the version of the --json document. Raise it when a field
// changes meaning or goes away; a new field alone does not need it.
const jsonSchema = 1

// The --json document: the panels collect returns, for a program to read. The
// struct tags are the schema, so every field is always present, and a fix that
// does not exist is "" rather than an absent key.
type jsonReport struct {
	Schema   int         `json:"schema"`
	Severity string      `json:"severity"` // the header's: ok, warn or error
	Summary  string      `json:"summary"`  // the header's verdict, "1 warning"
	Panels   []jsonPanel `json:"panels"`
}

type jsonPanel struct {
	Name     string     `json:"name"`
	Severity string     `json:"severity"`
	Fix      string     `json:"fix"` // what f runs for this panel
	Lines    []jsonLine `json:"lines"`
}

type jsonLine struct {
	Severity string `json:"severity"`
	Text     string `json:"text"`
	Fix      string `json:"fix"`
}

// name is a severity's word in the --json document, as icon is its mark.
func (s severity) name() string {
	switch s {
	case sevOK:
		return "ok"
	case sevWarn:
		return "warn"
	case sevErr:
		return "error"
	default:
		return "info"
	}
}

// renderJSON writes the panels as one JSON document, and nothing else. The
// slices are made, not left nil, so an empty list is [] and never null.
//
// On a terminal the document is not quite alone: bubbletea's package init
// (tea_init.go, v1.1.0) asks the terminal for its background colour before
// main runs, as it does for --plain and --help. termenv asks only when stdout
// is a terminal, so a program reading a pipe gets the document alone.
func renderJSON(w io.Writer, groups []group) error {
	verdict, vsev := summary(groups)
	r := jsonReport{Schema: jsonSchema, Severity: vsev.name(), Summary: verdict,
		Panels: make([]jsonPanel, 0, len(groups))}
	for _, g := range groups {
		p := jsonPanel{Name: g.name, Severity: g.sev.name(), Fix: g.fix,
			Lines: make([]jsonLine, 0, len(g.lines))}
		for _, l := range g.lines {
			p.Lines = append(p.Lines, jsonLine{Severity: l.sev.name(), Text: l.text, Fix: l.fix})
		}
		r.Panels = append(r.Panels, p)
	}
	enc := json.NewEncoder(w)
	// A fix such as "cd x && y" stays readable: the escape is for HTML, and
	// nothing here is HTML.
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(r)
}
