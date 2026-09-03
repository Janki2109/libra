package services

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"strings"

	"github.com/ledongthuc/pdf"
)

// maxExtractedTextChars keeps an extracted document within a sane size for a
// single AI prompt — a large PDF's full text could otherwise blow past the
// model's context window on its own, before the user's actual question or
// the system prompt are even added.
const maxExtractedTextChars = 50000

// ExtractDocumentText pulls plain text out of a PDF, DOCX or plain-text file
// so a lawyer can upload the actual document instead of copy-pasting its
// contents by hand. Scanned/image-only PDFs have no text layer to extract —
// that case returns an error explaining why, rather than silently returning
// nothing.
func ExtractDocumentText(fileBytes []byte, ext string) (string, error) {
	var text string
	var err error

	switch strings.ToLower(ext) {
	case "pdf":
		text, err = extractPDFText(fileBytes)
	case "docx":
		text, err = extractDOCXText(fileBytes)
	case "txt":
		text = string(fileBytes)
	default:
		return "", fmt.Errorf("unsupported file type: %s (use PDF, DOCX or TXT)", ext)
	}
	if err != nil {
		return "", err
	}

	text = strings.TrimSpace(text)
	if text == "" {
		return "", fmt.Errorf("no text found in this file — if it's a scanned document, use the OCR tool instead")
	}
	if len(text) > maxExtractedTextChars {
		text = text[:maxExtractedTextChars] + "\n\n[truncated — document exceeds the size this tool can process at once]"
	}
	return text, nil
}

func extractPDFText(fileBytes []byte) (string, error) {
	reader, err := pdf.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		return "", fmt.Errorf("could not read PDF: %w", err)
	}

	var b strings.Builder
	for i := 1; i <= reader.NumPage(); i++ {
		page := reader.Page(i)
		if page.V.IsNull() {
			continue
		}
		content, err := page.GetPlainText(nil)
		if err != nil {
			continue // one unreadable page shouldn't fail the whole document
		}
		b.WriteString(content)
		b.WriteString("\n")
	}
	return b.String(), nil
}

// docxParagraph/docxRun/docxText mirror just enough of a .docx's
// word/document.xml to pull out the visible text, in document order.
type docxText struct {
	Body docxBody `xml:"body"`
}
type docxBody struct {
	Paragraphs []docxParagraph `xml:"p"`
}
type docxParagraph struct {
	Runs []docxRun `xml:"r"`
}
type docxRun struct {
	Text string `xml:"t"`
}

func extractDOCXText(fileBytes []byte) (string, error) {
	zr, err := zip.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		return "", fmt.Errorf("could not read DOCX: %w", err)
	}

	var docXML *zip.File
	for _, f := range zr.File {
		if f.Name == "word/document.xml" {
			docXML = f
			break
		}
	}
	if docXML == nil {
		return "", fmt.Errorf("not a valid DOCX file")
	}

	rc, err := docXML.Open()
	if err != nil {
		return "", err
	}
	defer rc.Close()

	raw, err := io.ReadAll(rc)
	if err != nil {
		return "", err
	}

	var doc docxText
	if err := xml.Unmarshal(raw, &doc); err != nil {
		return "", fmt.Errorf("could not parse DOCX content: %w", err)
	}

	var b strings.Builder
	for _, p := range doc.Body.Paragraphs {
		for _, r := range p.Runs {
			b.WriteString(r.Text)
		}
		b.WriteString("\n")
	}
	return b.String(), nil
}
