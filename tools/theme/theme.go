// Package theme provides shared lipgloss colors and styles for mrk TUI tools.
package theme

import "github.com/charmbracelet/lipgloss"

// ── Shared palette ───────────────────────────────────────────────────────────

var (
	ColSubtle    = lipgloss.AdaptiveColor{Light: "#888888", Dark: "#555555"}
	ColDim       = lipgloss.AdaptiveColor{Light: "#aaaaaa", Dark: "#444444"}
	ColNormal    = lipgloss.AdaptiveColor{Light: "#222222", Dark: "#cccccc"}
	ColHighlight = lipgloss.AdaptiveColor{Light: "#d7005f", Dark: "#ff87af"}
	ColAccent    = lipgloss.AdaptiveColor{Light: "#005fd7", Dark: "#87d7ff"}
	ColGreen     = lipgloss.AdaptiveColor{Light: "#00875f", Dark: "#5fd7a7"}
	ColAmber     = lipgloss.AdaptiveColor{Light: "#875f00", Dark: "#ffd787"}
	ColRed       = lipgloss.AdaptiveColor{Light: "#af0000", Dark: "#ff8787"}
)

// ── Shared styles ────────────────────────────────────────────────────────────

var (
	StylePaneOff = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColSubtle)
	StylePaneOn = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColAccent)

	StyleTitle  = lipgloss.NewStyle().Bold(true).Foreground(ColNormal)
	StyleFooter = lipgloss.NewStyle().Foreground(ColSubtle)
)
