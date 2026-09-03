package controllers

import (
	"bytes"
	"encoding/base64"
	"net/http"
	"regexp"
	"strings"
	"time"

	"libra/services"
	"libra/utils"

	"github.com/gin-gonic/gin"
	"github.com/go-pdf/fpdf"
)

// ExportPdf turns a generated draft/tool result into a real, readable PDF —
// the same {title, content} contract as ExportDocx, so every Smart Draft
// result screen that already offers "Export as Word" can offer "Save as
// PDF" next to it without a different request shape. fpdf handles text
// wrapping and automatic page breaks, so this works for both a short
// translation and a multi-page drafted document.
func ExportPdf(c *gin.Context) {
	var req struct {
		Title   string `json:"title"`
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Title == "" {
		req.Title = "Document"
	}

	// Arabic/Urdu is cursive script: every letter changes shape depending on
	// its neighbors, and rendering it without a shaping engine (which fpdf
	// doesn't have) would draw only isolated letterforms — not just
	// imperfect, but genuinely unreadable as Arabic/Urdu. Word/LibreOffice do
	// their own shaping on open, so that script alone is still pointed
	// there. The Brahmic scripts (Devanagari, Bengali, Gurmukhi, Gujarati,
	// Tamil, Telugu, Kannada) are rendered below with embedded Unicode fonts.
	if r, ok := firstUnsupportedScriptRune(req.Title + req.Content); ok {
		utils.Error(c, http.StatusUnprocessableEntity,
			"PDF export doesn't support "+scriptNameFor(r)+" text yet — please use Save as Word instead.",
			"unsupported script for PDF rendering")
		return
	}

	pdfBytes, err := buildPdf(req.Title, req.Content)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to build document", err.Error())
		return
	}
	if len(pdfBytes) == 0 {
		utils.Error(c, http.StatusInternalServerError, "Failed to build document", "empty PDF output")
		return
	}

	fileName := timestampedFileName(req.Title, ".pdf")
	utils.Success(c, http.StatusOK, "Document exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(pdfBytes),
		"file_name":   fileName,
	})
}

var fileNameWordRe = regexp.MustCompile(`[A-Za-z0-9]+`)

// timestampedFileName builds a lowercase, underscore-separated file name
// with today's date so repeated exports of the same tool never collide and
// a user can tell at a glance when a download was produced, e.g. the
// Translator's title "Translated Document" becomes
// "translated_document_03-09-2026.pdf".
func timestampedFileName(title, ext string) string {
	words := fileNameWordRe.FindAllString(sanitizeFileName(title), -1)
	base := strings.ToLower(strings.Join(words, "_"))
	if base == "" {
		base = "document"
	}
	return base + "_" + time.Now().Format("02-01-2006") + ext
}

// pdfFont is fpdf's built-in "Times" family (Times-Roman/Bold/Italic/
// BoldItalic) — the same visual choice as buildDocx's "Times New Roman", so
// Word and PDF output look like the same document, used for any run that's
// representable in cp1252 (English, numbers, punctuation). title isn't
// rendered into the body: it's only ever the tool/template name used for
// the filename, and injecting it as an extra heading here (the previous
// behavior) made the PDF show a heading Word's export never had.
const pdfFont = "Times"

const (
	pdfBodySize   = 11.0
	pdfLineHeight = 6.0
)

// scriptFont names an embedded Unicode font family registered on the
// document (see registerScriptFonts) plus the Unicode range it covers.
type scriptFont struct {
	lo, hi  rune
	family  string
	ttfName string
}

