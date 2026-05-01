package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"mrk-theme"
)

// Layout sizing.
//
// chromeLines counts every vertical line outside the panes:
//
//	border (2) + window padding (2) + banner (3) + banner margin (1) +
//	subtitle row (1) + flash row (1) + spacer (1) + status (1) + help (1) = 13.
const (
	minTermW    = 80
	minTermH    = 22
	preferredW  = 100
	leftPaneW   = 30
	chromeLines = 13
	maxPaneH    = 22
	minPaneH    = 6
)

// Compact 3-line banner used as a header on every menu screen.
var bannerSmall = []string{
	"█▀▄▀█ █▀█ █▄▀",
	"█ ▀ █ █▀▄ █ █",
	"▀   ▀ ▀ ▀ ▀ ▀",
}

// Tall 6-line banner used on the splash screen.
var bannerBig = []string{
	"███╗   ███╗ ██████╗ ██╗  ██╗",
	"████╗ ████║ ██╔══██╗██║ ██╔╝",
	"██╔████╔██║ ██████╔╝█████╔╝ ",
	"██║╚██╔╝██║ ██╔══██╗██╔═██╗ ",
	"██║ ╚═╝ ██║ ██║  ██║██║  ██╗",
	"╚═╝     ╚═╝ ╚═╝  ╚═╝╚═╝  ╚═╝",
}

var (
	styleBanner    = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleSubtitle  = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleSelected  = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleNormal    = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleDesc      = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleCmd       = lipgloss.NewStyle().Foreground(theme.ColDim)
	styleWarning   = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleHelp      = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleHelpKey   = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleNukeProm  = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleStatusOK  = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleStatusErr = lipgloss.NewStyle().Foreground(theme.ColRed)
	styleVersion   = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleFilterTag = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
)

func paneCatStyle(focused bool, w, h int) lipgloss.Style {
	border := theme.ColSubtle
	if focused {
		border = theme.ColAccent
	}
	return lipgloss.NewStyle().
		Width(w).Height(h).
		PaddingRight(2).
		BorderRight(true).
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(border)
}

func paneItemStyle(w, h int) lipgloss.Style {
	return lipgloss.NewStyle().PaddingLeft(2).Width(w).Height(h)
}

func windowStyle(w int) lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.ColSubtle).
		Padding(1, 2).
		Width(w)
}

// renderBanner renders one of the banner slices, centered to width w.
func renderBanner(lines []string, w int) string {
	var b strings.Builder
	for i, line := range lines {
		pad := (w - lipgloss.Width(line)) / 2
		if pad < 0 {
			pad = 0
		}
		b.WriteString(strings.Repeat(" ", pad))
		b.WriteString(styleBanner.Render(line))
		if i < len(lines)-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return ""
	}
	if m.width < minTermW || m.height < minTermH {
		msg := fmt.Sprintf("Terminal too small (%d×%d). Resize to at least %d×%d.",
			m.width, m.height, minTermW, minTermH)
		return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
			styleWarning.Render(msg))
	}

	if m.state == stateSplash {
		return m.viewSplash()
	}

	outerW := preferredW
	if outerW > m.width {
		outerW = m.width
	}
	winW := outerW - 2

	paneH := m.height - chromeLines
	if paneH < minPaneH {
		paneH = minPaneH
	}
	if paneH > maxPaneH {
		paneH = maxPaneH
	}

	innerW := winW - 4

	switch m.state {
	case stateFilter:
		return m.viewFilter(winW, innerW, paneH)
	case stateNukeConfirm:
		return m.viewNukeConfirm(winW, innerW)
	case stateHelp:
		return m.viewHelp(winW, innerW)
	default:
		return m.viewMenu(winW, innerW, paneH)
	}
}

