// Quick debug: GET /community/decks and show full error body
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final r = await http.get(Uri.parse('http://localhost:8080/community/decks?page=1&limit=1'));
  print('Status: ${r.statusCode}');
  print('Body: ${r.body}');
  exit(0);
}
