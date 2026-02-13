// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Teste de integração completo para os endpoints do Épico 3 (Trades)
///
/// Uso: dart run bin/qa/integration_trades.dart
void main() async {
  const baseUrl = 'http://localhost:8080';
  const email = 'rafaelhalder@gmail.com';
  const password = '12345678';

  var passed = 0;
  var failed = 0;

  void ok(String name) {
    passed++;
    print('  ✅ $name');
  }

  void fail(String name, String reason) {
    failed++;
    print('  ❌ $name → $reason');
  }

  // ─── 1. LOGIN ───────────────────────────────────────────────
  print('\n🔐 1. Login...');
  late String token;
  late String userId;
  try {
    final loginRes = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (loginRes.statusCode != 200) {
      print('❌ FATAL: Login falhou (${loginRes.statusCode}): ${loginRes.body}');
      exit(1);
    }
    final loginBody = jsonDecode(loginRes.body);
    token = loginBody['token'] as String;
    userId = loginBody['user']?['id'] as String? ?? '';
    ok('POST /auth/login → 200 (token obtido, userId=$userId)');
  } catch (e) {
    print('❌ FATAL: Não foi possível conectar ao servidor: $e');
    print('   Certifique-se de que dart_frog dev está rodando.');
    exit(1);
  }

  Map<String, String> authHeaders() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ─── 2. Preparar: buscar carta e criar binder item ──────────
  print('\n🃏 2. Preparar carta + binder item...');
  late String testCardId;
  late String binderItemId;
  try {
    final cardsRes = await http.get(
      Uri.parse('$baseUrl/cards?name=sol%20ring&limit=1'),
      headers: authHeaders(),
    );
    if (cardsRes.statusCode != 200) {
      print('❌ FATAL: Busca de cartas falhou');
      exit(1);
    }
    final cardsBody = jsonDecode(cardsRes.body);
    final cards = cardsBody['data'] as List;
    if (cards.isEmpty) {
      print('❌ FATAL: Nenhuma carta encontrada para testes');
      exit(1);
    }
    testCardId = cards[0]['id'] as String;
    ok('GET /cards?name=sol+ring → carta encontrada ($testCardId)');

    // Criar item no binder marcado para troca
    final binderRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: authHeaders(),
      body: jsonEncode({
        'card_id': testCardId,
        'quantity': 2,
        'condition': 'NM',
        'for_trade': true,
        'for_sale': true,
        'price': 5.50,
      }),
    );
    if (binderRes.statusCode == 201 || binderRes.statusCode == 200) {
      final binderBody = jsonDecode(binderRes.body);
      binderItemId = binderBody['id'] as String;
      ok('POST /binder → binder item criado ($binderItemId)');
    } else {
      print('❌ FATAL: Não foi possível criar binder item: ${binderRes.body}');
      exit(1);
    }
  } catch (e) {
    print('❌ FATAL: Preparação falhou: $e');
    exit(1);
  }

  // ─── 3. POST /trades — sem auth ────────────────────────────
  print('\n🔒 3. Testes de segurança...');
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/trades'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      ok('POST /trades sem auth → ${res.statusCode}');
    } else {
      fail('POST /trades sem auth', 'esperado 401/403, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST /trades sem auth', '$e');
  }

  // ─── 4. POST /trades — trade consigo mesmo ─────────────────
  print('\n🚫 4. Validações de criação...');
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/trades'),
      headers: authHeaders(),
      body: jsonEncode({
        'receiver_id': userId,
        'type': 'trade',
        'my_items': [
          {'binder_item_id': binderItemId, 'quantity': 1}
        ],
        'requested_items': [
          {'binder_item_id': binderItemId, 'quantity': 1}
        ],
      }),
    );
    if (res.statusCode == 400) {
      ok('POST /trades consigo mesmo → 400');
    } else {
      fail('POST /trades consigo mesmo', 'esperado 400, recebeu ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('POST /trades consigo mesmo', '$e');
  }

  // ─── 5. POST /trades — sem items ───────────────────────────
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/trades'),
      headers: authHeaders(),
      body: jsonEncode({
        'receiver_id': 'some-fake-uuid',
        'type': 'trade',
        'my_items': [],
        'requested_items': [],
      }),
    );
    if (res.statusCode == 400) {
      ok('POST /trades sem items → 400');
    } else {
      fail('POST /trades sem items', 'esperado 400, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST /trades sem items', '$e');
  }

  // ─── 6. POST /trades — receiver inexistente ─────────────────
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/trades'),
      headers: authHeaders(),
      body: jsonEncode({
        'receiver_id': '00000000-0000-0000-0000-000000000000',
        'type': 'sale',
        'my_items': [
          {'binder_item_id': binderItemId, 'quantity': 1}
        ],
        'requested_items': [],
      }),
    );
    if (res.statusCode == 404) {
      ok('POST /trades receiver inexistente → 404');
    } else {
      fail('POST /trades receiver inexistente', 'esperado 404, recebeu ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('POST /trades receiver inexistente', '$e');
  }

  // ─── 7. GET /trades — lista vazia ou existente ──────────────
  print('\n📋 5. GET /trades (listagem)...');
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/trades?page=1&limit=20'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] as List;
      ok('GET /trades → ${res.statusCode} (${data.length} trades, total=${body['total']})');
    } else {
      fail('GET /trades', '${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /trades', '$e');
  }

  // ─── 8. GET /trades com filtro role=sender ──────────────────
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/trades?role=sender'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      ok('GET /trades?role=sender → 200');
    } else {
      fail('GET /trades?role=sender', '${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /trades?role=sender', '$e');
  }

  // ─── 9. GET /trades com filtro status=pending ───────────────
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/trades?status=pending'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      ok('GET /trades?status=pending → 200');
    } else {
      fail('GET /trades?status=pending', '${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /trades?status=pending', '$e');
  }

  // ─── 10. GET /trades/:id — fake id ─────────────────────────
  print('\n🔍 6. GET /trades/:id (detalhe)...');
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000'),
      headers: authHeaders(),
    );
    if (res.statusCode == 404) {
      ok('GET /trades/:fakeId → 404');
    } else {
      fail('GET /trades/:fakeId', 'esperado 404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('GET /trades/:fakeId', '$e');
  }

  // ─── 11. PUT /trades/:id/respond — trade inexistente ────────
  print('\n✋ 7. PUT /trades/:id/respond...');
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/respond'),
      headers: authHeaders(),
      body: jsonEncode({'action': 'accept'}),
    );
    if (res.statusCode == 404) {
      ok('PUT /trades/:fakeId/respond → 404');
    } else {
      fail('PUT /trades/:fakeId/respond', 'esperado 404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('PUT /trades/:fakeId/respond', '$e');
  }

  // ─── 12. PUT /trades/:id/respond — action inválido ──────────
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/respond'),
      headers: authHeaders(),
      body: jsonEncode({'action': 'invalid'}),
    );
    if (res.statusCode == 400) {
      ok('PUT respond action inválido → 400');
    } else {
      fail('PUT respond action inválido', 'esperado 400, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('PUT respond action inválido', '$e');
  }

  // ─── 13. PUT /trades/:id/status — trade inexistente ─────────
  print('\n📦 8. PUT /trades/:id/status...');
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/status'),
      headers: authHeaders(),
      body: jsonEncode({'status': 'shipped'}),
    );
    if (res.statusCode == 404) {
      ok('PUT /trades/:fakeId/status → 404');
    } else {
      fail('PUT /trades/:fakeId/status', 'esperado 404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('PUT /trades/:fakeId/status', '$e');
  }

  // ─── 14. PUT /trades/:id/status — status inválido ───────────
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/status'),
      headers: authHeaders(),
      body: jsonEncode({'status': 'blah'}),
    );
    if (res.statusCode == 400) {
      ok('PUT status inválido → 400');
    } else {
      fail('PUT status inválido', 'esperado 400, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('PUT status inválido', '$e');
  }

  // ─── 15. GET /trades/:id/messages — trade inexistente ───────
  print('\n💬 9. GET/POST /trades/:id/messages...');
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/messages'),
      headers: authHeaders(),
    );
    if (res.statusCode == 404) {
      ok('GET /trades/:fakeId/messages → 404');
    } else {
      fail('GET /trades/:fakeId/messages', 'esperado 404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('GET /trades/:fakeId/messages', '$e');
  }

  // ─── 16. POST /trades/:id/messages — sem conteúdo ───────────
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/trades/00000000-0000-0000-0000-000000000000/messages'),
      headers: authHeaders(),
      body: jsonEncode({}),
    );
    // pode ser 400 (sem message) ou 404 (trade não encontrado)
    if (res.statusCode == 400 || res.statusCode == 404) {
      ok('POST /trades/:fakeId/messages sem conteúdo → ${res.statusCode}');
    } else {
      fail('POST /trades/:fakeId/messages sem conteúdo', 'esperado 400/404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST /trades/:fakeId/messages sem conteúdo', '$e');
  }

  // ─── 17. Limpeza: remover binder item de teste ──────────────
  print('\n🧹 10. Limpeza...');
  try {
    final res = await http.delete(
      Uri.parse('$baseUrl/binder/$binderItemId'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200 || res.statusCode == 204) {
      ok('DELETE /binder/$binderItemId → ${res.statusCode} (limpeza)');
    } else {
      fail('Limpeza binder', '${res.statusCode}');
    }
  } catch (e) {
    fail('Limpeza binder', '$e');
  }

  // ─── Resultado ──────────────────────────────────────────────
  print('\n══════════════════════════════════════════════');
  print('   Resultado: $passed/${'$passed + $failed → ${passed + failed}'} testes');
  print('   ✅ Passaram: $passed');
  if (failed > 0) {
    print('   ❌ Falharam: $failed');
  }
  print('══════════════════════════════════════════════\n');

  exit(failed > 0 ? 1 : 0);
}
