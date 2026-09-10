import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';
import '../utils/browser_download.dart';
import '../utils/android_download.dart';

// OneLegal theme — matches the splash screen and login screen exactly
// (AppColors is the same palette those already use), so this page visually
// belongs to the same app instead of its old brown/beige look.
const _bg = AppColors.bg;
const _bgCard = AppColors.bgCard;
const _surface = AppColors.surface;
const _gold = AppColors.gold;
const _goldLight = AppColors.goldLight;
const _border = AppColors.border;
const _borderGold = AppColors.borderGold;
const _textPri = AppColors.textPrimary;
const _textMuted = AppColors.textSecondary;
const _blue = AppColors.info;
const _purple = AppColors.purple;
const _error = AppColors.error;

class AIDraftingScreen extends StatefulWidget {
  const AIDraftingScreen({super.key});
  @override
  State<AIDraftingScreen> createState() => _AIDraftingScreenState();
}

class _AIDraftingScreenState extends State<AIDraftingScreen> {
  Map<String, dynamic>? _selectedTemplate;
  final Map<String, TextEditingController> _fieldCtrls = {};
  String _generatedDoc = '';
  bool _loading = false;
  bool _generated = false;

  // ── AI Tools (Drafter / Generate Summary / Translator / OCR / Timeline /
  // Ask / Compare / Citation Verifier) — Drafter runs through /ai/draft (the
  // same endpoint the template flow below already uses); the other seven
  // share /ai/tool, dispatched server-side by the 'tool' field.
  String? _activeTool;
  final _toolTextCtrl = TextEditingController();
  final _toolSecondTextCtrl = TextEditingController();
  final _toolQuestionCtrl = TextEditingController();
  String? _toolLanguage;
  String _toolResult = '';
  bool _toolLoading = false;
  bool _toolGenerated = false;
  Uint8List? _ocrImageBytes;
  String _ocrMimeType = 'image/jpeg';
  bool _exporting = false;
  bool _exportingPdf = false;

  static const List<String> _translateLanguages = [
    'English',
    'Hindi',
    'Marathi',
    'Gujarati',
    'Tamil',
    'Telugu',
    'Kannada',
    'Bengali',
    'Punjabi',
    'Urdu',
  ];

  final List<Map<String, dynamic>> _aiTools = [
    {
      'key': 'drafter',
      'name': 'Drafter',
      'icon': Icons.edit_document,
      'desc': 'Draft a document',
    },
    {
      'key': 'summary',
      'name': 'Generate Summary',
      'icon': Icons.summarize_rounded,
      'desc': 'Summarize a document',
    },
    {
      'key': 'translate',
      'name': 'Translator',
      'icon': Icons.translate_rounded,
      'desc': 'Translate to any language',
    },
    {
      'key': 'ocr',
      'name': 'OCR',
      'icon': Icons.document_scanner_rounded,
      'desc': 'Extract text from an image',
    },
    {
      'key': 'timeline',
      'name': 'Timeline Generator',
      'icon': Icons.timeline_rounded,
      'desc': 'Chronological case timeline',
    },
    {
      'key': 'ask',
      'name': 'Ask Questions',
      'icon': Icons.question_answer_rounded,
      'desc': 'Ask about a document',
    },
    {
      'key': 'compare',
      'name': 'Compare Documents',
      'icon': Icons.compare_arrows_rounded,
      'desc': 'Spot the differences',
    },
    {
      'key': 'citation',
      'name': 'Citation Verifier',
      'icon': Icons.fact_check_rounded,
      'desc': 'Check legal citations',
    },
  ];

