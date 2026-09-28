package main

import (
	"bytes"
	"errors"
	"flag"
	"strings"
	"testing"
)

func TestParseFlagsRefusesAStrayArgument(t *testing.T) {
	// Until 2026-09-28 flag.Args() was never checked, so a stray argument was
	// dropped and the picker opened anyway (audit 19, W-24).
	var out bytes.Buffer
	_, err := parseFlags([]string{"--brewfile", "Brewfile", "bogus"}, &out)
	if err == nil || !strings.Contains(err.Error(), "bogus") {
		t.Errorf("a stray argument should be refused by name; got %v", err)
	}
	if !strings.Contains(out.String(), "-brewfile") {
		t.Errorf("the refusal should print the flags; got %q", out.String())
	}
}

func TestParseFlagsReadsEveryFlag(t *testing.T) {
	o, err := parseFlags([]string{"--brewfile", "B", "--installed-formulae", "a,b",
		"--installed-casks", "c", "--skip-formulae", "--skip-casks", "--no-ignore"}, &bytes.Buffer{})
	if err != nil {
		t.Fatal(err)
	}
	want := options{"B", "a,b", "c", true, true, true}
	if o != want {
		t.Errorf("got %+v, want %+v", o, want)
	}
}

func TestParseFlagsHelpListsNoIgnore(t *testing.T) {
	// mrk brew runs `mrk-picker -h` and looks for -no-ignore before passing it,
	// because an older picker would take the unknown flag for a cancel.
	var out bytes.Buffer
	_, err := parseFlags([]string{"-h"}, &out)
	if !errors.Is(err, flag.ErrHelp) {
		t.Errorf("-h should return flag.ErrHelp, got %v", err)
	}
	if !strings.Contains(out.String(), "-no-ignore") {
		t.Errorf("-h output should list -no-ignore:\n%s", out.String())
	}
}