func (m model) viewMenu(winW, innerW, paneH int) string {
	// Left pane has Width(leftPaneW) + a 1-col BorderRight, so it actually occupies
	// leftPaneW+1 columns on screen. Subtract that from innerW to get rightW.
	rightW := innerW - leftPaneW - 1
	if rightW < 30 {
		rightW = 30
	}
	// Right pane width budget: paneItemStyle eats 2 cols of padding, content has
	// 2-char cursor or 4-char indent before the actual text. Leave 6 cols of slack.
	nameBudget := rightW - 4
	descBudget := rightW - 6
	if nameBudget < 10 {
		nameBudget = 10
	}
	if descBudget < 10 {
		descBudget = 10
	}

	var s strings.Builder
	s.WriteString(renderBanner(bannerSmall, innerW) + "\n\n")

	subtitle := "  System configuration menu"
	if m.state == stateFocusItem {
		subtitle = "  " + categories[m.cursorCat].name
	}
	s.WriteString(styleSubtitle.Render(subtitle) + "\n")

	if m.flashMsg != "" {
		s.WriteString(styleWarning.Render(m.flashMsg) + "\n")
	} else {
		s.WriteString("\n")
	}

	var leftPane strings.Builder
	for i, cat := range categories {
		num := fmt.Sprintf("%d ", i+1)
		cursor := "  "
		if i == m.cursorCat {
			cursor = "> "
		}
		line := cursor + num + cat.name
		if i == m.cursorCat && m.state == stateFocusCat {
			leftPane.WriteString(styleSelected.Render(line) + "\n")
		} else {
			leftPane.WriteString(styleNormal.Render(line) + "\n")
		}
	}

	// Right pane: each item is 2 lines (name + desc). Window around the cursor
	// so the rendered content fits paneH.
	var rightPane strings.Builder
	cat := categories[m.cursorCat]
	curIdx := m.cursorItems[m.cursorCat]
	rowsPerItem := 2
	maxItems := paneH / rowsPerItem
	if maxItems < 1 {
		maxItems = 1
	}
	start := 0
	if curIdx >= maxItems {
		start = curIdx - maxItems + 1
	}
	end := start + maxItems
	if end > len(cat.items) {
		end = len(cat.items)
	}
	for i := start; i < end; i++ {
		it := cat.items[i]
		num := fmt.Sprintf("%d ", i+1)
		cursor := "  "
		if i == curIdx {
			cursor = "> "
		}
		nameStr := theme.Truncate(num+it.name, nameBudget)
		if i == curIdx && m.state == stateFocusItem {
			nameStr = styleSelected.Render(cursor + nameStr)
		} else {
			nameStr = styleNormal.Render(cursor + nameStr)
		}
		rightPane.WriteString(nameStr + "\n")

		descStr := theme.Truncate(it.desc, descBudget)
		if i < end-1 {
			rightPane.WriteString(styleDesc.Render("    "+descStr) + "\n")
		} else {
			rightPane.WriteString(styleDesc.Render("    " + descStr))
		}
	}

	leftRendered := paneCatStyle(m.state == stateFocusCat, leftPaneW, paneH).Render(leftPane.String())
	rightRendered := paneItemStyle(rightW, paneH).Render(rightPane.String())
	s.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, leftRendered, rightRendered) + "\n\n")

	s.WriteString(m.renderStatusFooter(innerW) + "\n")

	var help string
	if m.state == stateFocusCat {
		help = "j/k nav · enter select · / filter · 1-9 jump · ? help · q quit"
	} else {
		help = "j/k nav · enter launch · esc back · / filter · ? help · q quit"
	}
	s.WriteString(styleHelp.Render(theme.Truncate(help, innerW)))

	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
		windowStyle(winW).Render(s.String()))
}

func (m model) viewFilter(winW, innerW, paneH int) string {
	var s strings.Builder
	s.WriteString(renderBanner(bannerSmall, innerW) + "\n\n")
	s.WriteString(styleSubtitle.Render("  Filter") + "\n\n")

	prompt := styleFilterTag.Render("/ ") + styleNormal.Render(m.filterInput) + styleSelected.Render("█")
	s.WriteString(prompt + "\n\n")

	listH := paneH
	if listH < 4 {
		listH = 4
	}

	var list strings.Builder
	if len(m.filterResults) == 0 {
		list.WriteString(styleSubtitle.Render("  (no matches)"))
	} else {
		// Window the result list around the cursor so it doesn't overflow.
		start := 0
		if m.filterCursor >= listH {
			start = m.filterCursor - listH + 1
		}
		end := start + listH
		if end > len(m.filterResults) {
			end = len(m.filterResults)
		}
		budget := innerW - 6
		if budget < 20 {
			budget = 20
		}
		for i := start; i < end; i++ {
			fi := m.filterResults[i]
			label := fmt.Sprintf("%s › %s", categories[fi.cat].name, fi.item.name)
			label = theme.Truncate(label, budget)
			cursor := "  "
			if i == m.filterCursor {
				cursor = "> "
				list.WriteString(styleSelected.Render(cursor+label) + "\n")
			} else {
				list.WriteString(styleNormal.Render(cursor+label) + "\n")
			}
		}
	}

	listBox := lipgloss.NewStyle().Width(innerW).Height(listH).Render(list.String())
	s.WriteString(listBox + "\n")

	s.WriteString(m.renderStatusFooter(innerW) + "\n")
	help := "type to filter · enter launch · ↑/↓ navigate · esc cancel"
	s.WriteString(styleHelp.Render(theme.Truncate(help, innerW)))

	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
		windowStyle(winW).Render(s.String()))
}