  final List<Map<String, dynamic>> _templates = [
    {
      'name': 'Legal Notice',
      'icon': '📜',
      'color': const Color(0xFFD9534F),
      'desc': 'Send formal legal notice to a party',
      'fields': [
        'Sender Name',
        'Sender Address',
        'Recipient Name',
        'Recipient Address',
        'Subject of Notice',
        'Details of Grievance',
        'Relief Sought',
        'Deadline (days)'
      ],
    },
    {
      'name': 'Affidavit',
      'icon': '📋',
      'color': _purple,
      'desc': 'Sworn statement of facts',
      'fields': [
        'Deponent Name',
        'Deponent Address',
        'Deponent Occupation',
        'Court/Authority Name',
        'Purpose of Affidavit',
        'Facts to State',
        'Place',
        'Date'
      ],
    },
    {
      'name': 'Bail Application',
      'icon': '🔓',
      'color': const Color(0xFF2E8B57),
      'desc': 'Application for bail in criminal case',
      'fields': [
        'Accused Name',
        'FIR Number',
        'Police Station',
        'Date of Arrest',
        'Sections Charged',
        'Court Name',
        'Grounds for Bail',
        'Surety Details'
      ],
    },
    {
      'name': 'Petition',
      'icon': '⚖️',
      'color': _blue,
      'desc': 'Court petition / writ petition',
      'fields': [
        'Petitioner Name',
        'Petitioner Address',
        'Respondent Name',
        'Court Name',
        'Subject Matter',
        'Facts of Case',
        'Legal Grounds',
        'Prayer/Relief Sought'
      ],
    },
    {
      'name': 'Agreement',
      'icon': '🤝',
      'color': const Color(0xFF7C3AED),
      'desc': 'Contract / agreement between parties',
      'fields': [
        'Party 1 Name',
        'Party 1 Address',
        'Party 2 Name',
        'Party 2 Address',
        'Subject of Agreement',
        'Terms & Conditions',
        'Duration',
        'Date'
      ],
    },
    {
      'name': 'Vakalatnama',
      'icon': '👨‍⚖️',
      'color': _gold,
      'desc': 'Power of attorney to represent client',
      'fields': [
        'Client Name',
        'Client Address',
        'Advocate Name',
        'Advocate Enrollment No',
        'Court Name',
        'Case Details',
        'Date'
      ],
    },
    {
      'name': 'Written Statement',
      'icon': '📝',
      'color': const Color(0xFF0D6E4F),
      'desc': 'Reply to plaint in civil case',
      'fields': [
        'Defendant Name',
        'Plaintiff Name',
        'Case Number',
        'Court Name',
        'Preliminary Objections',
        'Reply to Allegations',
        'Counter Claims',
        'Date'
      ],
    },
    {
      'name': 'Complaint',
      'icon': '📣',
      'color': const Color(0xFFD4A017),
      'desc': 'Formal complaint to court/authority',
      'fields': [
        'Complainant Name',
        'Complainant Address',
        'Accused/Respondent Name',
        'Authority/Court',
        'Nature of Complaint',
        'Incident Details',
        'Evidence',
        'Relief Sought'
      ],
    },
  ];

  void _selectTemplate(Map<String, dynamic> template) {
    setState(() {
      _selectedTemplate = template;
      _generatedDoc = '';
      _generated = false;
      _fieldCtrls.clear();
      for (final field in template['fields'] as List<String>) {
        _fieldCtrls[field] = TextEditingController();
      }
    });
  }

