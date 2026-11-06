package main

import "testing"

// main used to compare os.Args[1] against "--help" and "-h" and fall through on
// anything else, so an unrecognised flag was discarded and the TUI opened
// anyway. A second argument was dropped even when the first was valid. Both are
// the shape recorded as audit/14 P-9.
//
// parseArgs exists so that decision can be tested without os.Exit.

func TestParseArgs(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		act  action
		bad  string
	}{
		{"no arguments runs the TUI", nil, actTUI, ""},
		{"empty slice runs the TUI", []string{}, actTUI, ""},
		{"--help", []string{"--help"}, actHelp, ""},
		{"-h", []string{"-h"}, actHelp, ""},
		{"--json", []string{"--json"}, actJSON, ""},
		{"an unknown flag is refused", []string{"--bogus"}, actTUI, "--bogus"},
		{"a bare word is refused", []string{"status"}, actTUI, "status"},
		{"-help is not -h", []string{"-help"}, actTUI, "-help"},
		{"-json is not --json", []string{"-json"}, actTUI, "-json"},
		{"case matters", []string{"--HELP"}, actTUI, "--HELP"},
		{"an extra argument after --help is refused", []string{"--help", "extra"}, actTUI, "extra"},
		{"an extra argument after --json is refused", []string{"--json", "extra"}, actTUI, "extra"},
		{"an extra argument after a flag is refused", []string{"--bogus", "extra"}, actTUI, "extra"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			act, bad := parseArgs(tc.args)
			if act != tc.act || bad != tc.bad {
				t.Errorf("parseArgs(%q) = (act=%v, bad=%q), want (act=%v, bad=%q)",
					tc.args, act, bad, tc.act, tc.bad)
			}
		})
	}
}

// A refusal must never also be a request for help or for the document: main
// switches on bad first, and a case that set both would print usage to stderr
// and exit 2 while the caller had asked for output on stdout.
func TestRefusalIsAlwaysTheTUIAction(t *testing.T) {
	for _, args := range [][]string{
		nil, {}, {"--help"}, {"-h"}, {"--json"}, {"--bogus"}, {"x"}, {"--help", "extra"}, {"--json", "extra"},
	} {
		if act, bad := parseArgs(args); act != actTUI && bad != "" {
			t.Errorf("parseArgs(%q) returned act=%v and bad=%q", args, act, bad)
		}
	}
}