// brahmicFonts covers every non-Latin language in the Translator's dropdown
// except Urdu (Arabic script — rejected earlier, see firstUnsupportedScriptRune).
// fpdf has no OpenType shaping engine, so complex conjuncts/reordering
// (e.g. a Devanagari "ि" matra that visually precedes its consonant) may not
// always land in the exact visual position a shaping-aware renderer would
// produce — but the correct characters render in a real script-appropriate
// font instead of the previous behavior, which refused to generate the PDF
// at all.
var brahmicFonts = []scriptFont{
	{0x0900, 0x097F, "NotoDevanagari", "Devanagari"}, // Hindi, Marathi
	{0x0980, 0x09FF, "NotoBengali", "Bengali"},
	{0x0A00, 0x0A7F, "NotoGurmukhi", "Gurmukhi"}, // Punjabi
	{0x0A80, 0x0AFF, "NotoGujarati", "Gujarati"},
	{0x0B80, 0x0BFF, "NotoTamil", "Tamil"},
	{0x0C00, 0x0C7F, "NotoTelugu", "Telugu"},
	{0x0C80, 0x0CFF, "NotoKannada", "Kannada"},
}

func fontBytesFor(ttfName string) []byte {
	switch ttfName {
	case "Devanagari":
		return services.NotoSansDevanagariTTF
	case "Bengali":
		return services.NotoSansBengaliTTF
	case "Gurmukhi":
		return services.NotoSansGurmukhiTTF
	case "Gujarati":
		return services.NotoSansGujaratiTTF
	case "Tamil":
		return services.NotoSansTamilTTF
	case "Telugu":
		return services.NotoSansTeluguTTF
	case "Kannada":
		return services.NotoSansKannadaTTF
	}
	return nil
}

// familyForRune returns the registered Unicode font family for r, or ""
// when r belongs to the default cp1252-safe (Times) run.
func familyForRune(r rune) string {
	for _, sf := range brahmicFonts {
		if r >= sf.lo && r <= sf.hi {
			return sf.family
		}
	}
	return ""
}

// registerScriptFonts scans the document once and embeds only the Unicode
// fonts actually needed, so a plain-English draft's PDF isn't bloated with
// megabytes of unused font data. The same TTF is registered for both the
// regular and bold style slots — these embedded fonts ship as a single
// weight, so a "bold" Devanagari/Tamil/etc. run renders in that weight
// rather than fpdf erroring for an unregistered style.
func registerScriptFonts(pdf *fpdf.Fpdf, text string) {
	needed := map[string]bool{}
	for _, r := range text {
		if fam := familyForRune(r); fam != "" {
			needed[fam] = true
		}
	}
	for _, sf := range brahmicFonts {
		if !needed[sf.family] {
			continue
		}
		b := fontBytesFor(sf.ttfName)
		pdf.AddUTF8FontFromBytes(sf.family, "", b)
		pdf.AddUTF8FontFromBytes(sf.family, "B", b)
	}
}

// pdfDoc bundles the fpdf instance with its cp1252 translator so every
// render helper applies the same encoding fix without threading an extra
// parameter through each call.
type pdfDoc struct {
	pdf *fpdf.Fpdf
	tr  func(string) string
}

// text prepares a run of content for the core (non-embedded) PDF font, which
// only understands single-byte cp1252 — passing raw UTF-8 bytes straight
// through (the previous behavior) renders every accented letter, curly
// quote, en/em dash and rupee sign as mojibake instead of the actual
// character. The rupee sign has no cp1252 slot at all, so it's spelled out
// rather than silently dropped. Only called for the Times/cp1252 segments;
// embedded Unicode-font segments are written as raw UTF-8 (see writeRuns).
func (d *pdfDoc) text(s string) string {
	s = strings.ReplaceAll(s, "₹", "Rs. ")
	return d.tr(s)
}

