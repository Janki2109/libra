import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _blue = Color(0xFF1565C0);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);
const _gold = Color(0xFFFFD700);

class CertificateScreen extends StatelessWidget {
  const CertificateScreen({super.key});

  final List<Map<String, dynamic>> _certificates = const [
    {
      'title': 'Constitutional Law Expert',
      'icon': '📜',
      'color': Color(0xFF1565C0),
      'requirement': 'Score 80%+ in Constitutional Law Quiz',
      'xp': 500,
      'earned': false,
      'skills': [
        'Fundamental Rights',
        'DPSP',
        'Amendment Procedure',
        'Landmark Cases'
      ],
    },
    {
      'title': 'Criminal Law Specialist',
      'icon': '⚖️',
      'color': Color(0xFFD9534F),
      'requirement': 'Score 80%+ in BNS/IPC Quiz',
      'xp': 500,
      'earned': false,
      'skills': ['BNS Sections', 'Bail Laws', 'Offences', 'Criminal Procedure'],
    },
    {
      'title': 'Legal Researcher',
      'icon': '🔍',
      'color': Color(0xFF7C3AED),
      'requirement': 'Complete 10 AI Legal Research sessions',
      'xp': 300,
      'earned': false,
      'skills': ['Case Law Research', 'Act Interpretation', 'Legal Analysis'],
    },
    {
      'title': 'Contract Law Expert',
      'icon': '🤝',
      'color': Color(0xFF2E8B57),
      'requirement': 'Score 80%+ in Contract Law Quiz',
      'xp': 400,
      'earned': false,
      'skills': ['Essential Elements', 'Void Contracts', 'Breach & Remedies'],
    },
    {
      'title': 'Mock Court Champion',
      'icon': '🏆',
      'color': Color(0xFFD4A017),
      'requirement': 'Win 5 Mock Court sessions',
      'xp': 600,
      'earned': false,
      'skills': ['Oral Arguments', 'Written Submission', 'Case Strategy'],
    },
    {
      'title': 'Legal Drafter',
      'icon': '✍️',
      'color': Color(0xFF0288D1),
      'requirement': 'Complete 5 AI Drafting exercises',
      'xp': 400,
      'earned': false,
      'skills': ['Legal Notice', 'Affidavit', 'Petition Drafting'],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Certificates',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    const SizedBox(width: 48),
                  ]),
                  // Stats
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat('0', 'Earned', _gold),
                        _Stat('${_certificates.length}', 'Available',
                            Colors.white),
                        _Stat('0', 'XP from Certs', Colors.white70),
                      ]),
                ]),
              )),
        ),
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _gold.withValues(alpha: 0.3))),
              child: const Row(children: [
                Text('🏅', style: TextStyle(fontSize: 22)),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Complete quizzes and mock courts to earn certificates! Each certificate validates your legal skills.',
                        style: TextStyle(
                            color: Color(0xFF8B5E3C),
                            fontSize: 12,
                            height: 1.4))),
              ])),
          const SizedBox(height: 16),
          ..._certificates.map((cert) {
            final color = cert['color'] as Color;
            final earned = cert['earned'] as bool;
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: earned ? color : _border, width: earned ? 2 : 0.8),
                  boxShadow: [
                    BoxShadow(
                        color: _blue.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: Column(children: [
                // Certificate header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16))),
                  child: Row(children: [
                    Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: color.withValues(alpha: 0.3), width: 2)),
                        child: Center(
                            child: Text(cert['icon'],
                                style: const TextStyle(fontSize: 24)))),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(cert['title'],
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.bolt_rounded, color: _gold, size: 14),
                            Text(' +${cert['xp']} XP',
                                style: const TextStyle(
                                    color: _gold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ]),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: earned
                            ? color.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            earned
                                ? Icons.verified_rounded
                                : Icons.lock_rounded,
                            color: earned ? color : _textMuted,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(earned ? 'Earned' : 'Locked',
                            style: TextStyle(
                                color: earned ? color : _textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),

                // Skills & requirement
                Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.task_alt_rounded,
                                color: _textMuted, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(cert['requirement'],
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 12))),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: (cert['skills'] as List<String>)
                                  .map((s) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: Text(s,
                                          style: TextStyle(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600))))
                                  .toList()),
                          const SizedBox(height: 12),
                          // Action button
                          SizedBox(
                            width: double.infinity,
                            child: earned
                                ? ElevatedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _showCertificate(context, cert, color);
                                    },
                                    icon: const Icon(Icons.download_rounded,
                                        color: Colors.white, size: 16),
                                    label: const Text('View Certificate',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: color,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10)))
                                : OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _showHowToEarn(context, cert, color);
                                    },
                                    icon: Icon(Icons.info_outline_rounded,
                                        color: color, size: 16),
                                    label: Text('How to Earn',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: color),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10))),
                          ),
                        ])),
              ]),
            );
          }),
          const SizedBox(height: 40),
        ])),
      ]),
    );
  }

  void _showCertificate(
      BuildContext context, Map<String, dynamic> cert, Color color) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.8), color]),
                        borderRadius: BorderRadius.circular(14)),
                    child: Column(children: [
                      const Text('🏅', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      const Text('CERTIFICATE OF ACHIEVEMENT',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              letterSpacing: 2)),
                      const SizedBox(height: 4),
                      Text(cert['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('This certifies successful completion',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      Text('Libra Law Platform • 2025',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10)),
                    ])),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Clipboard.setData(const ClipboardData(
                        text: 'I earned a certificate on Libra Law!'));
                  },
                  icon: const Icon(Icons.share_rounded,
                      color: Colors.white, size: 16),
                  label: const Text('Share',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ]),
            ));
  }

  void _showHowToEarn(
      BuildContext context, Map<String, dynamic> cert, Color color) {
    showModalBottomSheet(
        context: context,
        backgroundColor: _bgCard,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('How to earn: ${cert['title']}',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 14),
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.2))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.task_alt_rounded, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(cert['requirement'],
                                style: const TextStyle(
                                    color: _textPri,
                                    fontSize: 13,
                                    height: 1.4))),
                      ])),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Got it!',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  )),
            ])));
  }

  Widget _Stat(String value, String label, Color color) => Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
      ]);
}
