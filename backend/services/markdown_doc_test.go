package services

import "testing"

func plainText(runs []DocRun) string {
	var s string
	for _, r := range runs {
		s += r.Text
	}
	return s
}

func TestParseMarkdownDocument_TitleAndBoldInline(t *testing.T) {
	content := "**SOFTWARE DEVELOPMENT, IMPLEMENTATION & SUPPORT AGREEMENT**\n\n" +
		"**THIS AGREEMENT** is made and entered into on this **2nd day of September 2026**"

	blocks := ParseMarkdownDocument(content)
	if len(blocks) != 2 {
		t.Fatalf("expected 2 blocks, got %d: %+v", len(blocks), blocks)
	}
	if blocks[0].Kind != BlockHeading1 {
		t.Errorf("expected first block to be Heading1 (title), got %v", blocks[0].Kind)
	}
	if got := plainText(blocks[0].Lines[0]); got != "SOFTWARE DEVELOPMENT, IMPLEMENTATION & SUPPORT AGREEMENT" {
		t.Errorf("title text mismatch, got %q", got)
	}

	if blocks[1].Kind != BlockParagraph {
		t.Errorf("expected second block to be a paragraph, got %v", blocks[1].Kind)
	}
	runs := blocks[1].Lines[0]
	full := plainText(runs)
	want := "THIS AGREEMENT is made and entered into on this 2nd day of September 2026"
	if full != want {
		t.Errorf("content changed by formatting parse:\n got: %q\nwant: %q", full, want)
	}
	if !runs[0].Style.Bold {
		t.Errorf("expected 'THIS AGREEMENT' run to be bold, got %+v", runs[0])
	}
}

func TestParseMarkdownDocument_NumberedClauses(t *testing.T) {
	content := "1. HOMEFIX TECHNOLOGIES PRIVATE LIMITED, a company incorporated under...\n" +
		"2. [VENDOR NAME] PRIVATE LIMITED, a company incorporated under..."

	blocks := ParseMarkdownDocument(content)
	if len(blocks) != 2 {
		t.Fatalf("expected 2 numbered blocks, got %d: %+v", len(blocks), blocks)
	}
	for i, want := range []string{"1.", "2."} {
		if blocks[i].Kind != BlockNumbered {
			t.Errorf("block %d: expected Numbered, got %v", i, blocks[i].Kind)
		}
		if blocks[i].Marker != want {
			t.Errorf("block %d: expected marker %q, got %q", i, want, blocks[i].Marker)
		}
	}
	if got := plainText(blocks[0].Lines[0]); got != "HOMEFIX TECHNOLOGIES PRIVATE LIMITED, a company incorporated under..." {
		t.Errorf("clause 1 text mismatch: %q", got)
	}
}

func TestParseMarkdownDocument_NumberedClauseWithBoldLabel(t *testing.T) {
	content := "1. **CLIENT**\n2. **VENDOR**"
	blocks := ParseMarkdownDocument(content)
	if len(blocks) != 2 {
		t.Fatalf("expected 2 blocks, got %d", len(blocks))
	}
	if blocks[0].Kind != BlockNumbered || blocks[0].Marker != "1." {
		t.Fatalf("expected numbered '1.' block, got %+v", blocks[0])
	}
	if plainText(blocks[0].Lines[0]) != "CLIENT" || !blocks[0].Lines[0][0].Style.Bold {
		t.Errorf("expected bold 'CLIENT', got %+v", blocks[0].Lines[0])
	}
}

func TestParseMarkdownDocument_DividerAndBullets(t *testing.T) {
	content := "Some text\n\n---\n\n- First point\n- Second point\n* Third point"
	blocks := ParseMarkdownDocument(content)

	var kinds []BlockKind
	for _, b := range blocks {
		kinds = append(kinds, b.Kind)
	}
	want := []BlockKind{BlockParagraph, BlockDivider, BlockBullet, BlockBullet, BlockBullet}
	if len(kinds) != len(want) {
		t.Fatalf("expected kinds %v, got %v (blocks: %+v)", want, kinds, blocks)
	}
	for i := range want {
		if kinds[i] != want[i] {
			t.Errorf("block %d: expected %v, got %v", i, want[i], kinds[i])
		}
	}
	if plainText(blocks[2].Lines[0]) != "First point" {
		t.Errorf("bullet text mismatch: %q", plainText(blocks[2].Lines[0]))
	}
}

func TestParseMarkdownDocument_MultilineParagraphKeepsSoftBreaks(t *testing.T) {
	content := "Mr. Ramesh Kumar\nFlat No. 12, Sunrise Apartments\nSector-5, Dwarka, New Delhi"
	blocks := ParseMarkdownDocument(content)
	if len(blocks) != 1 {
		t.Fatalf("expected address block to stay one paragraph, got %d blocks: %+v", len(blocks), blocks)
	}
	if blocks[0].Kind != BlockParagraph {
		t.Errorf("expected Paragraph, got %v", blocks[0].Kind)
	}
	if len(blocks[0].Lines) != 3 {
		t.Errorf("expected 3 soft-break lines, got %d", len(blocks[0].Lines))
	}
}

func TestParseMarkdownDocument_HeadingHash(t *testing.T) {
	content := "# SOFTWARE AGREEMENT\n\nBody text here."
	blocks := ParseMarkdownDocument(content)
	if len(blocks) != 2 || blocks[0].Kind != BlockHeading1 {
		t.Fatalf("expected [Heading1, Paragraph], got %+v", blocks)
	}
	if plainText(blocks[0].Lines[0]) != "SOFTWARE AGREEMENT" {
		t.Errorf("heading text mismatch: %q", plainText(blocks[0].Lines[0]))
	}
}

func TestParseMarkdownDocument_ItalicAndUnterminatedMarkerSurvives(t *testing.T) {
	content := "This is *emphasized* text with an unterminated * marker."
	blocks := ParseMarkdownDocument(content)
	got := plainText(blocks[0].Lines[0])
	want := "This is emphasized text with an unterminated * marker."
	if got != want {
		t.Errorf("content lost or altered:\n got: %q\nwant: %q", got, want)
	}
}
