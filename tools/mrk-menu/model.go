package main

import (
	"strings"
)

type state int

const (
	stateSplash state = iota
	stateFocusCat
	stateFocusItem
	stateFilter
	stateNukeConfirm
	stateHelp
)

// flatItem is a flattened view of a category+item used by filter mode.
type flatItem struct {
	cat  int
	idx  int
	item item
}

type model struct {
	state     state
	prevState state

	cursorCat   int
	cursorItems []int

	// Filter mode
	filterInput   string
	filterCursor  int
	filterResults []flatItem

	// Nuke confirmation
	nukeInput string

	// Status footer
	flashMsg     string
	lastExitMsg  string
	lastExitOK   bool
	lastItemName string

	width  int
	height int
}

func initialModel() model {
	return model{
		state:       stateSplash,
		cursorItems: make([]int, len(categories)),
	}
}

// flattenItems returns every (cat, idx, item) tuple across all categories.
func flattenItems() []flatItem {
	var out []flatItem
	for ci, c := range categories {
		for ii, it := range c.items {
			out = append(out, flatItem{cat: ci, idx: ii, item: it})
		}
	}
	return out
}

// applyFilter recomputes filterResults based on filterInput.
// Substring match (case-insensitive) against name + description + category name.
func (m *model) applyFilter() {
	q := strings.ToLower(strings.TrimSpace(m.filterInput))
	all := flattenItems()
	if q == "" {
		m.filterResults = all
	} else {
		var matched []flatItem
		for _, fi := range all {
			hay := strings.ToLower(fi.item.name + " " + fi.item.desc + " " + categories[fi.cat].name)
			if strings.Contains(hay, q) {
				matched = append(matched, fi)
			}
		}
		m.filterResults = matched
	}
	if m.filterCursor >= len(m.filterResults) {
		m.filterCursor = len(m.filterResults) - 1
	}
	if m.filterCursor < 0 {
		m.filterCursor = 0
	}
}

// selectedItem returns the item the cursor is currently on, in either menu state.
// Returns nil if there is no current item (e.g. splash).
func (m *model) selectedItem() *item {
	switch m.state {
	case stateFocusCat, stateFocusItem:
		if m.cursorCat < 0 || m.cursorCat >= len(categories) {
			return nil
		}
		items := categories[m.cursorCat].items
		idx := m.cursorItems[m.cursorCat]
		if idx < 0 || idx >= len(items) {
			return nil
		}
		return &items[idx]
	case stateFilter:
		if m.filterCursor < 0 || m.filterCursor >= len(m.filterResults) {
			return nil
		}
		it := m.filterResults[m.filterCursor].item
		return &it
	}
	return nil
}
