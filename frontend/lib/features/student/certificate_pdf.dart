import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the OneLegal Certificate of Completion PDF, A4 landscape, laid
/// out to match the provided reference design as closely as the `pdf`
/// package's vector/text primitives allow -- no `printing`/network-fetched
/// font package is a dependency of this app, so the reference's script
/// font for the student's name and its photographic medal/watermark
/// artwork are approximated with the pdf package's built-in Times
/// (Base-14, no asset/network needed) italic/bold-italic faces and drawn
/// vector shapes (gold circle + ribbon for the medal, a faint scale glyph
/// for the left watermark) rather than reproduced pixel-for-pixel.
///
/// Every value below is a real argument, never a literal placeholder --
/// the caller (CertificateScreen) is the one that fetches the actual
/// student name, course name, certificate number and issue date from the
/// backend before calling this.
Future<pw.Document> buildCertificatePdf({
  required String studentName,
  required String courseName,
  required String certificateNumber,
  required String issueDateLabel,
  required String instructorName,
  required String directorName,
}) async {
  final doc = pw.Document();

  const navy = PdfColor.fromInt(0xFF0A1628);
  const gold = PdfColor.fromInt(0xFFD4AF37);
  const ivory = PdfColor.fromInt(0xFFFBF8F1);
  const textMuted = PdfColor.fromInt(0xFF55606E);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Stack(children: [
          // Ivory background with a very faint justice-scale watermark on
          // the left, approximating the reference's left-side watermark.
          pw.Container(color: ivory),
          pw.Positioned(
            left: 40,
            top: 160,
            child: pw.Opacity(
              opacity: 0.08,
              child: pw.Text('⚖',
                  style: const pw.TextStyle(fontSize: 220, color: navy)),
            ),
          ),

          // Top navy/gold curved band (approximated as angled bars).
          pw.Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: pw.Container(
              height: 10,
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(colors: [navy, gold, navy]),
              ),
            ),
          ),
          pw.Positioned(
            left: 0,
            bottom: 0,
            right: 0,
            child: pw.Container(
              height: 10,
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(colors: [navy, gold, navy]),
              ),
            ),
          ),

          // Outer decorative gold border.
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gold, width: 2.2),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
              ),
            ),
          ),

          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(42, 36, 42, 30),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // ── Header row: logo left, medal right ──
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Row(children: [
                          pw.Container(
                            width: 38,
                            height: 38,
                            decoration: const pw.BoxDecoration(
                                color: navy, shape: pw.BoxShape.circle),
                            child: pw.Center(
                                child: pw.Text('⚖',
                                    style: const pw.TextStyle(
                                        fontSize: 18, color: gold))),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('OneLegal',
                                    style: pw.TextStyle(
                                        font: pw.Font.timesBold(),
                                        fontSize: 20,
                                        color: navy)),
                                pw.Text('Learn  •  Practice  •  Excel',
                                    style: pw.TextStyle(
                                        font: pw.Font.times(),
                                        fontSize: 8.5,
                                        color: textMuted)),
                              ]),
                        ]),
                      ),
                      // Medal: gold ring + navy center + ribbon tails.
                      pw.Column(children: [
                        pw.Container(
                          width: 64,
                          height: 64,
                          decoration: const pw.BoxDecoration(
                              color: gold, shape: pw.BoxShape.circle),
                          child: pw.Center(
                            child: pw.Container(
                              width: 46,
                              height: 46,
                              decoration: const pw.BoxDecoration(
                                  color: navy, shape: pw.BoxShape.circle),
                              child: pw.Center(
                                  child: pw.Text('⚖',
                                      style: const pw.TextStyle(
                                          fontSize: 20, color: gold))),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Container(
                                  width: 14,
                                  height: 24,
                                  color: gold,
                                  margin:
                                      const pw.EdgeInsets.only(right: 2)),
                              pw.Container(
                                  width: 14, height: 24, color: gold),
                            ]),
                      ]),
                    ],
                  ),

                  pw.SizedBox(height: 14),

                  // ── Title ──
                  pw.Center(
                    child: pw.Text('CERTIFICATE',
                        style: pw.TextStyle(
                            font: pw.Font.timesBold(),
                            fontSize: 42,
                            color: navy,
                            letterSpacing: 2)),
                  ),
                  pw.Center(
                    child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Container(width: 60, height: 1, color: gold),
                          pw.SizedBox(width: 10),
                          pw.Text('OF COMPLETION',
                              style: pw.TextStyle(
                                  font: pw.Font.timesBold(),
                                  fontSize: 15,
                                  color: gold,
                                  letterSpacing: 4)),
                          pw.SizedBox(width: 10),
                          pw.Container(width: 60, height: 1, color: gold),
                        ]),
                  ),

                  pw.SizedBox(height: 16),
                  pw.Center(
                      child: pw.Text('This is to certify that',
                          style: pw.TextStyle(
                              font: pw.Font.timesItalic(),
                              fontSize: 13,
                              color: navy))),
                  pw.SizedBox(height: 10),

                  // ── Student name ──
                  pw.Center(
                    child: pw.Text(studentName,
                        style: pw.TextStyle(
                            font: pw.Font.timesBoldItalic(),
                            fontSize: 30,
                            color: navy)),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Center(
                      child:
                          pw.Container(width: 220, height: 1, color: gold)),

                  pw.SizedBox(height: 14),
                  pw.Center(
                      child: pw.Text('has successfully completed the course',
                          style: pw.TextStyle(
                              font: pw.Font.times(),
                              fontSize: 12.5,
                              color: navy))),
                  pw.SizedBox(height: 8),

                  // ── Course name box ──
                  pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 22, vertical: 8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: gold, width: 1.4),
                        borderRadius: pw.BorderRadius.circular(18),
                      ),
                      child: pw.Text(courseName,
                          style: pw.TextStyle(
                              font: pw.Font.timesBold(),
                              fontSize: 16,
                              color: navy)),
                    ),
                  ),

                  pw.SizedBox(height: 12),
                  pw.Center(
                    child: pw.Text(
                      'on OneLegal, demonstrating outstanding dedication,\n'
                      'knowledge and commitment to excellence.',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          font: pw.Font.times(), fontSize: 11, color: navy),
                    ),
                  ),

                  pw.SizedBox(height: 8),
                  pw.Center(
                      child: pw.Text('Keep Learning. Keep Growing.',
                          style: pw.TextStyle(
                              font: pw.Font.timesItalic(),
                              fontSize: 12,
                              color: gold))),

                  pw.Spacer(),

                  // ── Signatures row ──
                  pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Expanded(
                            child: _SignatureBlock(
                                name: instructorName,
                                title: 'Course Instructor')),
                        pw.SizedBox(
                          width: 90,
                          child: pw.Center(
                            child: pw.Text('★',
                                style:
                                    const pw.TextStyle(fontSize: 22, color: gold)),
                          ),
                        ),
                        pw.Expanded(
                            child: _SignatureBlock(
                                name: directorName, title: 'Director')),
                      ]),

                  pw.SizedBox(height: 14),
                  pw.Container(height: 0.6, color: gold),
                  pw.SizedBox(height: 6),

                  // ── Footer: certificate id + issue date ──
                  pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Certificate ID: $certificateNumber',
                            style: pw.TextStyle(
                                font: pw.Font.times(),
                                fontSize: 9.5,
                                color: textMuted)),
                        pw.Text('Issue Date: $issueDateLabel',
                            style: pw.TextStyle(
                                font: pw.Font.times(),
                                fontSize: 9.5,
                                color: textMuted)),
                      ]),
                ]),
          ),
        ]);
      },
    ),
  );

  return doc;
}

class _SignatureBlock extends pw.StatelessWidget {
  final String name;
  final String title;
  _SignatureBlock({required this.name, required this.title});

  @override
  pw.Widget build(pw.Context context) {
    const navy = PdfColor.fromInt(0xFF0A1628);
    const textMuted = PdfColor.fromInt(0xFF55606E);
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(name,
              style: pw.TextStyle(font: pw.Font.timesItalic(), fontSize: 13, color: navy)),
          pw.SizedBox(height: 4),
          pw.Container(width: 140, height: 0.8, color: navy),
          pw.SizedBox(height: 3),
          pw.Text(title,
              style: pw.TextStyle(font: pw.Font.timesBold(), fontSize: 10, color: navy)),
          pw.Text('OneLegal',
              style: pw.TextStyle(font: pw.Font.times(), fontSize: 9, color: textMuted)),
        ]);
  }
}
