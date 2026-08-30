import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'news_webview_screen.dart';

const _bg = Color(0xFFFFF0F5);
const _bgCard = Color(0xFFFFFFFF);
const _pink = Color(0xFFE91E8C);
const _textMuted = Color(0xFF6B6B8A);

class LawBooksScreen extends StatelessWidget {
  const LawBooksScreen({super.key});

  static const List<Map<String, dynamic>> _books = [
    {
      'title': 'Constitution of India - Full Text',
      'author': 'Legislative Department, India',
      'description':
          'Complete text of the Constitution of India with all amendments. Fundamental rights, duties, directive principles.',
      'emoji': '🏛️',
      'color': Color(0xFF7C3AED),
      'url': 'https://legislative.gov.in/constitution-of-india/',
      'pages': '395 Articles'
    },
    {
      'title': 'Indian Penal Code (IPC) 1860',
      'author': 'India Code',
      'description':
          'Main criminal code covering all major offenses, punishments and criminal procedures.',
      'emoji': '⚖️',
      'color': Color(0xFFDC2626),
      'url':
          'https://www.indiacode.nic.in/bitstream/123456789/2263/1/aiphenalcode.pdf',
      'pages': '511 Sections'
    },
    {
      'title': 'LiveLaw - Latest Judgments',
      'author': 'LiveLaw Media',
      'description':
          'Latest Supreme Court and High Court judgments, legal news and analysis.',
      'emoji': '📰',
      'color': Color(0xFF7C3AED),
      'url': 'https://www.livelaw.in/supreme-court',
      'pages': 'Daily Updates'
    },
    {
      'title': 'Indian Kanoon - Case Search',
      'author': 'Indian Kanoon',
      'description':
          'Search millions of Indian court judgments from Supreme Court and High Courts.',
      'emoji': '🔍',
      'color': Color(0xFF0EA5E9),
      'url': 'https://indiankanoon.org',
      'pages': 'All Cases'
    },
    {
      'title': 'SCC Online - Supreme Court',
      'author': 'SCC Online',
      'description':
          'Comprehensive database of Supreme Court cases and legal research.',
      'emoji': '📚',
      'color': Color(0xFF059669),
      'url': 'https://www.scconline.com/blog/post/category/landmark-judgments/',
      'pages': 'Landmark Cases'
    },
    {
      'title': 'Bar & Bench - Legal News',
      'author': 'Bar & Bench',
      'description':
          'Breaking legal news, court updates, and in-depth analysis.',
      'emoji': '⚖️',
      'color': Color(0xFF0EA5E9),
      'url': 'https://www.barandbench.com',
      'pages': 'Daily News'
    },
    {
      'title': 'Hindu Marriage Act 1955',
      'author': 'India Code',
      'description':
          'Governs marriage, divorce, maintenance and custody for Hindus, Buddhists, Jains and Sikhs.',
      'emoji': '👫',
      'color': Color(0xFFE91E8C),
      'url':
          'https://www.indiacode.nic.in/bitstream/123456789/2188/1/A1955-25.pdf',
      'pages': '30 Sections'
    },
    {
      'title': 'RTI Act 2005 - Right to Information',
      'author': 'India Code',
      'description':
          'Provides citizens right to access government information.',
      'emoji': '📋',
      'color': Color(0xFFD97706),
      'url':
          'https://www.indiacode.nic.in/bitstream/123456789/1872/3/200522.pdf',
      'pages': '31 Sections'
    },
    {
      'title': 'Protection of Women from DV Act 2005',
      'author': 'India Code',
      'description': 'Provides protection to women from domestic violence.',
      'emoji': '🛡️',
      'color': Color(0xFFE91E8C),
      'url':
          'https://www.indiacode.nic.in/bitstream/123456789/15436/1/protection_of_women_from_domestic.pdf',
      'pages': '37 Sections'
    },
    {
      'title': 'IT Act 2000 - Cyber Law',
      'author': 'India Code',
      'description':
          'Governs cyber crimes, digital signatures and electronic transactions in India.',
      'emoji': '💻',
      'color': Color(0xFF059669),
      'url':
          'https://www.indiacode.nic.in/bitstream/123456789/1999/3/200021.pdf',
      'pages': '90 Sections'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _pink,
        title: const Text('Law Library 📚',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _books.length,
        itemBuilder: (_, i) {
          final b = _books[i];
          final color = b['color'] as Color;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 200 + (i * 60)),
            builder: (_, v, child) => Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.translate(
                    offset: Offset(0, 20 * (1 - v)), child: child)),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NewsWebViewScreen(
                            url: b['url'],
                            title: b['title'],
                            source: 'Law Library')));
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                          color: _pink.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(children: [
                  Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text(b['emoji'],
                              style: const TextStyle(fontSize: 28)))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(b['title'],
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 14),
                            maxLines: 2),
                        const SizedBox(height: 4),
                        Text(b['description'],
                            style: const TextStyle(
                                color: _textMuted, fontSize: 11, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(b['pages'],
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          const Text('Tap to read →',
                              style:
                                  TextStyle(color: _textMuted, fontSize: 10)),
                        ]),
                      ])),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
