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
		want options
		bad  string
	}{
		{"no arguments runs the TUI", nil, options{}, ""},
		{"empty slice runs the TUI", []string{}, options{}, ""},
		{"--help", []string{"--help"}, options{help: true}, ""},
		{"-h", []string{"-h"}, options{help: true}, ""},
		{"--plain prints the panels", []string{"--plain"}, options{plain: true}, ""},
		{"an unknown flag is refused", []string{"--bogus"}, options{}, "--bogus"},
		{"a bare word is refused", []string{"status"}, options{}, "status"},
		{"-help is not -h", []string{"-help"}, options{}, "-help"},
		{"case matters", []string{"--HELP"}, options{}, "--HELP"},
		{"an extra argument after --help is refused", []string{"--help", "extra"}, options{}, "extra"},
		{"an extra argument after --plain is refused", []string{"--plain", "extra"}, options{}, "extra"},
		{"an extra argument after a flag is refused", []string{"--bogus", "extra"}, options{}, "extra"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, bad := parseArgs(tc.args)
			if got != tc.want || bad != tc.bad {
				t.Errorf("parseArgs(%q) = (%+v, bad=%q), want (%+v, bad=%q)",
					tc.args, got, bad, tc.want, tc.bad)
			}
		})
	}
}

// A refusal must never also be a help request: main switches on bad first, and
// a case that set both would print usage to stderr and exit 2 while the caller
// had asked for help on stdout.
func TestRefusalAndHelpAreExclusive(t *testing.T) {
	for _, args := range [][]string{
		nil, {}, {"--help"}, {"-h"}, {"--plain"}, {"--bogus"}, {"x"}, {"--help", "extra"},
	} {
		if opts, bad := parseArgs(args); (opts.help || opts.plain) && bad != "" {
			t.Errorf("parseArgs(%q) returned both %+v and bad=%q", args, opts, bad)
		}
	}
}
