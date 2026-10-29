package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// --json is for a program to read, so its shape is held here key by key: a
// renamed field or a null where a list was expected breaks the reader without
// breaking anything in this repository.

// decodeOne decodes out as exactly one JSON value, and fails if anything
// follows it.
func decodeOne(t *testing.T, out []byte, v any) {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(out))
	if err := dec.Decode(v); err != nil {
		t.Fatalf("output is not JSON: %v\n%s", err, out)
	}
	if _, err := dec.Token(); err != io.EOF {
		t.Fatalf("something follows the JSON document (err=%v):\n%s", err, out)
	}
}

func keys(m map[string]any) string {
	var ks []string
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return strings.Join(ks, ",")
}

func TestJSONShape(t *testing.T) {
	groups := []group{
		{"Unrecorded", sevWarn, []statusLine{
			slFix(sevWarn, "1 package installed but not in the Brewfile: jq", fixSyncAdd),
			sl(sevOK, "~/mrk: committed and pushed"),
			slFix(sevInfo, "a <suggestion> & more", `make setup ARGS="--only shell" && exec zsh`),
		}, fixSyncAdd},
		{"Time Machine Backups", sevErr, []statusLine{sl(sevErr, "Last backup 9 days ago")}, ""},
		{"Empty", sevInfo, nil, ""},
	}
	var b bytes.Buffer
	if err := renderJSON(&b, groups); err != nil {
		t.Fatal(err)
	}
	out := b.Bytes()
	if bytes.Contains(out, []byte("\x1b[")) {
		t.Errorf("JSON should carry no colour codes:\n%q", out)
	}
	if !bytes.Contains(out, []byte(`ARGS=\"--only shell\" && exec zsh`)) {
		t.Errorf("a fix should keep && and <> as they are, not as \\u0026:\n%s", out)
	}

	var doc map[string]any
	decodeOne(t, out, &doc)
	if got := keys(doc); got != "panels,schema,severity,summary" {
		t.Errorf("top-level keys = %s", got)
	}
	if doc["schema"] != float64(1) || doc["severity"] != "error" || doc["summary"] != "1 error, 1 warning" {
		t.Errorf("header = schema %v, severity %v, summary %v", doc["schema"], doc["severity"], doc["summary"])
	}
	panels, ok := doc["panels"].([]any)
	if !ok || len(panels) != 3 {
		t.Fatalf("panels = %#v, want a list of 3", doc["panels"])
	}
	for i, want := range []struct{ name, sev, fix string }{
		{"Unrecorded", "warn", fixSyncAdd},
		{"Time Machine Backups", "error", ""},
		{"Empty", "info", ""},
	} {
		p := panels[i].(map[string]any)
		if got := keys(p); got != "fix,lines,name,severity" {
			t.Errorf("panel %d keys = %s", i, got)
		}
		if p["name"] != want.name || p["severity"] != want.sev || p["fix"] != want.fix {
			t.Errorf("panel %d = %v %v %q, want %s %s %q", i, p["name"], p["severity"], p["fix"], want.name, want.sev, want.fix)
		}
		if _, ok := p["lines"].([]any); !ok {
			t.Errorf("panel %d lines = %#v, want a list, never null", i, p["lines"])
		}
	}
	lines := panels[0].(map[string]any)["lines"].([]any)
	for i, want := range []struct{ sev, text, fix string }{
		{"warn", "1 package installed but not in the Brewfile: jq", fixSyncAdd},
		{"ok", "~/mrk: committed and pushed", ""},
		{"info", "a <suggestion> & more", `make setup ARGS="--only shell" && exec zsh`},
	} {
		l := lines[i].(map[string]any)
		if got := keys(l); got != "fix,severity,text" {
			t.Errorf("line %d keys = %s", i, got)
		}
		if l["severity"] != want.sev || l["text"] != want.text || l["fix"] != want.fix {
			t.Errorf("line %d = %v %q %q, want %s %q %q", i, l["severity"], l["text"], l["fix"], want.sev, want.text, want.fix)
		}
	}
}

// publishedSchemas holds the keys of each schema that a program reads. A key
// may be added with no new schema, but none of these may be renamed or deleted
// while jsonSchema is the schema that lists it: raise jsonSchema, and add the
// next schema's keys here. Never edit a published list. TestJSONShape pins
// the exact keys, which a change edits with the code; this list is what a
// reader was promised (audit 22, Z-13).
var publishedSchemas = map[int]struct{ top, panel, line []string }{
	1: {
		top:   []string{"panels", "schema", "severity", "summary"},
		panel: []string{"fix", "lines", "name", "severity"},
		line:  []string{"fix", "severity", "text"},
	},
}

