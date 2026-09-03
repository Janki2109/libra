package controllers

import (
	"archive/zip"
	"bytes"
	"io"
	"strings"
	"testing"
)

func readZipPart(t *testing.T, docxBytes []byte, name string) string {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(docxBytes), int64(len(docxBytes)))
	if err != nil {
		t.Fatalf("not a valid zip: %v", err)
	}
	for _, f := range zr.File {
		if f.Name == name {
			rc, err := f.Open()
			if err != nil {
				t.Fatalf("could not open %s: %v", name, err)
			}
			defer rc.Close()
			data, err := io.ReadAll(rc)
			if err != nil {
				t.Fatalf("could not read %s: %v", name, err)
			}
			return string(data)
		}
	}
	t.Fatalf("part %s not found in docx", name)
	return ""
}

func TestBuildDocx_SoftwareAgreementExample(t *testing.T) {
	content := "**SOFTWARE DEVELOPMENT, IMPLEMENTATION & SUPPORT AGREEMENT**\n\n" +
		"**THIS AGREEMENT** is made and entered into on this **2nd day of September 2026**\n\n" +
		"1. HOMEFIX TECHNOLOGIES PRIVATE LIMITED, a company incorporated under the Companies Act, having its registered office at Mumbai, Maharashtra, referred to as the “Client”.\n" +
		"2. [VENDOR NAME] PRIVATE LIMITED, a company incorporated under the Companies Act, referred to as the “Vendor”.\n\n" +
		"---\n\n" +
		"1. **CLIENT**\n2. **VENDOR**\n\n" +
		"The total consideration payable under this Agreement is ₹50,000 – due within 30 days.\n\n" +
		"- First deliverable\n- Second deliverable\n\n" +
		"Mr. Ramesh Kumar\nFlat No. 12, Sunrise Apartments\nSector-5, Dwarka, New Delhi"

	docxBytes, err := buildDocx(content)
	if err != nil {
		t.Fatalf("buildDocx failed: %v", err)
	}
	if len(docxBytes) == 0 {
		t.Fatal("buildDocx produced empty output")
	}

	doc := readZipPart(t, docxBytes, "word/document.xml")

	// No raw markdown syntax should survive into the rendered text runs.
	for _, forbidden := range []string{"**", "---\n", ">**", "**<"} {
		if strings.Contains(doc, forbidden) {
			t.Errorf("document.xml still contains raw markdown-ish sequence %q", forbidden)
		}
	}
	// A literal "**" inside a <w:t> would mean markdown leaked through as text.
	for _, part := range strings.Split(doc, "<w:t") {
		if strings.Contains(part, "**") {
			t.Errorf("found literal ** inside a <w:t> run: %q", part[:min(80, len(part))])
		}
	}

	if !strings.Contains(doc, ">SOFTWARE DEVELOPMENT, IMPLEMENTATION &amp; SUPPORT AGREEMENT<") {
		t.Error("expected the title text to appear verbatim (XML-escaped)")
	}
	if !strings.Contains(doc, `<w:jc w:val="center"/>`) {
		t.Error("expected the title paragraph to be centered")
	}
	if !strings.Contains(doc, "<w:b/>") {
		t.Error("expected at least one bold run")
	}
	if !strings.Contains(doc, `w:val="single"`) {
		t.Error("expected the divider to render as a ruled line, not literal dashes")
	}
	if !strings.Contains(doc, "1.\t") {
		t.Error("expected numbered marker '1.' followed by a tab character")
	}
	if !strings.Contains(doc, "•\t") {
		t.Error("expected bullet marker '•' followed by a tab character")
	}
	if !strings.Contains(doc, `<w:pgSz w:w="11906" w:h="16838"/>`) {
		t.Error("expected an A4 page size in sectPr")
	}

	styles := readZipPart(t, docxBytes, "word/styles.xml")
	if !strings.Contains(styles, docxFont) {
		t.Errorf("expected default font %q in styles.xml", docxFont)
	}

	contentTypes := readZipPart(t, docxBytes, "[Content_Types].xml")
	if !strings.Contains(contentTypes, "styles.xml") {
		t.Error("styles.xml must be registered in [Content_Types].xml")
	}
	rels := readZipPart(t, docxBytes, "word/_rels/document.xml.rels")
	if !strings.Contains(rels, "styles.xml") {
		t.Error("styles.xml relationship must be present in document.xml.rels")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
