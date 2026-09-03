package services

import _ "embed"

// These embedded Noto Sans fonts give the PDF exporter real glyph coverage
// for the Brahmic scripts used by the Translator's Indian-language options
// (Hindi/Marathi, Bengali, Punjabi, Gujarati, Tamil, Telugu, Kannada).
// fpdf's built-in "Times" font only understands single-byte cp1252, which
// has no slot for any of these scripts at all.
//
//go:embed fonts/NotoSansDevanagari.ttf
var NotoSansDevanagariTTF []byte

//go:embed fonts/NotoSansBengali.ttf
var NotoSansBengaliTTF []byte

//go:embed fonts/NotoSansGurmukhi.ttf
var NotoSansGurmukhiTTF []byte

//go:embed fonts/NotoSansGujarati.ttf
var NotoSansGujaratiTTF []byte

//go:embed fonts/NotoSansTamil.ttf
var NotoSansTamilTTF []byte

//go:embed fonts/NotoSansTelugu.ttf
var NotoSansTeluguTTF []byte

//go:embed fonts/NotoSansKannada.ttf
var NotoSansKannadaTTF []byte
