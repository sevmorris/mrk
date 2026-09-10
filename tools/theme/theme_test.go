package theme

import "testing"

// This package had no tests at all — `make check` printed
// "? mrk-theme [no test files]" on every run — while being the shared helper
// all three TUIs render through, with twelve call sites between them. It is
// also where F05 lived: Truncate cut by byte rather than by rune, so a
// multi-byte character could be sliced in half.

func TestTruncate(t *testing.T) {
	for _, tc := range []struct {
		name string
		s    string
		n    int
		want string
	}{
		{"shorter than the limit is untouched", "hello", 10, "hello"},
		{"exactly the limit is untouched", "hello", 5, "hello"},
		{"one over gets an ellipsis", "hello", 4, "hel…"},
		{"limit of one is just the ellipsis", "hello", 1, "…"},
		{"empty string, zero width", "", 0, ""},
		{"empty string, room to spare", "", 5, ""},

		// A width-limiting function must never return more than it was asked
		// for. These returned "…" — one column — before 2026-09-10.
		{"zero width yields nothing", "hello", 0, ""},
		{"negative width yields nothing", "hello", -3, ""},

		// F05: cutting by byte would split these mid-character.
		{"multi-byte is cut by rune", "héllo wörld", 6, "héllo…"},
		{"accented string under the limit", "héllo", 5, "héllo"},
		{"wide characters are cut by rune", "日本語テキスト", 4, "日本語…"},
		{"emoji are cut by rune", "a😀b😀c", 3, "a😀…"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := Truncate(tc.s, tc.n); got != tc.want {
				t.Errorf("Truncate(%q, %d) = %q, want %q", tc.s, tc.n, got, tc.want)
			}
		})
	}
}

// The property that matters at every call site: the result is never wider than
// the budget. Asserted over the table above plus a sweep, because the callers
// compute their budgets by subtraction and a wrong answer here overflows a pane.
func TestTruncateNeverExceedsItsBudget(t *testing.T) {
	inputs := []string{"", "a", "hello world", "héllo wörld", "日本語テキスト", "a😀b😀c",
		"↑↓/jk move · tab/hl pane · space add · i ignore · a all · enter ok · q quit"}
	for _, s := range inputs {
		for n := -5; n <= 30; n++ {
			got := []rune(Truncate(s, n))
			budget := n
			if budget < 0 {
				budget = 0
			}
			if len(got) > budget {
				t.Errorf("Truncate(%q, %d) returned %d runes, over its %d budget: %q",
					s, n, len(got), budget, string(got))
			}
		}
	}
}

// Truncate counts runes, not display columns, and for CJK those differ: the
// three runes of "日本語" occupy six columns. Every string mrk renders through
// it is ASCII plus a few punctuation marks, so this is recorded rather than
// fixed — the test pins the actual behaviour so the limitation is visible to
// whoever first passes it something wider.
func TestTruncateCountsRunesNotColumns(t *testing.T) {
	if got := Truncate("日本語テキスト", 4); got != "日本語…" {
		t.Fatalf("unexpected: %q", got)
	}
	if n := len([]rune("日本語…")); n != 4 {
		t.Fatalf("expected 4 runes, got %d", n)
	}
}
