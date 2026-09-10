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
		help bool
		bad  string
	}{
		{"no arguments runs the TUI", nil, false, ""},
		{"empty slice runs the TUI", []string{}, false, ""},
		{"--help", []string{"--help"}, true, ""},
		{"-h", []string{"-h"}, true, ""},
		{"an unknown flag is refused", []string{"--bogus"}, false, "--bogus"},
		{"a bare word is refused", []string{"status"}, false, "status"},
		{"-help is not -h", []string{"-help"}, false, "-help"},
		{"case matters", []string{"--HELP"}, false, "--HELP"},
		{"an extra argument after --help is refused", []string{"--help", "extra"}, false, "extra"},
		{"an extra argument after a flag is refused", []string{"--bogus", "extra"}, false, "extra"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			help, bad := parseArgs(tc.args)
			if help != tc.help || bad != tc.bad {
				t.Errorf("parseArgs(%q) = (help=%v, bad=%q), want (help=%v, bad=%q)",
					tc.args, help, bad, tc.help, tc.bad)
			}
		})
	}
}

// A refusal must never also be a help request: main switches on bad first, and
// a case that set both would print usage to stderr and exit 2 while the caller
// had asked for help on stdout.
func TestRefusalAndHelpAreExclusive(t *testing.T) {
	for _, args := range [][]string{
		nil, {}, {"--help"}, {"-h"}, {"--bogus"}, {"x"}, {"--help", "extra"},
	} {
		if help, bad := parseArgs(args); help && bad != "" {
			t.Errorf("parseArgs(%q) returned both help and bad=%q", args, bad)
		}
	}
}
