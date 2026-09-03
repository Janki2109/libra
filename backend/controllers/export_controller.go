package controllers

import (
	"archive/zip"
	"bytes"
	"encoding/base64"
	"fmt"
	"libra/services"
	"libra/utils"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ExportDocx turns a generated draft/translation into a real, professionally
// formatted .docx file so a lawyer can save/share the AI's output as a Word
// document instead of only copy-pasting plain text. Built with stdlib
// archive/zip only — a .docx is just a zip of a handful of fixed XML parts —
// with services.ParseMarkdownDocument turning the AI's Markdown-ish output
// into headings/bold/italic/lists instead of exporting "**"/"#"/"---" as
// literal characters. document_text_service.go's extractDOCXText (used by
// the "Upload Document" -> AI Tools round trip) only reads whatever text is
// inside <w:t> elements, so the extra <w:pPr>/<w:rPr>/<w:br/> formatting
// added here doesn't change what that reads back out.
func ExportDocx(c *gin.Context) {
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

	docxBytes, err := buildDocx(req.Content)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to build document", err.Error())
		return
	}

	fileName := sanitizeFileName(req.Title) + ".docx"
	utils.Success(c, http.StatusOK, "Document exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(docxBytes),
		"file_name":   fileName,
	})
}

var unsafeFileNameChars = regexp.MustCompile(`[^A-Za-z0-9 _-]+`)

func sanitizeFileName(name string) string {
	cleaned := unsafeFileNameChars.ReplaceAllString(name, "")
	cleaned = strings.TrimSpace(cleaned)
	if cleaned == "" {
		return "Document"
	}
	return cleaned
}

func xmlEscape(s string) string {
	replacer := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		`"`, "&quot;",
		"'", "&apos;",
	)
	return replacer.Replace(s)
}

const contentTypesXML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>`

const rootRelsXML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`

const documentRelsXML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`

// docxFont is the one consistent primary font used throughout the exported
// document — a serif face is the conventional choice for a legal document.
const docxFont = "Times New Roman"

// stylesXML sets the document-wide default font/size/spacing so a paragraph
// or run that doesn't need any special formatting still renders consistently
// (this is also what the previous version of this file was missing
// entirely, which is why Word fell back to its own spacious built-in
// default and produced the huge gaps between every line).
const stylesXML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults>
<w:rPrDefault><w:rPr><w:rFonts w:ascii="` + docxFont + `" w:hAnsi="` + docxFont + `" w:cs="` + docxFont + `"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="200" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
</w:styles>`

// A4 in twentieths of a point (twips): 210mm x 297mm. Margins are 1 inch
// (1440 twips) on every side.
const docxSectPr = `<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>`

