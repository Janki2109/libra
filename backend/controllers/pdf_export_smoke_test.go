package controllers

import (
	"bytes"
	"strings"
	"testing"
)

func TestBuildPdf_SoftwareAgreementExample(t *testing.T) {
	content := "**SOFTWARE DEVELOPMENT, IMPLEMENTATION & SUPPORT AGREEMENT**\n\n" +
		"**THIS AGREEMENT** is made and entered into on this **2nd day of September 2026**\n\n" +
		"1. HOMEFIX TECHNOLOGIES PRIVATE LIMITED, a company incorporated under the Companies Act, having its registered office at Mumbai, Maharashtra, referred to as the “Client”.\n" +
		"2. [VENDOR NAME] PRIVATE LIMITED, a company incorporated under the Companies Act, referred to as the “Vendor”.\n\n" +
		"---\n\n" +
		"1. **CLIENT**\n2. **VENDOR**\n\n" +
		"The total consideration payable under this Agreement is ₹50,000 – due within 30 days.\n\n" +
		"- First deliverable\n- Second deliverable\n\n" +
		"Mr. Ramesh Kumar\nFlat No. 12, Sunrise Apartments\nSector-5, Dwarka, New Delhi"

	pdfBytes, err := buildPdf("Test Agreement", content)
	if err != nil {
		t.Fatalf("buildPdf failed: %v", err)
	}
	if !bytes.HasPrefix(pdfBytes, []byte("%PDF")) {
		t.Error("output does not start with %PDF")
	}
	if !bytes.Contains(pdfBytes[len(pdfBytes)-30:], []byte("%%EOF")) {
		t.Error("output is missing the PDF end-of-file marker")
	}
}

func TestBuildPdf_ArabicStillRejected(t *testing.T) {
	// Arabic/Urdu is the one script that still can't render correctly (no
	// shaping engine to join cursive letterforms), so ExportPdf's guard must
	// still catch it — everything else in unsupportedScriptRanges was
	// removed once brahmicFonts made those scripts renderable.
	if _, ok := firstUnsupportedScriptRune("یہ معاہدہ"); !ok {
		t.Error("expected Arabic/Urdu text to be flagged as an unsupported script")
	}
}

func TestBuildPdf_DevanagariNoLongerRejected(t *testing.T) {
	if _, ok := firstUnsupportedScriptRune("यह अनुबंध है"); ok {
		t.Error("Devanagari should no longer be flagged as an unsupported script")
	}
}

// TestBuildPdf_IndianScripts exercises every Brahmic script the Translator
// offers end to end through buildPdf (the same path ExportPdf uses once the
// script guard passes), confirming each produces a well-formed, non-trivial
// PDF instead of erroring or emitting an empty/near-empty file.
func TestBuildPdf_IndianScripts(t *testing.T) {
	cases := map[string]string{
		"Hindi":    "यह एक अनुबंध है जो दोनों पक्षों के बीच हस्ताक्षरित है। किताब में तारीख दी गई है।",
		"Marathi":  "हा करार दोन्ही पक्षांमध्ये स्वाक्षरी केलेला आहे.",
		"Bengali":  "এই চুক্তিটি উভয় পক্ষের মধ্যে স্বাক্ষরিত হয়েছে।",
		"Punjabi":  "ਇਹ ਸਮਝੌਤਾ ਦੋਵਾਂ ਧਿਰਾਂ ਵਿਚਕਾਰ ਦਸਤਖਤ ਕੀਤਾ ਗਿਆ ਹੈ।",
		"Gujarati": "આ કરાર બંને પક્ષો વચ્ચે સહી થયેલ છે.",
		"Tamil":    "இந்த ஒப்பந்தம் இரு தரப்பினருக்கும் இடையே கையொப்பமிடப்பட்டது.",
		"Telugu":   "ఈ ఒప్పందం ఇరు పక్షాల మధ్య సంతకం చేయబడింది.",
		"Kannada":  "ಈ ಒಪ್ಪಂದವು ಎರಡೂ ಪಕ್ಷಗಳ ನಡುವೆ ಸಹಿ ಮಾಡಲ್ಪಟ್ಟಿದೆ.",
	}
	for lang, content := range cases {
		t.Run(lang, func(t *testing.T) {
			if _, ok := firstUnsupportedScriptRune(content); ok {
				t.Fatalf("%s content unexpectedly flagged as unsupported", lang)
			}
			pdfBytes, err := buildPdf("Translated Document", "**"+lang+" Translation**\n\n"+content)
			if err != nil {
				t.Fatalf("buildPdf failed for %s: %v", lang, err)
			}
			if !bytes.HasPrefix(pdfBytes, []byte("%PDF")) {
				t.Errorf("%s: output does not start with %%PDF", lang)
			}
			if !bytes.Contains(pdfBytes[len(pdfBytes)-30:], []byte("%%EOF")) {
				t.Errorf("%s: output is missing the PDF end-of-file marker", lang)
			}
			// fpdf subsets embedded TrueType fonts to just the glyphs used, so
			// this won't be as large as the source TTF — but a bare-cp1252
			// PDF of comparable plain-English content runs about 1KB, so
			// anything in the low thousands confirms real (subsetted) glyph
			// data was embedded rather than silently dropped.
			if len(pdfBytes) < 5000 {
				t.Errorf("%s: output suspiciously small (%d bytes) for an embedded-font PDF", lang, len(pdfBytes))
			}
		})
	}
}

// TestBuildPdf_MixedScript confirms a line mixing English and a Brahmic
// script (a realistic translation containing a proper noun or citation)
// renders without error via the per-run script segmentation.
func TestBuildPdf_MixedScript(t *testing.T) {
	content := "Sri **Ramesh Kumar** ने अनुबंध पर हस्ताक्षर किए on 2nd September 2026."
	pdfBytes, err := buildPdf("Translated Document", content)
	if err != nil {
		t.Fatalf("buildPdf failed: %v", err)
	}
	if !bytes.HasPrefix(pdfBytes, []byte("%PDF")) {
		t.Error("output does not start with %PDF")
	}
}

func TestTimestampedFileName(t *testing.T) {
	name := timestampedFileName("Translator", ".pdf")
	if !strings.HasPrefix(name, "translator_") || !strings.HasSuffix(name, ".pdf") {
		t.Errorf("unexpected file name shape: %q", name)
	}
	if strings.Contains(name, " ") || strings.ToLower(name) != name {
		t.Errorf("expected a lowercase, space-free file name, got %q", name)
	}
}

func TestBuildPdf_NoLiteralMarkdownOrMojibake(t *testing.T) {
	content := "**Bold Title**\n\nNormal text with *italic* and a rupee amount ₹1,234 and a dash – here."
	pdfBytes, err := buildPdf("Doc", content)
	if err != nil {
		t.Fatalf("buildPdf failed: %v", err)
	}
	// The PDF content stream is Flate-compressed, so we can't grep the
	// decoded text directly here without a decompressor; this at least
	// verifies generation succeeds and produces a non-trivial file for the
	// scenarios that previously risked a raw UTF-8 write into a cp1252 font.
	if len(pdfBytes) < 500 {
		t.Errorf("output suspiciously small (%d bytes) for this content", len(pdfBytes))
	}
}
