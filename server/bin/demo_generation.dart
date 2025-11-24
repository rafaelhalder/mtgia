import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main() async {
  final url = Uri.parse('http://localhost:8080/ai/generate');
  
  // Gera um token de teste
  final jwt = JWT({'id': 'test-user-id'});
  final token = jwt.sign(SecretKey('your-super-secret-and-long-string-for-jwt'));

  print('Calling POST $url ...');
  
  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'prompt': 'A aggressive goblin deck with Krenko, Mob Boss as commander',
        'format': 'Commander'
      }),
    );

    print('Status Code: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Generated Deck:');
      final cards = data['generated_deck']['cards'] as List;
      print('Total Cards: ${cards.length}');
      print('First 5 cards:');
      for (var i = 0; i < 5 && i < cards.length; i++) {
        print(' - ${cards[i]['quantity']}x ${cards[i]['name']}');
      }
      print('Meta Context Used: ${data['meta_context_used']}');
    } else {
      print('Error: ${response.body}');
    }
  } catch (e) {
    print('Request failed: $e');
  }
}