// buildDocx renders services.ParseMarkdownDocument's blocks as real Word
// formatting — headings, bold/italic runs, numbered/bulleted paragraphs with
// a hanging indent, and a thin ruled line in place of a literal "---".
func buildDocx(content string) ([]byte, error) {
	blocks := services.ParseMarkdownDocument(content)

	var body strings.Builder
	for _, b := range blocks {
		body.WriteString(renderDocxBlock(b))
	}
	body.WriteString(docxSectPr)

	documentXML := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>` + body.String() + `</w:body>
</w:document>`

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	files := map[string]string{
		"[Content_Types].xml":          contentTypesXML,
		"_rels/.rels":                  rootRelsXML,
		"word/document.xml":            documentXML,
		"word/_rels/document.xml.rels": documentRelsXML,
		"word/styles.xml":              stylesXML,
	}
	for name, data := range files {
		w, err := zw.Create(name)
		if err != nil {
			return nil, fmt.Errorf("could not add %s: %w", name, err)
		}
		if _, err := w.Write([]byte(data)); err != nil {
			return nil, fmt.Errorf("could not write %s: %w", name, err)
		}
	}
	if err := zw.Close(); err != nil {
		return nil, fmt.Errorf("could not finalize docx: %w", err)
	}
	return buf.Bytes(), nil
}

// docxRunProps writes the <w:rPr> for one run at the given size (in
// half-points, i.e. 22 = 11pt).
func docxRunProps(style services.RunStyle, halfPoints int) string {
	var b strings.Builder
	sz := strconv.Itoa(halfPoints)
	b.WriteString(`<w:rPr><w:rFonts w:ascii="` + docxFont + `" w:hAnsi="` + docxFont + `" w:cs="` + docxFont + `"/>`)
	if style.Bold {
		b.WriteString(`<w:b/><w:bCs/>`)
	}
	if style.Italic {
		b.WriteString(`<w:i/><w:iCs/>`)
	}
	b.WriteString(`<w:sz w:val="` + sz + `"/><w:szCs w:val="` + sz + `"/></w:rPr>`)
	return b.String()
}

func docxRun(text string, style services.RunStyle, halfPoints int) string {
	if text == "" {
		return ""
	}
	return `<w:r>` + docxRunProps(style, halfPoints) + `<w:t xml:space="preserve">` +
		xmlEscape(text) + `</w:t></w:r>`
}

// docxParagraphLines renders a block's lines as runs, joining lines within
// the same block with a soft <w:br/> line break rather than starting a new
// paragraph — so a multi-line address block, for example, doesn't pick up a
// full paragraph's worth of spacing between each of its lines.
func docxParagraphLines(lines [][]services.DocRun, halfPoints int) string {
	var b strings.Builder
	for i, line := range lines {
		if i > 0 {
			b.WriteString(`<w:r><w:br/></w:r>`)
		}
		for _, run := range line {
			b.WriteString(docxRun(run.Text, run.Style, halfPoints))
		}
	}
	return b.String()
}

// docxListMarkerRun renders a numbered/bullet marker followed by a literal
// tab character inside the same <w:t> — combined with the tab stop set in
// docxListPPr, the wrapped continuation lines land under the text instead of
// under the number, without needing a separate <w:tab/> element (so a
// re-extracted copy of this file still reads back "1.\tClause text" instead
// of losing the gap between marker and text).
func docxListMarkerRun(marker string, halfPoints int) string {
	return `<w:r>` + docxRunProps(services.RunStyle{}, halfPoints) +
		`<w:t xml:space="preserve">` + xmlEscape(marker) + "\t</w:t></w:r>"
}

const docxListPPr = `<w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="720"/><w:spacing w:after="120" w:line="276" w:lineRule="auto"/>`

func renderDocxBlock(b services.DocBlock) string {
	const bodySize = 22 // 11pt

	switch b.Kind {
	case services.BlockHeading1:
		return `<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="240"/><w:keepNext/></w:pPr>` +
			docxParagraphLines(b.Lines, 32) + `</w:p>`
	case services.BlockHeading2:
		return `<w:p><w:pPr><w:spacing w:before="240" w:after="120"/><w:keepNext/></w:pPr>` +
			docxParagraphLines(b.Lines, 26) + `</w:p>`
	case services.BlockHeading3:
		return `<w:p><w:pPr><w:spacing w:before="200" w:after="100"/><w:keepNext/></w:pPr>` +
			docxParagraphLines(b.Lines, 24) + `</w:p>`
	case services.BlockNumbered:
		return `<w:p><w:pPr>` + docxListPPr + `</w:pPr>` +
			docxListMarkerRun(b.Marker, bodySize) +
			docxParagraphLines(b.Lines, bodySize) + `</w:p>`
	case services.BlockBullet:
		return `<w:p><w:pPr>` + docxListPPr + `</w:pPr>` +
			docxListMarkerRun("•", bodySize) +
			docxParagraphLines(b.Lines, bodySize) + `</w:p>`
	case services.BlockDivider:
		return `<w:p><w:pPr><w:spacing w:before="120" w:after="120"/>` +
			`<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="999999"/></w:pBdr></w:pPr></w:p>`
	default: // BlockParagraph
		return `<w:p><w:pPr><w:jc w:val="both"/><w:spacing w:after="200" w:line="276" w:lineRule="auto"/></w:pPr>` +
			docxParagraphLines(b.Lines, bodySize) + `</w:p>`
	}
}
