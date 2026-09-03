package services

import (
	"regexp"
	"strings"
)

// This file turns the AI's Markdown-ish output into a structure both the
// DOCX exporter (export_controller.go) and the PDF exporter
// (pdf_export_controller.go) render from, so "**bold**", "# Heading",
// "1. clause" etc. become real formatting instead of literal characters —
// and both file formats end up looking like the same document because they
// share this one parse.
//
// The parser only recognizes formatting syntax; it never adds, removes or
// reorders words. Every non-blank character that isn't itself a markdown
// marker (*, #, list marker, --- divider) survives into a DocRun's Text
// untouched.

// RunStyle is the inline emphasis on a run of text.
type RunStyle struct {
	Bold   bool
	Italic bool
}

// DocRun is one span of text with a single consistent style.
type DocRun struct {
	Text  string
	Style RunStyle
}

// BlockKind is how a block of the document should be laid out.
type BlockKind int

const (
	BlockParagraph BlockKind = iota
	BlockHeading1            // the document title — bold, centered, largest
	BlockHeading2            // a section heading — bold, left-aligned
	BlockHeading3            // a minor heading — bold, left-aligned, smaller
	BlockNumbered            // "1. ..." / "1) ..." — numbered clause
	BlockBullet              // "- ..." / "* ..." — bullet item
	BlockDivider             // "---" — rendered as a thin rule, not literal dashes
)

// DocBlock is one paragraph-equivalent unit. Lines holds one []DocRun per
// visual line inside the block — almost always just one, except a plain
// paragraph made of several manually-wrapped lines (e.g. an address block),
// which are kept as soft line breaks within a single block instead of
// separate paragraphs, so they don't pick up a full paragraph's spacing
// between them.
type DocBlock struct {
	Kind  BlockKind
	Lines [][]DocRun
	// Marker is the original list marker text ("1.", "2)") for a Numbered
	// block, kept verbatim rather than renumbered, since the AI's own
	// numbering must not be second-guessed or changed.
	Marker string
}

var (
	headingRE  = regexp.MustCompile(`^(#{1,6})\s+(.*)$`)
	numberedRE = regexp.MustCompile(`^(\d+[.)])\s+(.*)$`)
	bulletRE   = regexp.MustCompile(`^[-*•]\s+(.*)$`)
	dividerRE  = regexp.MustCompile(`^(-{3,}|_{3,}|\*{3,})$`)
)

// ParseMarkdownDocument splits content into blocks in document order.
func ParseMarkdownDocument(content string) []DocBlock {
	normalized := strings.ReplaceAll(content, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	rawLines := strings.Split(normalized, "\n")

	var blocks []DocBlock
	var paragraphLines [][]DocRun
	titleAssigned := false

	flushParagraph := func() {
		if len(paragraphLines) > 0 {
			blocks = append(blocks, DocBlock{Kind: BlockParagraph, Lines: paragraphLines})
			paragraphLines = nil
		}
	}

	for _, raw := range rawLines {
		trimmed := strings.TrimSpace(raw)

		if trimmed == "" {
			flushParagraph()
			continue
		}

		if dividerRE.MatchString(trimmed) {
			flushParagraph()
			blocks = append(blocks, DocBlock{Kind: BlockDivider})
			continue
		}

		if m := headingRE.FindStringSubmatch(trimmed); m != nil {
			flushParagraph()
			level := len(m[1])
			kind := BlockHeading2
			switch {
			case level == 1:
				kind = BlockHeading1
			case level >= 3:
				kind = BlockHeading3
			}
			blocks = append(blocks, DocBlock{Kind: kind, Lines: [][]DocRun{parseInlineRuns(m[2])}})
			titleAssigned = true
			continue
		}

		if m := numberedRE.FindStringSubmatch(trimmed); m != nil {
			flushParagraph()
			blocks = append(blocks, DocBlock{
				Kind:   BlockNumbered,
				Lines:  [][]DocRun{parseInlineRuns(m[2])},
				Marker: m[1],
			})
			continue
		}

		if m := bulletRE.FindStringSubmatch(trimmed); m != nil {
			flushParagraph()
			blocks = append(blocks, DocBlock{Kind: BlockBullet, Lines: [][]DocRun{parseInlineRuns(m[1])}})
			continue
		}

		runs := parseInlineRuns(trimmed)

		// A line that is entirely one bold run (and nothing else) reads as a
		// heading rather than a normal sentence — the AI's own convention
		// for "**SOFTWARE AGREEMENT**" as a title, or "**Termination**" as a
		// section header elsewhere in the body. The very first one found
		// becomes the document title (centered, largest); later ones are
		// treated as section headings.
		if len(runs) == 1 && runs[0].Style.Bold && !runs[0].Style.Italic &&
			strings.TrimSpace(runs[0].Text) != "" {
			flushParagraph()
			kind := BlockHeading2
			if !titleAssigned {
				kind = BlockHeading1
				titleAssigned = true
			}
			blocks = append(blocks, DocBlock{Kind: kind, Lines: [][]DocRun{runs}})
			continue
		}

		paragraphLines = append(paragraphLines, runs)
	}
	flushParagraph()
	return blocks
}

// parseInlineRuns splits one line into runs, interpreting **bold**/__bold__
// and *italic*/_italic_ as emphasis rather than literal asterisks/
// underscores. An unmatched/unterminated marker is emitted as literal text
// instead of being dropped, since losing a character is worse than an
// occasional stray symbol.
func parseInlineRuns(line string) []DocRun {
	var runs []DocRun
	i := 0
	n := len(line)

	for i < n {
		if rest := line[i:]; strings.HasPrefix(rest, "**") || strings.HasPrefix(rest, "__") {
			marker := rest[:2]
			if end := strings.Index(rest[2:], marker); end >= 0 && end > 0 {
				runs = append(runs, DocRun{Text: rest[2 : 2+end], Style: RunStyle{Bold: true}})
				i += 2 + end + 2
				continue
			}
		}
		if rest := line[i:]; strings.HasPrefix(rest, "*") || strings.HasPrefix(rest, "_") {
			marker := rest[:1]
			if end := strings.Index(rest[1:], marker); end >= 0 && end > 0 {
				runs = append(runs, DocRun{Text: rest[1 : 1+end], Style: RunStyle{Italic: true}})
				i += 1 + end + 1
				continue
			}
		}

		next := nextMarkerIndex(line[i:])
		if next < 0 {
			runs = append(runs, DocRun{Text: line[i:]})
			break
		}
		if next == 0 {
			// Marker at position 0 didn't resolve above (no closing marker
			// found) — emit it as a literal character and move on so this
			// never loops forever or eats real content.
			runs = append(runs, DocRun{Text: line[i : i+1]})
			i++
			continue
		}
		runs = append(runs, DocRun{Text: line[i : i+next]})
		i += next
	}

	return mergeAdjacentRuns(runs)
}

func nextMarkerIndex(s string) int {
	best := -1
	for _, marker := range []string{"**", "__", "*", "_"} {
		if idx := strings.Index(s, marker); idx >= 0 && (best == -1 || idx < best) {
			best = idx
		}
	}
	return best
}

func mergeAdjacentRuns(runs []DocRun) []DocRun {
	if len(runs) < 2 {
		return runs
	}
	merged := runs[:1]
	for _, r := range runs[1:] {
		last := &merged[len(merged)-1]
		if last.Style == r.Style {
			last.Text += r.Text
			continue
		}
		merged = append(merged, r)
	}
	return merged
}
