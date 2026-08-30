import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

class NewsService {
  static final _dio = Dio();

  // ✅ RSS Feed URL — LiveLaw is the news source for Live Court News.
  // (livelaw.in/rss returns a 404; the site's real feed is at feeds.xml,
  // discoverable from the <atom:link rel="self"> tag on that very feed.)
  static const Map<String, String> _feeds = {
    'LiveLaw': 'https://www.livelaw.in/feeds.xml',
  };

  static Future<List<Map<String, dynamic>>> fetchAllNews() async {
    final List<Map<String, dynamic>> allNews = [];

    for (final entry in _feeds.entries) {
      try {
        final news = await _fetchFeed(entry.key, entry.value);
        allNews.addAll(news);
      } catch (e) {
        print('Error fetching ${entry.key}: $e');
      }
    }

    // Sort by date - newest first
    allNews.sort((a, b) {
      final dateA = DateTime.tryParse(a['pubDate'] ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['pubDate'] ?? '') ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return allNews;
  }

  static Future<List<Map<String, dynamic>>> _fetchFeed(
      String source, String url) async {
    final response = await _dio.get(url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/rss+xml, application/xml, text/xml',
          },
          receiveTimeout: const Duration(seconds: 10),
        ));

    final document = XmlDocument.parse(response.data.toString());
    final items = document.findAllElements('item');

    return items.take(10).map((item) {
      final title = item.findElements('title').firstOrNull?.innerText ?? '';
      final description =
          item.findElements('description').firstOrNull?.innerText ?? '';
      final link = item.findElements('link').firstOrNull?.innerText ?? '';
      final pubDate = item.findElements('pubDate').firstOrNull?.innerText ?? '';
      final category =
          item.findElements('category').firstOrNull?.innerText ?? '';

      // Clean HTML from description
      final cleanDesc = description
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .trim();

      return {
        'title': title.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
        'description': cleanDesc.length > 300
            ? '${cleanDesc.substring(0, 300)}...'
            : cleanDesc,
        'link': link,
        'pubDate': _parseDate(pubDate),
        'source': source,
        'category': _detectCategory(title + category),
        'color': _getSourceColor(source),
        'emoji': _getCategoryEmoji(_detectCategory(title + category)),
        'timeAgo': _getTimeAgo(pubDate),
      };
    }).toList();
  }

  static String _detectCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('supreme court') || lower.contains('sc '))
      return 'Supreme Court';
    if (lower.contains('high court') || lower.contains('hc '))
      return 'High Court';
    if (lower.contains('criminal') ||
        lower.contains('ipc') ||
        lower.contains('bns') ||
        lower.contains('bail') ||
        lower.contains('murder') ||
        lower.contains('rape') ||
        lower.contains('pocso')) return 'Criminal';
    if (lower.contains('constitutional') ||
        lower.contains('article') ||
        lower.contains('fundamental')) return 'Constitutional';
    if (lower.contains('family') ||
        lower.contains('divorce') ||
        lower.contains('custody') ||
        lower.contains('marriage')) return 'Family';
    if (lower.contains('property') ||
        lower.contains('land') ||
        lower.contains('rent') ||
        lower.contains('evict')) return 'Property';
    if (lower.contains('cyber') ||
        lower.contains('digital') ||
        lower.contains('data') ||
        lower.contains('internet')) return 'Cyber';
    return 'General';
  }

  static String _getSourceColor(String source) {
    switch (source) {
      case 'LiveLaw':
        return '0xFF7C3AED';
      case 'Bar & Bench':
        return '0xFF0EA5E9';
      case 'LawBeat':
        return '0xFF059669';
      default:
        return '0xFFD97706';
    }
  }

  static String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Supreme Court':
        return '🏛️';
      case 'High Court':
        return '⚖️';
      case 'Criminal':
        return '🔍';
      case 'Constitutional':
        return '📜';
      case 'Family':
        return '👨‍👩‍👧';
      case 'Property':
        return '🏠';
      case 'Cyber':
        return '💻';
      default:
        return '📰';
    }
  }

  static String _parseDate(String dateStr) {
    try {
      // RFC 2822 format: "Mon, 02 Jan 2006 15:04:05 +0000"
      return DateTime.parse(dateStr).toIso8601String();
    } catch (_) {
      return DateTime.now().toIso8601String();
    }
  }

  static String _getTimeAgo(String dateStr) {
    try {
      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        // Try RFC 2822
        date = DateTime.now();
      }
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Recently';
    }
  }
}