  void _selectTool(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _activeTool = key;
      _selectedTemplate = null;
      _toolResult = '';
      _toolGenerated = false;
      _toolTextCtrl.clear();
      _toolSecondTextCtrl.clear();
      _toolQuestionCtrl.clear();
      _toolLanguage = null;
      _ocrImageBytes = null;
    });
  }

  void _closeTool() {
    setState(() {
      _activeTool = null;
      _toolResult = '';
      _toolGenerated = false;
    });
  }

  // Which text controller is currently mid-extraction, so its own "Upload
  // Document" button can show a spinner without blocking the others (used
  // by Compare, which has two independent upload slots).
  TextEditingController? _extractingInto;

  /// Lets a tool be run against an actual uploaded document instead of
  /// requiring the text to be pasted in by hand. Extraction happens
  /// server-side and needs no AI call — it just reads the PDF/DOCX/TXT's
  /// own text layer — so it works even without any AI provider configured.
  /// A scanned/image-only PDF has no text layer to pull from; that's what
  /// the separate OCR tool is for.
  Future<void> _pickAndExtractDocument(TextEditingController target) async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'txt'],
        withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) {
      _showToolError('Could not read the selected file. Please try again.');
      return;
    }
    final ext = file.name.split('.').last.toLowerCase();

    setState(() => _extractingInto = target);
    try {
      final res = await DioClient.instance.post('/ai/extract-text', data: {
        'file_content': base64Encode(file.bytes!),
        'file_type': ext,
      });
      final text = res.data['data']?['text'] as String? ?? '';
      setState(() {
        target.text = text;
        _extractingInto = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Extracted text from ${file.name}'),
            backgroundColor: const Color(0xFF2E8B57)));
      }
    } catch (e) {
      setState(() => _extractingInto = null);
      _showToolError(DioClient.describeError(e));
    }
  }

  Future<void> _pickOcrImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1800);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      setState(() {
        _ocrImageBytes = bytes;
        _ocrMimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not access camera/gallery.'),
          backgroundColor: _error));
    }
  }

  // Every AI Tool goes through the SAME backend endpoint used for Drafter's
  // key rotation — /ai/tool — so each Generate click here is a fresh, live
  // Groq request too, never a cached/previous result.
  Future<void> _generateTool() async {
    final tool = _activeTool;
    if (tool == null) return;

    // Drafter goes through /ai/draft — the same freeform-prompt endpoint the
    // template flow below already uses — since /ai/tool's dispatch only
    // covers the other seven tools; everything else shares /ai/tool.
    if (tool == 'drafter') {
      if (_toolTextCtrl.text.trim().isEmpty) {
        _showToolError('Please enter what you need drafted');
        return;
      }
      await _runGenerate(
        request: () => DioClient.instance.post('/ai/draft', data: {
          'prompt':
              'Generate a professional Indian legal document based on the '
                  'following instructions/content. Follow Indian legal '
                  'format and conventions, use formal legal language, and '
                  'make it court-ready:\n\n${_toolTextCtrl.text.trim()}',
        }),
      );
      return;
    }

    final data = <String, dynamic>{'tool': tool};
    switch (tool) {
      case 'summary':
      case 'timeline':
      case 'citation':
        if (_toolTextCtrl.text.trim().isEmpty) {
          _showToolError('Please provide the document text');
          return;
        }
        data['text'] = _toolTextCtrl.text.trim();
        break;
      case 'translate':
        if (_toolTextCtrl.text.trim().isEmpty || _toolLanguage == null) {
          _showToolError('Please provide the text and select a target language');
          return;
        }
        data['text'] = _toolTextCtrl.text.trim();
        data['target_language'] = _toolLanguage!;
        break;
      case 'ask':
        if (_toolTextCtrl.text.trim().isEmpty ||
            _toolQuestionCtrl.text.trim().isEmpty) {
          _showToolError('Please provide the document and your question');
          return;
        }
        data['text'] = _toolTextCtrl.text.trim();
        data['question'] = _toolQuestionCtrl.text.trim();
        break;
      case 'compare':
        if (_toolTextCtrl.text.trim().isEmpty ||
            _toolSecondTextCtrl.text.trim().isEmpty) {
          _showToolError('Please provide both documents');
          return;
        }
        data['text'] = _toolTextCtrl.text.trim();
        data['second_text'] = _toolSecondTextCtrl.text.trim();
        break;
      case 'ocr':
        if (_ocrImageBytes == null) {
          _showToolError('Please provide a document image');
          return;
        }
        data['image_base64'] =
            'data:$_ocrMimeType;base64,${base64Encode(_ocrImageBytes!)}';
        break;
    }

    await _runGenerate(
        request: () => DioClient.instance.post('/ai/tool', data: data));
  }

  /// Shared request/loading/result plumbing for every AI Tool (Drafter
  /// included) — one place that sets the loading state, unpacks `content`,
  /// catches a failed request, and treats an empty-but-"successful" response
  /// as a failure too instead of silently showing a blank result.
  Future<void> _runGenerate(
      {required Future<dynamic> Function() request}) async {
    setState(() {
      _toolLoading = true;
      _toolGenerated = false;
    });
    HapticFeedback.lightImpact();
    try {
      final response = await request();
      final content = (response.data['data']?['content'] ?? '') as String;
      if (content.trim().isEmpty) {
        setState(() => _toolLoading = false);
        _showToolError('The AI returned an empty result. Please try again.');
        return;
      }
      setState(() {
        _toolResult = content;
        _toolLoading = false;
        _toolGenerated = true;
      });
    } catch (e) {
      setState(() => _toolLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: _error));
      }
    }
  }

  void _showToolError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: _error));
  }

  /// Shared by the Word and PDF buttons on every result (Drafter, every
  /// other AI Tool, and the template flow) — one implementation instead of
  /// two near-identical copies, so a fix here fixes both everywhere they're
  /// used.
  ///
  /// dart:io's File and path_provider's getTemporaryDirectory() have no real
  /// filesystem to work with on Flutter Web — constructing a File there
  /// throws at runtime (it compiles fine, so this wasn't caught until it ran
  /// in a browser), which is what made every "Word"/"PDF" button fail with
  /// "Could not export document: Something went wrong" — a non-network
  /// error, so DioClient.describeError fell through to its generic message.
  /// triggerBrowserDownload handles the actual file delivery on web (a
  /// browser "Save As" via Blob + <a download>); everywhere else this falls
  /// back to the original temp-file + OS share sheet flow, unchanged.
  Future<void> _exportFile({
    required String endpoint,
    required String title,
    required String content,
    required String mimeType,
    required bool isExporting,
    required void Function(bool) setExporting,
  }) async {
    if (content.trim().isEmpty) {
      _showToolError('Nothing to export yet — generate a result first.');
      return;
    }
    if (isExporting) return;
    setExporting(true);
    try {
      final res = await DioClient.instance
          .post(endpoint, data: {'title': title, 'content': content});
      final data = res.data['data'];
      final base64File = data?['file_base64'] as String?;
      final fileName = data?['file_name'] as String?;
      if (base64File == null || fileName == null) {
        throw Exception('The server did not return a file');
      }
      final bytes = base64Decode(base64File);

      if (triggerBrowserDownload(bytes, fileName, mimeType)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$fileName downloaded'),
            backgroundColor: const Color(0xFF2E8B57),
            behavior: SnackBarBehavior.floating));
        return;
      }

      // Android: save straight into the real Downloads folder — this used
      // to skip straight to the share sheet below, which only saved the
      // file if the user separately chose "Save to Files" there, so nothing
      // was actually downloaded by default.
      if (await saveToAndroidDownloads(bytes, fileName, mimeType)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$fileName saved to Downloads'),
            backgroundColor: const Color(0xFF2E8B57),
            behavior: SnackBarBehavior.floating));
        return;
      }

      // iOS / older Android without Downloads access: no bare filesystem
      // download, so save to a temp file and hand it to the OS share sheet
      // (Save to Files, send to another app) — that stands in for
      // "download" there.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          text: 'Exported from OneLegal Smart Draft');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not export document: ${DioClient.describeError(e)}'),
          backgroundColor: _error));
    } finally {
      if (mounted) setExporting(false);
    }
  }

  Future<void> _exportAsWord(String title, String content) => _exportFile(
        endpoint: '/ai/export-docx',
        title: title,
        content: content,
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        isExporting: _exporting,
        setExporting: (v) => setState(() => _exporting = v),
      );

  /// /ai/export-pdf renders every Indian-language script in the Translator's
  /// dropdown (Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, Telugu,
  /// Kannada) with an embedded Unicode font. Arabic/Urdu is the one
  /// exception still rejected with a clear message — surfaced via the catch
  /// block above — since it's a cursive script that needs real shaping to
  /// join letters, which the PDF library can't do; Word/LibreOffice do their
  /// own shaping on open, so that one script is still pointed there.
  Future<void> _exportAsPdf(String title, String content) => _exportFile(
        endpoint: '/ai/export-pdf',
        title: title,
        content: content,
        mimeType: 'application/pdf',
        isExporting: _exportingPdf,
        setExporting: (v) => setState(() => _exportingPdf = v),
      );

  /// Falls back to a clipboard copy instead of surfacing a raw error when
  /// the browser has no native share target available (desktop browsers
  /// commonly don't implement the Web Share API) — the previous unguarded
  /// call is what produced "Could not export document: Something went
  /// wrong" on the Share button, which doesn't even touch file export.
  Future<void> _shareText(String content) async {
    if (content.trim().isEmpty) {
      _showToolError('Nothing to share yet — generate a result first.');
      return;
    }
    try {
      await Share.share(content);
    } catch (_) {
      Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Sharing isn't available here — copied to clipboard instead."),
          backgroundColor: Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating));
    }
  }

  void _copyToolResult() {
    Clipboard.setData(ClipboardData(text: _toolResult));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied to clipboard!'),
        backgroundColor: Color(0xFF2E8B57),
        behavior: SnackBarBehavior.floating));
  }

  /// The Word / PDF / Share action row shown under every result — the
  /// template-generated document and every AI Tool's result — so both
  /// places stay in sync instead of keeping two copies of the same row.
  Widget _exportActionsRow(String title, String content) => Row(children: [
        Expanded(
            child: OutlinedButton.icon(
          onPressed: _exporting ? null : () => _exportAsWord(title, content),
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _goldLight))
              : const Icon(Icons.description_rounded,
                  color: _goldLight, size: 18),
          label: const Text('Word', style: TextStyle(color: _textPri, fontSize: 13)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        )),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
          onPressed:
              _exportingPdf ? null : () => _exportAsPdf(title, content),
          icon: _exportingPdf
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _goldLight))
              : const Icon(Icons.picture_as_pdf_rounded,
                  color: _goldLight, size: 18),
          label: const Text('PDF', style: TextStyle(color: _textPri, fontSize: 13)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        )),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
          onPressed: () => _shareText(content),
          icon: const Icon(Icons.share_rounded, color: _goldLight, size: 18),
          label: const Text('Share', style: TextStyle(color: _textPri, fontSize: 13)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        )),
      ]);

  Future<void> _generate() async {
    if (_selectedTemplate == null) return;
    final emptyFields = _fieldCtrls.entries
        .where((e) => e.value.text.trim().isEmpty)
        .map((e) => e.key)
        .toList();
    if (emptyFields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please fill: ${emptyFields.take(2).join(', ')}'),
        backgroundColor: _error,
      ));
      return;
    }
    setState(() {
      _loading = true;
      _generated = false;
    });
    HapticFeedback.lightImpact();
    try {
      final fields = _fieldCtrls.entries
          .map((e) => '${e.key}: ${e.value.text.trim()}')
          .join('\n');
      final prompt =
          '''Generate a professional Indian legal ${_selectedTemplate!['name']} document.

Details provided:
$fields

Requirements:
- Follow Indian legal format and conventions
- Use formal legal language
- Include all necessary legal provisions
- Add appropriate sections and headings
- Make it court-ready
- Include signature blocks at the end

Generate the complete document now:''';

      // The Groq key(s) and rotation live on the backend only — this screen
      // never talks to the AI provider directly.
      final response = await DioClient.instance
          .post('/ai/draft', data: {'prompt': prompt});
      setState(() {
        _generatedDoc = response.data['data']?['content'] ?? '';
        _loading = false;
        _generated = true;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _error));
      }
    }
  }

  void _copyDoc() {
    Clipboard.setData(ClipboardData(text: _generatedDoc));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Document copied to clipboard!'),
        backgroundColor: Color(0xFF2E8B57),
        behavior: SnackBarBehavior.floating));
  }

  /// Steps back one level at a time — result/form → template or tool list →
  /// tool grid → leave the screen — instead of the header arrow (and the
  /// system/gesture back button) always leaving Smart Draft outright no
  /// matter how deep the user was in a tool.
  bool get _atTopLevel => _activeTool == null && _selectedTemplate == null;

  void _handleBack() {
    if (_activeTool != null) {
      _closeTool();
      return;
    }
    if (_selectedTemplate != null) {
      setState(() {
        _selectedTemplate = null;
        _generatedDoc = '';
        _generated = false;
        _fieldCtrls.clear();
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _atTopLevel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header — same navy/purple gradient + gold accent as the OneLegal
        // splash and login screens.
        Container(
          decoration: const BoxDecoration(gradient: AppColors.bgGradient),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 14),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: _handleBack),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _gold, width: 1.3),
                      boxShadow: [
                        BoxShadow(
                            color: _gold.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1),
                      ],
                    ),
                    child: const Icon(Icons.balance_rounded,
                        color: _gold, size: 17),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart Draft',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Create court-ready legal documents',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  )),
                  if (_activeTool != null)
                    TextButton(
                      onPressed: _closeTool,
                      child: const Text('AI Tools',
                          style: TextStyle(
                              color: _goldLight, fontWeight: FontWeight.w700)),
                    )
                  else if (_selectedTemplate != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedTemplate = null;
                        _generatedDoc = '';
                        _generated = false;
                        _fieldCtrls.clear();
                      }),
                      child: const Text('Templates',
                          style: TextStyle(
                              color: _goldLight, fontWeight: FontWeight.w700)),
                    ),
                ]),
              )),
        ),

        Expanded(
            child: _activeTool != null
                ? _buildToolRunner()
                : _selectedTemplate == null
                    ? _buildTemplateGrid()
                    : _generated
                        ? _buildGeneratedDoc()
                        : _buildForm()),
      ]),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────
  Widget _buildHero() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [_surface, _bgCard],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _borderGold),
          boxShadow: [
            BoxShadow(
                color: _gold.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 1),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                    text: const TextSpan(
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.25),
                        children: [
                      TextSpan(
                          text: 'Smart Draft.\n',
                          style: TextStyle(color: Colors.white)),
                      TextSpan(
                          text: 'Legal Simplified.',
                          style: TextStyle(color: _goldLight)),
                    ])),
                const SizedBox(height: 8),
                const Text(
                    'Create accurate, professional and court-ready legal documents in minutes with AI.',
                    style: TextStyle(
                        color: _textMuted, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withValues(alpha: 0.08),
              border: Border.all(color: _gold.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                    color: _gold.withValues(alpha: 0.3),
                    blurRadius: 18,
                    spreadRadius: 2),
              ],
            ),
            child: const Icon(Icons.balance_rounded, color: _gold, size: 28),
          ),
        ]),
      );

  // ── Security banner ─────────────────────────────
  Widget _buildSecurityBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                    color: _gold.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 1),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: _gold, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Secure. Private. Reliable.',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                SizedBox(height: 2),
                Text('Your documents are encrypted and 100% confidential.',
                    style: TextStyle(color: _textMuted, fontSize: 11)),
              ])),
        ]),
      );

  Widget _buildTemplateGrid() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _buildHero(),
        const SizedBox(height: 22),

        const Text('AI Tools',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Everything OneLegal can do for you',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78),
          itemCount: _aiTools.length,
          itemBuilder: (_, i) {
            final tool = _aiTools[i];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _selectTool(tool['key']),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              _gold.withValues(alpha: 0.16),
                              _purple.withValues(alpha: 0.16),
                            ]),
                            borderRadius: BorderRadius.circular(13)),
                        child: Icon(tool['icon'], color: _goldLight, size: 22)),
                    const SizedBox(height: 6),
                    Text(tool['name'],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 26),

        const Text('Choose Document Type',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Select a template to start drafting',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25),
          itemCount: _templates.length,
          itemBuilder: (_, i) {
            final t = _templates[i];
            final color = t['color'] as Color;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _selectTemplate(t);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2))
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(t['icon'], style: const TextStyle(fontSize: 24)),
                          const Spacer(),
                          Icon(Icons.arrow_forward_ios_rounded,
                              color: color.withValues(alpha: 0.6), size: 12),
                        ]),
                        const SizedBox(height: 8),
                        Text(t['name'],
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(t['desc'],
                            style: const TextStyle(
                                color: _textMuted, fontSize: 10),
                            maxLines: 2),
                      ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),

        _buildSecurityBanner(),
        const SizedBox(height: 40),
      ]);

  Widget _buildForm() {
    final t = _selectedTemplate!;
    final color = t['color'] as Color;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Template header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Row(children: [
          Text(t['icon'], style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(t['name'],
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                Text(t['desc'],
                    style: const TextStyle(color: _textMuted, fontSize: 12)),
              ])),
        ]),
      ),
      const SizedBox(height: 20),
      const Text('Fill in the details',
          style: TextStyle(
              color: _textPri, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),

      // Fields
      ...(t['fields'] as List<String>).map((field) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _fieldCtrls[field],
              style: const TextStyle(color: _textPri, fontSize: 14),
              maxLines: field.contains('Details') ||
                      field.contains('Facts') ||
                      field.contains('Terms') ||
                      field.contains('Grounds')
                  ? 3
                  : 1,
              decoration: InputDecoration(
                labelText: field,
                labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border, width: 0.8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color, width: 1.5)),
              ),
            ),
          )),
      const SizedBox(height: 20),

      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _loading ? null : _generate,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Color(0xFF0A0A14), strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0A0A14)),
          label: Text(_loading ? 'Generating...' : 'Generate Document',
              style: const TextStyle(
                  color: Color(0xFF0A0A14),
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _buildGeneratedDoc() => Column(children: [
        // Action bar
        Container(
          color: _bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
                child: Text('${_selectedTemplate!['name']} Generated ✅',
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w700,
                        fontSize: 14))),
            GestureDetector(
              onTap: _copyDoc,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: _gold, borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy_rounded, color: Color(0xFF0A0A14), size: 16),
                  SizedBox(width: 6),
                  Text('Copy',
                      style: TextStyle(
                          color: Color(0xFF0A0A14),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _generated = false;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border)),
                child: const Text('Edit',
                    style: TextStyle(
                        color: _goldLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          ]),
        ),
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border, width: 0.8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child: SelectableText(_generatedDoc,
                style: const TextStyle(
                    color: _textPri,
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'monospace')),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _copyDoc,
              icon: const Icon(Icons.copy_all_rounded, color: Color(0xFF0A0A14)),
              label: const Text('Copy Entire Document',
                  style: TextStyle(
                      color: Color(0xFF0A0A14), fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
            ),
          ),
          const SizedBox(height: 10),
          _exportActionsRow(_selectedTemplate!['name'], _generatedDoc),
          const SizedBox(height: 40),
        ])),
      ]);

  // ── AI Tools runner (Summary / Translator / OCR / Timeline / Ask /
  // Compare / Citation Verifier) ─────────────────
  Widget _buildToolRunner() {
    final tool = _aiTools.firstWhere((t) => t['key'] == _activeTool);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderGold)),
        child: Row(children: [
          Icon(tool['icon'], color: _goldLight, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(tool['name'],
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                Text(tool['desc'],
                    style: const TextStyle(color: _textMuted, fontSize: 12)),
              ])),
        ]),
      ),
      const SizedBox(height: 20),
      ..._buildToolInputs(_activeTool!),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _toolLoading ? null : _generateTool,
          icon: _toolLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Color(0xFF0A0A14), strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0A0A14)),
          label: Text(_toolLoading ? 'Generating...' : 'Generate',
              style: const TextStyle(
                  color: Color(0xFF0A0A14),
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ),
      if (_toolGenerated) ...[
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(
              child: Text('Result',
                  style: TextStyle(
                      color: _textPri,
                      fontWeight: FontWeight.w700,
                      fontSize: 14))),
          GestureDetector(
            onTap: _copyToolResult,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: _gold, borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.copy_rounded, color: Color(0xFF0A0A14), size: 16),
                SizedBox(width: 6),
                Text('Copy',
                    style: TextStyle(
                        color: Color(0xFF0A0A14),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: SelectableText(_toolResult,
              style: const TextStyle(
                  color: _textPri,
                  fontSize: 13,
                  height: 1.6,
                  fontFamily: 'monospace')),
        ),
        const SizedBox(height: 10),
        _exportActionsRow(
            _activeTool == 'translate' ? 'Translated Document' : tool['name'],
            _toolResult),
      ] else if (!_toolLoading) ...[
        const SizedBox(height: 20),
        _toolEmptyState(_activeTool!),
      ],
      const SizedBox(height: 40),
    ]);
  }

  /// Shown before a result exists (and never once one does), so the panel
  /// never sits blank and never shows stale/placeholder content mistaken for
  /// real output — only ever the actual generated/translated text once
  /// _generateTool succeeds.
  Widget _toolEmptyState(String toolKey) {
    final message = toolKey == 'translate'
        ? 'Your translated text will appear here.'
        : 'Your result will appear here once generated.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 0.8)),
      child: Column(children: [
        Icon(Icons.translate_rounded,
            color: _textMuted.withValues(alpha: 0.5), size: 36),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMuted, fontSize: 13)),
      ]),
    );
  }

  List<Widget> _buildToolInputs(String tool) {
    Widget textArea(TextEditingController ctrl, String label) {
      final extracting = _extractingInto == ctrl;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            onPressed:
                extracting ? null : () => _pickAndExtractDocument(ctrl),
            icon: extracting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _goldLight))
                : const Icon(Icons.upload_file_rounded,
                    color: _goldLight, size: 16),
            label: Text(extracting ? 'Extracting…' : 'Upload Document (PDF/DOCX/TXT)',
                style: const TextStyle(color: _textPri, fontSize: 12)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(color: _textPri, fontSize: 13),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border, width: 0.8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold, width: 1.5)),
            ),
          ),
        ]),
      );
    }

    Widget shortField(TextEditingController ctrl, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: ctrl,
            style: const TextStyle(color: _textPri, fontSize: 14),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border, width: 0.8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold, width: 1.5)),
            ),
          ),
        );

    Widget languageDropdown() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _toolLanguage,
            isExpanded: true,
            dropdownColor: _bgCard,
            style: const TextStyle(color: _textPri, fontSize: 14),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: _goldLight),
            decoration: InputDecoration(
              labelText: 'Target Language',
              labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border, width: 0.8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold, width: 1.5)),
            ),
            hint: const Text('Select Language',
                style: TextStyle(color: _textMuted, fontSize: 14)),
            items: _translateLanguages
                .map((lang) =>
                    DropdownMenuItem(value: lang, child: Text(lang)))
                .toList(),
            onChanged: (v) => setState(() => _toolLanguage = v),
          ),
        );

    switch (tool) {
      case 'drafter':
        return [
          textArea(_toolTextCtrl,
              'Describe what you need drafted, or paste reference content'),
        ];
      case 'summary':
      case 'timeline':
      case 'citation':
        return [textArea(_toolTextCtrl, 'Paste the document text')];
      case 'translate':
        return [
          textArea(_toolTextCtrl, 'Paste the document/text'),
          languageDropdown(),
        ];
      case 'ask':
        return [
          textArea(_toolTextCtrl, 'Paste the document/context'),
          shortField(_toolQuestionCtrl, 'Your question'),
        ];
      case 'compare':
        return [
          textArea(_toolTextCtrl, 'Document A'),
          textArea(_toolSecondTextCtrl, 'Document B'),
        ];
      case 'ocr':
        return [
          if (_ocrImageBytes != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border)),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_ocrImageBytes!,
                        width: 56, height: 56, fit: BoxFit.cover)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Image selected',
                        style: TextStyle(
                            color: _textPri, fontWeight: FontWeight.w600))),
              ]),
            ),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _pickOcrImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined,
                        color: _goldLight, size: 18),
                    label: const Text('Gallery',
                        style: TextStyle(color: _textPri)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _pickOcrImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: _goldLight, size: 18),
                    label: const Text('Camera',
                        style: TextStyle(color: _textPri)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))))),
          ]),
        ];
      default:
        return [];
    }
  }
}
