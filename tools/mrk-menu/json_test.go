package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

// The document a program reads, through the decoder a program would use.
func decodeMenu(t *testing.T) jsonMenu {
	t.Helper()
	var buf bytes.Buffer
	if err := renderJSON(&buf); err != nil {
		t.Fatal(err)
	}
	var doc jsonMenu
	dec := json.NewDecoder(&buf)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&doc); err != nil {
		t.Fatalf("the document does not decode: %v\n%s", err, buf.String())
	}
	return doc
}

func TestJSONHasEveryItemInOrder(t *testing.T) {
	doc := decodeMenu(t)
	if doc.Schema != 1 {
		t.Errorf("schema = %d, want 1", doc.Schema)
	}
	if len(doc.Categories) != len(categories) {
		t.Fatalf("%d categories, want %d", len(doc.Categories), len(categories))
	}
	for i, c := range categories {
		jc := doc.Categories[i]
		if jc.Name != c.name || len(jc.Commands) != len(c.items) {
			t.Errorf("category %d is %q with %d commands, want %q with %d",
				i, jc.Name, len(jc.Commands), c.name, len(c.items))
			continue
		}
		for j, it := range c.items {
			if jc.Commands[j].Name != it.name || jc.Commands[j].Description != it.desc {
				t.Errorf("%s, command %d is %q, want %q", c.name, j, jc.Commands[j].Name, it.name)
			}
		}
	}
}

// One item of each kind, as the document gives it.
func TestJSONCommands(t *testing.T) {
	byName := map[string]jsonCommand{}
	for _, c := range decodeMenu(t).Categories {
		for _, cmd := range c.Commands {
			byName[cmd.Name] = cmd
		}
	}
	for _, want := range []jsonCommand{
		{Name: "sync --push", Command: "scripts/sync --push", Terminal: true},
		{Name: "mrk-push", Command: "bin/mrk-push"},
		{Name: "mrk-status", Command: "bin/mrk-status"},
		{Name: "make doctor ARGS=--fix", Command: "make doctor ARGS=--fix"},
		{Name: "tidy-projects --apply ff,refs,worktrees,branches", Command: "bin/tidy-projects --apply ff,refs,worktrees,branches"},
		{Name: "update-full", Command: "bin/update-full", Terminal: true},
		{Name: "nuke-mrk", Command: "bin/nuke-mrk", Terminal: true, TypeToConfirm: "nuke"},
	} {
		got, ok := byName[want.Name]
		if !ok {
			t.Errorf("no command %q", want.Name)
			continue
		}
		got.Description = ""
		if got != want {
			t.Errorf("%q = %+v, want %+v", want.Name, got, want)
		}
	}
}

// Only nuke-mrk asks for a word, as only it is behind the menu's gate
// (TestOnlyNukeMrkIsGated).
func TestJSONOnlyNukeMrkAsksForAWord(t *testing.T) {
	for _, c := range decodeMenu(t).Categories {
		for _, cmd := range c.Commands {
			if (cmd.TypeToConfirm != "") != (cmd.Name == "nuke-mrk") {
				t.Errorf("%q asks for %q", cmd.Name, cmd.TypeToConfirm)
			}
		}
	}
}

// Every key is present on every command, so a reader never meets a missing
// one, and an empty list is [] rather than null.
func TestJSONKeysAlwaysPresent(t *testing.T) {
	var buf bytes.Buffer
	if err := renderJSON(&buf); err != nil {
		t.Fatal(err)
	}
	var raw struct {
		Categories []struct {
			Commands []map[string]any `json:"commands"`
		} `json:"categories"`
	}
	if err := json.Unmarshal(buf.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	keys := []string{"name", "description", "command", "terminal", "type_to_confirm"}
	for _, c := range raw.Categories {
		for _, cmd := range c.Commands {
			for _, k := range keys {
				if _, ok := cmd[k]; !ok {
					t.Errorf("%v has no %q", cmd["name"], k)
				}
			}
		}
	}
	empty := menuDocument([]category{{name: "Empty"}})
	b, _ := json.Marshal(empty)
	if !strings.Contains(string(b), `"commands":[]`) {
		t.Errorf("an empty category is %s, want commands []", b)
	}
}
