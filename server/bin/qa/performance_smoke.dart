// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Smoke test manual de performance para endpoints críticos
/// 
/// Mede tempo de resposta para:
/// - GET /decks/:id (detalhes do deck)
/// - POST /decks/:id/cards (adicionar carta)
/// - GET /cards (busca de cartas)
/// 
/// Uso: dart run bin/qa/performance_smoke.dart
void main() async {
  final baseUrl = Platform.environment['BASE_URL'] ?? 'http://localhost:8080';
  
  print('🔥 Smoke Test de Performance');
  print('Base URL: $baseUrl');
  print('');
  
  // Primeiro, fazer login para obter token
  String? token;
  String? testDeckId;
  
  try {
    print('1️⃣ Autenticação...');
    final loginResult = await _measureTime('POST /auth/login', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'test@test.com',
          'password': 'test123',
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        // Tenta criar usuário de teste
        print('   → Criando usuário de teste...');
        final registerResponse = await http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'test@test.com',
            'username': 'performance_test',
            'password': 'test123',
          }),
        );
        
        if (registerResponse.statusCode == 201) {
          return jsonDecode(registerResponse.body);
        }
        throw Exception('Falha ao criar usuário de teste');
      }
      throw Exception('Login falhou: ${response.statusCode}');
    });
    
    token = loginResult['token'] as String?;
    // userId disponível em loginResult['user']?['id'] se necessário
    
    if (token == null) {
      print('❌ Não foi possível obter token');
      exit(1);
    }
    
    print('   ✅ Token obtido\n');
    
    // 2. Busca de cartas
    print('2️⃣ Busca de cartas...');
    await _measureTime('GET /cards?name=Sol', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/cards?name=Sol&limit=20'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response;
    });
    
    await _measureTime('GET /cards?name=Lightning', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/cards?name=Lightning&limit=50'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response;
    });
    
    // 3. Criar deck de teste
    print('\n3️⃣ Criação de deck...');
    final createResult = await _measureTime('POST /decks', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/decks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': 'Performance Test Deck ${DateTime.now().millisecondsSinceEpoch}',
          'format': 'commander',
          'description': 'Deck criado para teste de performance',
        }),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      throw Exception('Falha ao criar deck: ${response.statusCode}');
    });
    
    testDeckId = createResult['id'] as String?;
    print('   ✅ Deck criado: $testDeckId\n');
    
    // 4. GET deck details
    print('4️⃣ Detalhes do deck...');
    await _measureTime('GET /decks/$testDeckId (vazio)', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response;
    });
    
    // 5. Adicionar cartas ao deck
    print('\n5️⃣ Adicionar cartas...');
    
    // Primeiro buscar uma carta para ter o ID
    final searchResponse = await http.get(
      Uri.parse('$baseUrl/cards?name=Forest&limit=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (searchResponse.statusCode == 200) {
      final searchData = jsonDecode(searchResponse.body);
      final cards = searchData['data'] as List?;
      
      if (cards != null && cards.isNotEmpty) {
        final cardId = cards[0]['id'] as String;
        
        // Adicionar 5 cartas sequencialmente
        for (var i = 0; i < 5; i++) {
          await _measureTime('POST /decks/$testDeckId/cards (carta ${i+1})', () async {
            final response = await http.post(
              Uri.parse('$baseUrl/decks/$testDeckId/cards'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'card_id': cardId,
                'quantity': 1,
              }),
            );
            return response;
          });
        }
      }
    }
    
    // 6. GET deck com cartas
    print('\n6️⃣ Detalhes do deck com cartas...');
    await _measureTime('GET /decks/$testDeckId (com cartas)', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response;
    });
    
    // 7. Listar decks
    print('\n7️⃣ Lista de decks...');
    await _measureTime('GET /decks', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/decks'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response;
    });
    
    // 8. Health check
    print('\n8️⃣ Health check...');
    await _measureTime('GET /health', () async {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response;
    });
    
    print('\n' + '=' * 50);
    print('✅ Smoke test concluído!');
    print('=' * 50);
    
  } catch (e) {
    print('❌ Erro no teste: $e');
    exit(1);
  } finally {
    // Limpar deck de teste
    if (testDeckId != null && token != null) {
      print('\n🧹 Limpando deck de teste...');
      try {
        await http.delete(
          Uri.parse('$baseUrl/decks/$testDeckId'),
          headers: {'Authorization': 'Bearer $token'},
        );
        print('   ✅ Deck removido');
      } catch (_) {
        print('   ⚠️ Não foi possível remover o deck');
      }
    }
  }
}

/// Mede o tempo de execução de uma operação e imprime o resultado
Future<T> _measureTime<T>(String operationName, Future<T> Function() operation) async {
  final stopwatch = Stopwatch()..start();
  
  try {
    final result = await operation();
    stopwatch.stop();
    
    final ms = stopwatch.elapsedMilliseconds;
    final status = ms < 500 ? '🟢' : (ms < 1000 ? '🟡' : '🔴');
    
    print('   $status $operationName: ${ms}ms');
    
    return result;
  } catch (e) {
    stopwatch.stop();
    print('   🔴 $operationName: FALHOU (${stopwatch.elapsedMilliseconds}ms) - $e');
    rethrow;
  }
}
