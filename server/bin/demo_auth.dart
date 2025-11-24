import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('🧪 Testando autenticação real...\n');

  // Teste 1: Registro
  print('1️⃣ Testando POST /auth/register');
  try {
    final registerResponse = await http.post(
      Uri.parse('http://localhost:8080/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': 'testuser_${DateTime.now().millisecondsSinceEpoch}',
        'email': 'test_${DateTime.now().millisecondsSinceEpoch}@example.com',
        'password': 'senha123456',
      }),
    );

    print('Status: ${registerResponse.statusCode}');
    print('Body: ${registerResponse.body}\n');

    if (registerResponse.statusCode == 201) {
      final data = jsonDecode(registerResponse.body);
      final token = data['token'];
      print('✅ Registro bem-sucedido!');
      print('Token: ${token.substring(0, 20)}...\n');

      // Teste 2: Login
      print('2️⃣ Testando POST /auth/login');
      final loginResponse = await http.post(
        Uri.parse('http://localhost:8080/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': data['user']['email'],
          'password': 'senha123456',
        }),
      );

      print('Status: ${loginResponse.statusCode}');
      print('Body: ${loginResponse.body}\n');

      if (loginResponse.statusCode == 200) {
        print('✅ Login bem-sucedido!');
      } else {
        print('❌ Login falhou');
      }
    } else {
      print('❌ Registro falhou');
    }
  } catch (e) {
    print('❌ Erro: $e');
  }
}