// buildPdf renders services.ParseMarkdownDocument's blocks the same way
// buildDocx does — headings, inline bold/italic, numbered/bulleted clauses
// with a hanging indent, and a drawn rule in place of a literal "---" — so
// the two export formats match instead of one showing raw Markdown.
func buildPdf(title, content string) ([]byte, error) {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(25, 20, 25)
	pdf.SetAutoPageBreak(true, 20)

	registerScriptFonts(pdf, title+content)
	pdf.AddPage()

	d := &pdfDoc{pdf: pdf, tr: pdf.UnicodeTranslatorFromDescriptor("cp1252")}

	for _, b := range services.ParseMarkdownDocument(content) {
		d.renderBlock(b)
	}

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// runSegment is a contiguous slice of a run's text that shares one font
// family — either "" (default Times/cp1252) or an embedded Unicode family.
type runSegment struct {
	text   string
	family string
}

// splitByScript breaks s into the fewest segments needed so each one can be
// written with a single SetFont call — the boundary between an English
// phrase and an embedded Devanagari/Tamil/etc. word, for instance.
func splitByScript(s string) []runSegment {
	var segs []runSegment
	var cur strings.Builder
	curFam := ""
	first := true
	flush := func() {
		if cur.Len() > 0 {
			segs = append(segs, runSegment{text: cur.String(), family: curFam})
			cur.Reset()
		}
	}
	for _, r := range s {
		fam := familyForRune(r)
		if first {
			curFam = fam
			first = false
		} else if fam != curFam {
			flush()
			curFam = fam
		}
		cur.WriteRune(r)
	}
	flush()
	return segs
}

func (d *pdfDoc) setRunFont(family string, style services.RunStyle, size float64) {
	fontStyle := ""
	if style.Bold {
		fontStyle += "B"
	}
	if style.Italic && family == "" {
		// The embedded Noto fonts ship one weight/style; italics only apply
		// to the Times core font, which has a real italic face.
		fontStyle += "I"
	}
	if family == "" {
		d.pdf.SetFont(pdfFont, fontStyle, size)
	} else {
		d.pdf.SetFont(family, fontStyle, size)
	}
}

// writeRun writes one styled run, script-segmented so a translated phrase
// that mixes, say, English and Hindi in the same sentence still renders
// every character in a font that actually has it.
func (d *pdfDoc) writeRun(text string, style services.RunStyle, size float64) {
	for _, seg := range splitByScript(text) {
		if seg.text == "" {
			continue
		}
		d.setRunFont(seg.family, style, size)
		if seg.family == "" {
			d.pdf.Write(pdfLineHeight, d.text(seg.text))
		} else {
			d.pdf.Write(pdfLineHeight, seg.text)
		}
	}
}

// allCp1252 reports whether every rune in the given lines renders through
// the default Times/cp1252 font — used to decide whether a heading can keep
// its centered MultiCell layout (which needs one consistent font) or must
// fall back to a left-flowing, script-segmented render.
func allCp1252(lines [][]services.DocRun) bool {
	for _, line := range lines {
		for _, run := range line {
			for _, r := range run.Text {
				if familyForRune(r) != "" {
					return false
				}
			}
		}
	}
	return true
}

func plainRunsText(lines [][]services.DocRun) string {
	var b strings.Builder
	for i, line := range lines {
		if i > 0 {
			b.WriteString(" ")
		}
		for _, r := range line {
			b.WriteString(r.Text)
		}
	}
	return b.String()
}

// writeLines flows each run left-to-right with fpdf's Write, which wraps
// automatically at the page margin — unlike MultiCell, it lets the font
// style (and, via writeRun, the font family) change mid-paragraph, which is
// what makes inline bold/italic and mixed-script text possible. Lines within
// one block are joined with a line break rather than a new paragraph,
// matching buildDocx's <w:br/> treatment of soft-wrapped content like an
// address block.
func (d *pdfDoc) writeLines(lines [][]services.DocRun, size float64) {
	for i, line := range lines {
		if i > 0 {
			d.pdf.Ln(pdfLineHeight)
		}
		for _, run := range line {
			if run.Text == "" {
				continue
			}
			d.writeRun(run.Text, run.Style, size)
		}
	}
}

func (d *pdfDoc) writeParagraph(lines [][]services.DocRun) {
	d.writeLines(lines, pdfBodySize)
	d.pdf.Ln(pdfLineHeight)
	d.pdf.Ln(2)
}

// writeListItem prints the marker in a fixed-width cell, then temporarily
// narrows the page's left margin so a wrapped continuation line lands under
// the text instead of back under the marker — a hanging indent, the same
// shape as buildDocx's <w:ind w:hanging="720"/>.
func (d *pdfDoc) writeListItem(marker string, lines [][]services.DocRun) {
	const indent = 10.0
	left, _, _, _ := d.pdf.GetMargins()

	d.setRunFont("", services.RunStyle{}, pdfBodySize)
	d.pdf.CellFormat(indent, pdfLineHeight, marker, "", 0, "L", false, 0, "")

	d.pdf.SetLeftMargin(left + indent)
	d.writeLines(lines, pdfBodySize)
	d.pdf.Ln(pdfLineHeight)
	d.pdf.SetLeftMargin(left)
	d.pdf.Ln(1.5)
}

func (d *pdfDoc) renderDivider() {
	d.pdf.Ln(3)
	left, _, right, _ := d.pdf.GetMargins()
	pageW, _ := d.pdf.GetPageSize()
	y := d.pdf.GetY()
	d.pdf.SetDrawColor(153, 153, 153)
	d.pdf.SetLineWidth(0.2)
	d.pdf.Line(left, y, pageW-right, y)
	d.pdf.SetDrawColor(0, 0, 0)
	d.pdf.Ln(4)
}

// writeHeading renders a heading line. MultiCell needs one font for the
// whole cell, so a pure-Latin heading keeps the original centered/aligned
// layout; a heading that mixes in an embedded script falls back to a
// left-flowing, script-segmented render (still bold, at the same size) so
// it renders correctly rather than dropping non-Latin characters.
func (d *pdfDoc) writeHeading(lines [][]services.DocRun, cellH, size float64, align string) {
	if allCp1252(lines) {
		d.pdf.SetFont(pdfFont, "B", size)
		d.pdf.MultiCell(0, cellH, d.text(plainRunsText(lines)), "", align, false)
		return
	}
	for _, line := range lines {
		for _, run := range line {
			if run.Text == "" {
				continue
			}
			d.writeRun(run.Text, services.RunStyle{Bold: true}, size)
		}
	}
	d.pdf.Ln(cellH)
}

func (d *pdfDoc) renderBlock(b services.DocBlock) {
	switch b.Kind {
	case services.BlockHeading1:
		d.pdf.Ln(2)
		d.writeHeading(b.Lines, 8, 16, "C")
		d.pdf.Ln(4)
	case services.BlockHeading2:
		d.pdf.Ln(3)
		d.writeHeading(b.Lines, 7, 13, "L")
		d.pdf.Ln(2)
	case services.BlockHeading3:
		d.pdf.Ln(2)
		d.writeHeading(b.Lines, 6.5, 12, "L")
		d.pdf.Ln(1)
	case services.BlockNumbered:
		d.writeListItem(b.Marker+" ", b.Lines)
	case services.BlockBullet:
		d.writeListItem("\x95 ", b.Lines) // \x95 is bullet (•) in cp1252
	case services.BlockDivider:
		d.renderDivider()
	default:
		d.writeParagraph(b.Lines)
	}
}

// scriptRange is an inclusive Unicode block boundary paired with a
// human-readable name for the error message.
type scriptRange struct {
	lo, hi rune
	name   string
}

// Scripts that still can't be rendered correctly. Every other non-English
// language in the Translator dropdown (Devanagari, Bengali, Gurmukhi,
// Gujarati, Tamil, Telugu, Kannada) now has an embedded Unicode font — see
// brahmicFonts. Arabic/Urdu is the one exception: it's a cursive script
// that needs real shaping to join letters correctly, which fpdf can't do.
var unsupportedScriptRanges = []scriptRange{
	{0x0600, 0x06FF, "Arabic/Urdu"},
}

func firstUnsupportedScriptRune(s string) (rune, bool) {
	for _, r := range s {
		for _, sr := range unsupportedScriptRanges {
			if r >= sr.lo && r <= sr.hi {
				return r, true
			}
		}
	}
	return 0, false
}

func scriptNameFor(r rune) string {
	for _, sr := range unsupportedScriptRanges {
		if r >= sr.lo && r <= sr.hi {
			return sr.name
		}
	}
	return "unsupported script"
}
