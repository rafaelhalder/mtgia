String? normalizeScryfallImageUrl(String? url) {
  if (url == null) return null;
  var normalized = url.trim();
  if (normalized.isEmpty) return null;

  if (normalized.startsWith('ttps://')) {
    normalized = 'h$normalized';
  } else if (normalized.startsWith('//api.scryfall.com/')) {
    normalized = 'https:$normalized';
  } else if (normalized.startsWith('api.scryfall.com/')) {
    normalized = 'https://$normalized';
  } else if (normalized.startsWith('http://api.scryfall.com/')) {
    normalized = normalized.replaceFirst(
      'http://api.scryfall.com/',
      'https://api.scryfall.com/',
    );
  }

  final parsed = Uri.tryParse(normalized);
  final isScryfall =
      parsed != null && parsed.host.toLowerCase() == 'api.scryfall.com';
  if (!isScryfall) return normalized;

  try {
    final uri = Uri.parse(normalized);
    final qp = Map<String, String>.from(uri.queryParameters);

    if (qp['set'] != null) qp['set'] = qp['set']!.toLowerCase();

    final exact = qp['exact'];
    if (uri.path == '/cards/named' && exact != null && exact.contains('//')) {
      final left = exact.split('//').first.trim();
      if (left.isNotEmpty) qp['exact'] = left;
    }

    return uri.replace(queryParameters: qp).toString().replaceAll('+', '%20');
  } catch (_) {
    return normalized.replaceAllMapped(
      RegExp(r'([?&]set=)([^&]+)', caseSensitive: false),
      (m) => '${m.group(1)}${(m.group(2) ?? '').toLowerCase()}',
    );
  }
}
