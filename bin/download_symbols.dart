import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final symbolsUrl = Uri.parse('https://api.scryfall.com/symbology');
  final outputDir = Directory('../app/assets/symbols');

  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
    print('Created directory: ${outputDir.path}');
  }

  print('Fetching symbols from Scryfall...');
  try {
    final response = await http.get(symbolsUrl);
    if (response.statusCode != 200) {
      print('Error fetching symbols: ${response.statusCode}');
      return;
    }

    final data = jsonDecode(response.body);
    final List<dynamic> symbols = data['data'];

    print('Found ${symbols.length} symbols. Downloading...');

    for (final symbol in symbols) {
      final String symbolText = symbol['symbol']; // e.g. {T}
      final String? svgUri = symbol['svg_uri'];

      if (svgUri == null) continue;

      // Sanitize filename: {T} -> T.svg, {2/W} -> 2-W.svg
      String filename = symbolText.replaceAll('{', '').replaceAll('}', '').replaceAll('/', '-');
      
      // Handle specific cases if needed, but replaceAll should work for most
      // e.g. {U/P} -> U-P.svg
      
      final file = File('${outputDir.path}/$filename.svg');
      
      // Download SVG
      final svgResponse = await http.get(Uri.parse(svgUri));
      if (svgResponse.statusCode == 200) {
        await file.writeAsBytes(svgResponse.bodyBytes);
        print('Downloaded: $filename.svg');
      } else {
        print('Failed to download: $filename.svg');
      }
      
      // Be nice to the API
      await Future.delayed(const Duration(milliseconds: 50));
    }

    print('All symbols downloaded successfully!');

  } catch (e) {
    print('Error: $e');
  }
}