func TestJSONKeepsItsPublishedSchema(t *testing.T) {
	want, ok := publishedSchemas[jsonSchema]
	if !ok {
		t.Fatalf("schema %d has no list of keys in publishedSchemas: add it with the change that raised jsonSchema", jsonSchema)
	}
	var b bytes.Buffer
	if err := renderJSON(&b, []group{{"P", sevWarn, []statusLine{slFix(sevWarn, "t", fixPull)}, fixPull}}); err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	decodeOne(t, b.Bytes(), &doc)
	if doc["schema"] != float64(jsonSchema) {
		t.Fatalf("schema = %v, want %d", doc["schema"], jsonSchema)
	}
	panel := doc["panels"].([]any)[0].(map[string]any)
	line := panel["lines"].([]any)[0].(map[string]any)
	for _, c := range []struct {
		what string
		m    map[string]any
		keys []string
	}{{"the document", doc, want.top}, {"a panel", panel, want.panel}, {"a line", line, want.line}} {
		for _, k := range c.keys {
			if _, ok := c.m[k]; !ok {
				t.Errorf("%s has no %q, which schema %d promises: raise jsonSchema to rename or delete a key", c.what, k, jsonSchema)
			}
		}
	}
}

func TestJSONWithNoPanels(t *testing.T) {
	var b bytes.Buffer
	if err := renderJSON(&b, nil); err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	decodeOne(t, b.Bytes(), &doc)
	if p, ok := doc["panels"].([]any); !ok || len(p) != 0 {
		t.Errorf("panels = %#v, want [], never null", doc["panels"])
	}
	if doc["severity"] != "ok" || doc["summary"] != "all clear" {
		t.Errorf("header = %v %v, want ok, all clear", doc["severity"], doc["summary"])
	}
}

// Each severity has its own word, so a reader can tell them apart.
func TestSeverityNames(t *testing.T) {
	seen := map[string]severity{}
	for s, want := range map[severity]string{sevOK: "ok", sevInfo: "info", sevWarn: "warn", sevErr: "error"} {
		if got := s.name(); got != want {
			t.Errorf("severity %d name = %q, want %q", s, got, want)
		}
		if prev, dup := seen[s.name()]; dup {
			t.Errorf("severities %d and %d share the name %q", prev, s, s.name())
		}
		seen[s.name()] = s
	}
}

// The real checks, as TestPanelsComeDailyFirst runs them, read back through
// the document's own types.
func TestJSONOfTheDashboard(t *testing.T) {
	upkeepFixtures(t, "")
	old := tmPlist
	tmPlist = filepath.Join(t.TempDir(), "tm.plist")
	t.Cleanup(func() { tmPlist = old })
	write(t, tmPlist, plistXML(`<dict/>`))
	repo := mrkRepo(t)
	write(t, filepath.Join(repo, "scripts", "sync"), "#!/bin/sh\nexit 0\n")
	if err := os.Chmod(filepath.Join(repo, "scripts", "sync"), 0o755); err != nil {
		t.Fatal(err)
	}
	groups := collect(repo, t.TempDir(), t.TempDir())
	var b bytes.Buffer
	if err := renderJSON(&b, groups); err != nil {
		t.Fatal(err)
	}
	var r jsonReport
	decodeOne(t, b.Bytes(), &r)
	if len(r.Panels) != len(groups) {
		t.Fatalf("%d panels, want %d", len(r.Panels), len(groups))
	}
	for i, g := range groups {
		p := r.Panels[i]
		if p.Name != g.name || p.Severity != g.sev.name() || p.Fix != g.fix || len(p.Lines) != len(g.lines) {
			t.Errorf("panel %d = %s %s %q (%d lines), want %s %s %q (%d lines)",
				i, p.Name, p.Severity, p.Fix, len(p.Lines), g.name, g.sev.name(), g.fix, len(g.lines))
		}
	}
	verdict, vsev := summary(groups)
	if r.Summary != verdict || r.Severity != vsev.name() {
		t.Errorf("header = %s %q, want %s %q", r.Severity, r.Summary, vsev.name(), verdict)
	}
}
