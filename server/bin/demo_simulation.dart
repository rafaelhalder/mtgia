import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main() async {
  // ID do deck de teste
  final deckId = 'd5e25e80-5c22-42b2-8eb8-59624b1f149a'; 
  final url = Uri.parse('http://localhost:8080/decks/$deckId/simulate');
  
  // Gera token
  final jwt = JWT({'id': 'test-user-id'});
  final token = jwt.sign(SecretKey('your-super-secret-and-long-string-for-jwt'));

  print('Calling GET $url ...');
  
  try {
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Status Code: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Simulation Results (1000 iterations):');
      print('-------------------------------------');
      print('Opening Hand Land Distribution:');
      final dist = data['opening_hand']['land_distribution'] as Map;
      dist.forEach((k, v) => print('  $k: $v'));
      
      print('\nVerdict: ${data['opening_hand']['analysis']}');
      
      print('\nProbability to Play on Curve:');
      final curve = data['on_curve_probability'] as Map;
      curve.forEach((k, v) => print('  $k: $v'));
      
    } else {
      print('Error: ${response.body}');
    }
  } catch (e) {
    print('Request failed: $e');
  }
}
