package main

import (
	"os"
	"regexp"
	"testing"
)

// The Brewfile's apps are filed under `## Casks - X` sections, and scripts/sync
// names X from the category an app declares, through the SECTIONS table in the
// Python of brew_describe in scripts/lib.sh. categoryName shortens a section header for the left pane,
// and it cuts at " & " and " / " and keeps the part after " - " only when that
// part is two words or fewer. A cask section named "Graphics & Design" would
// come out as "Applications", the name of no section at all. So every name sync
// can produce, and every cask section the Brewfile has now, must come through
// categoryName as itself.

func syncSectionNames(t *testing.T) []string {
	t.Helper()
	src, err := os.ReadFile("../../scripts/lib.sh")
	if err != nil {
		t.Fatalf("read scripts/lib.sh: %v", err)
	}
	table := regexp.MustCompile(`(?s)SECTIONS = \{(.*?)\n\}`).FindSubmatch(src)
	if table == nil {
		t.Fatal("no SECTIONS table in scripts/lib.sh")
	}
	var names []string
	for _, m := range regexp.MustCompile(`'[a-z-]+': '([^']+)',`).FindAllSubmatch(table[1], -1) {
		names = append(names, string(m[1]))
	}
	fallback := regexp.MustCompile(`FALLBACK = '([^']+)'`).FindSubmatch(src)
	if fallback == nil {
		t.Fatal("no FALLBACK in scripts/lib.sh")
	}
	names = append(names, string(fallback[1]))
	if len(names) < 10 {
		t.Fatalf("read only %d section names from scripts/lib.sh", len(names))
	}
	return names
}

func brewfileCaskSections(t *testing.T) []string {
	t.Helper()
	src, err := os.ReadFile("../../Brewfile")
	if err != nil {
		t.Fatalf("read Brewfile: %v", err)
	}
	var names []string
	for _, m := range regexp.MustCompile(`(?m)^## Casks - (.+)$`).FindAllSubmatch(src, -1) {
		names = append(names, string(m[1]))
	}
	if len(names) == 0 {
		t.Fatal("no `## Casks - X` sections in the Brewfile")
	}
	return names
}

func TestCaskSectionNamesSurviveCategoryName(t *testing.T) {
	for _, name := range append(syncSectionNames(t), brewfileCaskSections(t)...) {
		if got := categoryName("Casks - " + name); got != name {
			t.Errorf("categoryName(%q) = %q, want %q", "Casks - "+name, got, name)
		}
	}
}

// Each cask section is its own category in the picker, distinct from the
// formula sections' names too, or two sections would share one pane entry.
func TestBrewfileCategoriesAreDistinct(t *testing.T) {
	cats, err := parseBrewfile("../../Brewfile", nil, nil, false, false)
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, c := range cats {
		if seen[c.name] {
			t.Errorf("two Brewfile sections are both shown as %q", c.name)
		}
		seen[c.name] = true
	}
	for _, name := range brewfileCaskSections(t) {
		if !seen[name] {
			t.Errorf("cask section %q is not a picker category", name)
		}
	}
}