func (m model) viewNukeConfirm(winW, innerW int) string {
	var s strings.Builder
	s.WriteString(renderBanner(bannerSmall, innerW) + "\n\n")
	cat := categories[m.cursorCat]
	s.WriteString(styleSubtitle.Render("  "+cat.name) + "\n\n")
	s.WriteString(styleWarning.Render("⚠ This will remove all mrk symlinks and undo setup.") + "\n\n")
	s.WriteString(styleNormal.Render("Type ") +
		styleNukeProm.Render("nuke") +
		styleNormal.Render(" to proceed, ") +
		styleHelpKey.Render("esc") +
		styleNormal.Render(" to cancel.") + "\n\n")
	s.WriteString(styleNukeProm.Render("> ") + styleNormal.Render(m.nukeInput))

	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
		windowStyle(winW).Render(s.String()))
}

func (m model) viewHelp(winW, innerW int) string {
	var s strings.Builder
	s.WriteString(renderBanner(bannerSmall, innerW) + "\n\n")
	s.WriteString(styleSubtitle.Render("  Help") + "\n\n")
	rows := []struct{ keys, desc string }{
		{"j  k  ↑  ↓", "navigate"},
		{"enter  →  l", "select / launch"},
		{"esc  ←  h", "back"},
		{"/", "filter all items"},
		{"1 – 9", "jump to numbered entry"},
		{"?", "toggle this help"},
		{"q  ctrl-c", "quit"},
	}
	for _, r := range rows {
		s.WriteString(styleHelpKey.Render(fmt.Sprintf("  %-14s", r.keys)) +
			styleNormal.Render("  "+r.desc) + "\n")
	}
	s.WriteString("\n" + styleHelp.Render("Press esc or enter to return"))
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
		windowStyle(winW).Render(s.String()))
}

func (m model) viewSplash() string {
	var s strings.Builder
	innerW := preferredW - 6
	if innerW > m.width-6 {
		innerW = m.width - 6
	}

	s.WriteString(renderBanner(bannerBig, innerW) + "\n\n")
	tagline := "Mac Reset Kit"
	pad := (innerW - lipgloss.Width(tagline)) / 2
	if pad < 0 {
		pad = 0
	}
	s.WriteString(strings.Repeat(" ", pad) + styleNormal.Render(tagline) + "\n\n")

	versionLine := fmt.Sprintf("version %s · %s", Version, GitSHA)
	pad = (innerW - lipgloss.Width(versionLine)) / 2
	if pad < 0 {
		pad = 0
	}
	s.WriteString(strings.Repeat(" ", pad) + styleVersion.Render(versionLine) + "\n\n")

	prompt := "press any key to continue"
	pad = (innerW - lipgloss.Width(prompt)) / 2
	if pad < 0 {
		pad = 0
	}
	s.WriteString(strings.Repeat(" ", pad) + styleHelp.Render(prompt))

	winW := preferredW - 2
	if winW > m.width-2 {
		winW = m.width - 2
	}
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
		windowStyle(winW).Render(s.String()))
}

// renderStatusFooter shows: $ <selected command preview>     [last result]
func (m model) renderStatusFooter(innerW int) string {
	var preview string
	if it := m.selectedItem(); it != nil {
		preview = "$ " + it.commandLine()
	}

	var status string
	if m.lastExitMsg != "" {
		if m.lastExitOK {
			status = styleStatusOK.Render("✓ " + m.lastExitMsg)
		} else {
			status = styleStatusErr.Render("✗ " + m.lastExitMsg)
		}
	}

	previewBudget := innerW - lipgloss.Width(status) - 2
	if previewBudget < 10 {
		previewBudget = 10
	}
	preview = theme.Truncate(preview, previewBudget)

	gap := innerW - lipgloss.Width(preview) - lipgloss.Width(status)
	if gap < 1 {
		gap = 1
	}
	return styleCmd.Render(preview) + strings.Repeat(" ", gap) + status
}
