package main

import (
	"strings"
	"testing"
)

// descriptions.tsv is written as plain lines by sync, check-picker-desc --fix
// and Barkeep, and nothing but these tests reads it as the picker does. The
// compiler used to check the table, when it was a map literal in main.go; the
// parser and these tests now carry that check.

func TestDescriptionsTableParses(t *testing.T) {
	if descriptionsErr != nil {
		t.Fatalf("the embedded table: %v", descriptionsErr)
	}
	if len(descriptions) < 100 {
		t.Errorf("the embedded table holds %d descriptions; the Brewfile has more packages than that", len(descriptions))
	}
}

// The writers keep the lines in byte order of the name, which a writer can do
// without a parser: a new line goes before the first name that sorts after it.
func TestDescriptionsTableInNameOrder(t *testing.T) {
	prev := ""
	for i, line := range strings.Split(descriptionsTSV, "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, _, _ := strings.Cut(line, "\t")
		if prev != "" && name <= prev {
			t.Errorf("descriptions.tsv line %d: %s comes after %s, and must come before it", i+1, name, prev)
		}
		prev = name
	}
}

// The table reaches the picker: every package parseBrewfile reads from the
// repository's Brewfile is shown with a description. check-picker-desc holds
// the two files to each other by name; this holds what the picker builds.
func TestBrewfilePackagesAllDescribed(t *testing.T) {
	cats, err := parseBrewfile("../../Brewfile", nil, nil, false, false)
	if err != nil {
		t.Fatalf("parse ../../Brewfile: %v", err)
	}
	n := 0
	for _, c := range cats {
		for _, p := range c.pkgs {
			n++
			if p.desc == "" {
				t.Errorf("%s %s has no description in descriptions.tsv", p.kind, p.name)
			}
		}
	}
	if n == 0 {
		t.Fatal("parseBrewfile read no packages from ../../Brewfile")
	}
}

func TestParseDescriptionsShape(t *testing.T) {
	got, err := parseDescriptions("# a comment\n\n" +
		"bash-completion@2\tTab completion — for bash\n" +
		"4k-video-downloader+\tEdits \"quoted\" paths like C:\\temp # not a comment\n")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"bash-completion@2":    "Tab completion — for bash",
		"4k-video-downloader+": `Edits "quoted" paths like C:\temp # not a comment`,
	}
	if len(got) != len(want) {
		t.Errorf("got %d entries, want %d: %v", len(got), len(want), got)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s: got %q, want %q", k, got[k], v)
		}
	}
}

func TestParseDescriptionsRefuses(t *testing.T) {
	for _, c := range []struct{ table, why string }{
		{"git    Distributed version control\n", "no tab"},
		{"git\tDistributed\tversion control\n", "more than one tab"},
		{"\tDistributed version control\n", "an empty name"},
		{"git\t\n", "an empty description"},
		{"git\tone\nzsh\tshell\ngit\ttwo\n", "described twice"},
		{"git\tDistributed version control\r\n", "a carriage return"},
	} {
		if _, err := parseDescriptions(c.table); err == nil {
			t.Errorf("%s: %q parsed without an error", c.why, c.table)
		} else if !strings.Contains(err.Error(), "line ") {
			t.Errorf("%s: the error does not name the line: %v", c.why, err)
		}
	}
}
