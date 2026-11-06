package main

import (
	"encoding/json"
	"io"
)

// jsonSchema is the version of the --json document. Raise it when a key
// changes meaning or goes away; a new key alone does not need it.
const jsonSchema = 1

// The --json document: the menu's categories and items, in the menu's order,
// for a program that offers the same commands. Dipstick's Commands pane reads
// it, so a change to this list, or to these keys, is a change to Dipstick.
// The struct tags are the schema, so every key is always present.
type jsonMenu struct {
	Schema     int            `json:"schema"`
	Categories []jsonCategory `json:"categories"`
}

type jsonCategory struct {
	Name     string        `json:"name"`
	Commands []jsonCommand `json:"commands"`
}

type jsonCommand struct {
	// Name is the menu's label, which is the command as a person types it
	// (TestLabelIsTheCommandItRuns).
	Name        string `json:"name"`
	Description string `json:"description"`
	// Command is the line to run in the checkout: bin/TOOL, scripts/TOOL or
	// make TARGET, with the item's arguments (shellLine).
	Command string `json:"command"`
	// Terminal is true when the command must run in a terminal of its own
	// (terminalTools).
	Terminal bool `json:"terminal"`
	// TypeToConfirm is the word a person must type before the command runs,
	// or "" for none.
	TypeToConfirm string `json:"type_to_confirm"`
}

// menuDocument is the --json document for cats.
func menuDocument(cats []category) jsonMenu {
	doc := jsonMenu{Schema: jsonSchema, Categories: make([]jsonCategory, 0, len(cats))}
	for _, c := range cats {
		jc := jsonCategory{Name: c.name, Commands: make([]jsonCommand, 0, len(c.items))}
		for _, it := range c.items {
			confirm := ""
			if it.needsNuke {
				confirm = nukeWord
			}
			jc.Commands = append(jc.Commands, jsonCommand{
				Name:          it.name,
				Description:   it.desc,
				Command:       it.shellLine(),
				Terminal:      terminalTools[it.target],
				TypeToConfirm: confirm,
			})
		}
		doc.Categories = append(doc.Categories, jc)
	}
	return doc
}

// renderJSON writes the menu as one JSON document, and nothing else.
//
// On a terminal the document is not quite alone: bubbletea's package init
// asks the terminal for its background colour before main runs, as mrk-status
// --json's does. termenv asks only when stdout is a terminal, so a program
// reading a pipe gets the document alone.
func renderJSON(w io.Writer) error {
	enc := json.NewEncoder(w)
	// A command such as "make doctor ARGS=--fix" stays readable: the escape is
	// for HTML, and nothing here is HTML.
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(menuDocument(categories))
}
