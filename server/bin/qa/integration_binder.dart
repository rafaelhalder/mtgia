// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Teste de integração completo para TODOS os endpoints do Épico 2 (Binder)
/// e rotas refatoradas (stats, following).
///
/// Uso: dart run bin/qa/integration_binder.dart
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
    ok('POST /auth/login → 200 (token obtido)');
  } catch (e) {
    print('❌ FATAL: Não foi possível conectar ao servidor: $e');
    print('   Certifique-se de que dart_frog dev está rodando.');
    exit(1);
  }

  Map<String, String> authHeaders() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ─── 2. Buscar uma carta real para usar nos testes ──────────
  print('\n🃏 2. Buscar carta para testes...');
  late String testCardId;
  late String testCardName;
  try {
    final cardsRes = await http.get(
      Uri.parse('$baseUrl/cards?name=lightning&limit=1'),
    );
    if (cardsRes.statusCode != 200) {
      fail('GET /cards?name=lightning', 'Status ${cardsRes.statusCode}');
      print('   Tentando buscar qualquer carta...');
      final anyRes = await http.get(Uri.parse('$baseUrl/cards?limit=1'));
      if (anyRes.statusCode != 200) {
        print('❌ FATAL: Sem cartas no banco. Rode sync_cards primeiro.');
        exit(1);
      }
      final anyBody = jsonDecode(anyRes.body);
      final card = (anyBody['data'] as List).first;
      testCardId = card['id'];
      testCardName = card['name'];
    } else {
      final cardsBody = jsonDecode(cardsRes.body);
      final cards = cardsBody['data'] as List;
      if (cards.isEmpty) {
        print('❌ FATAL: Nenhuma carta encontrada.');
        exit(1);
      }
      testCardId = cards[0]['id'];
      testCardName = cards[0]['name'];
      ok('GET /cards?name=lightning → encontrou "$testCardName" ($testCardId)');
    }
  } catch (e) {
    fail('GET /cards', '$e');
    exit(1);
  }

  // ─── 3. POST /binder (adicionar carta) ─────────────────────
  print('\n📦 3. POST /binder (adicionar carta ao binder)...');
  late String binderItemId;
  try {
    final addRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: authHeaders(),
      body: jsonEncode({
        'card_id': testCardId,
        'quantity': 2,
        'condition': 'NM',
        'is_foil': false,
        'for_trade': true,
        'for_sale': false,
        'notes': 'Teste automatizado',
      }),
    );

    if (addRes.statusCode == 201 || addRes.statusCode == 200) {
      final body = jsonDecode(addRes.body);
      binderItemId = body['id']?.toString() ?? '';
      ok('POST /binder → ${addRes.statusCode} (id: $binderItemId)');
    } else if (addRes.statusCode == 409) {
      // Item já existe (teste anterior não limpou) — pegar o id existente
      final body = jsonDecode(addRes.body);
      binderItemId = body['existing_id']?.toString() ?? '';
      ok('POST /binder → 409 (já existe, id: $binderItemId) — OK para retest');
    } else {
      fail('POST /binder', 'Status ${addRes.statusCode}: ${addRes.body}');
      binderItemId = '';
    }
  } catch (e) {
    fail('POST /binder', '$e');
    binderItemId = '';
  }

  // ─── 4. GET /binder (listar) ───────────────────────────────
  print('\n📋 4. GET /binder (listar meu binder)...');
  try {
    final listRes = await http.get(
      Uri.parse('$baseUrl/binder?page=1&limit=5'),
      headers: authHeaders(),
    );
    if (listRes.statusCode == 200) {
      final body = jsonDecode(listRes.body);
      final items = body['data'] as List;
      final total = body['total'];
      ok('GET /binder → 200 (${items.length} itens retornados, total: $total)');

      // Validar estrutura
      if (items.isNotEmpty) {
        final first = items[0] as Map<String, dynamic>;
        final hasCard = first.containsKey('card') && first['card'] is Map;
        final hasQty = first.containsKey('quantity');
        final hasCond = first.containsKey('condition');
        if (hasCard && hasQty && hasCond) {
          ok('  Estrutura do item: card ✓, quantity ✓, condition ✓');
        } else {
          fail('  Estrutura do item', 'Campos faltando: card=$hasCard qty=$hasQty cond=$hasCond');
        }
      }
    } else {
      fail('GET /binder', 'Status ${listRes.statusCode}: ${listRes.body}');
    }
  } catch (e) {
    fail('GET /binder', '$e');
  }

  // ─── 5. GET /binder/stats ──────────────────────────────────
  print('\n📊 5. GET /binder/stats (estatísticas)...');
  try {
    final statsRes = await http.get(
      Uri.parse('$baseUrl/binder/stats'),
      headers: authHeaders(),
    );
    if (statsRes.statusCode == 200) {
      final body = jsonDecode(statsRes.body);
      final hasTotal = body.containsKey('total_items');
      final hasUnique = body.containsKey('unique_cards');
      final hasTrade = body.containsKey('for_trade_count');
      final hasSale = body.containsKey('for_sale_count');
      final hasValue = body.containsKey('estimated_value');
      if (hasTotal && hasUnique && hasTrade && hasSale && hasValue) {
        ok('GET /binder/stats → 200 (total: ${body['total_items']}, unique: ${body['unique_cards']}, trade: ${body['for_trade_count']}, value: ${body['estimated_value']})');
      } else {
        fail('GET /binder/stats', 'Campos faltando no response');
      }
    } else {
      fail('GET /binder/stats', 'Status ${statsRes.statusCode}: ${statsRes.body}');
    }
  } catch (e) {
    fail('GET /binder/stats', '$e');
  }

  // ─── 6. PUT /binder/:id (atualizar) ────────────────────────
  print('\n✏️ 6. PUT /binder/:id (atualizar item)...');
  if (binderItemId.isNotEmpty) {
    try {
      final updateRes = await http.put(
        Uri.parse('$baseUrl/binder/$binderItemId'),
        headers: authHeaders(),
        body: jsonEncode({
          'quantity': 4,
          'condition': 'LP',
          'for_sale': true,
          'price': 2.50,
          'notes': 'Atualizado pelo teste',
        }),
      );
      if (updateRes.statusCode == 200) {
        ok('PUT /binder/$binderItemId → 200');
      } else {
        fail('PUT /binder/$binderItemId', 'Status ${updateRes.statusCode}: ${updateRes.body}');
      }
    } catch (e) {
      fail('PUT /binder/:id', '$e');
    }
  } else {
    fail('PUT /binder/:id', 'Sem binderItemId — POST anterior falhou');
  }

  // ─── 7. GET /binder (filtros) ──────────────────────────────
  print('\n🔍 7. GET /binder com filtros...');
  try {
    final filtRes = await http.get(
      Uri.parse('$baseUrl/binder?for_sale=true&condition=LP'),
      headers: authHeaders(),
    );
    if (filtRes.statusCode == 200) {
      final body = jsonDecode(filtRes.body);
      ok('GET /binder?for_sale=true&condition=LP → 200 (${(body['data'] as List).length} itens)');
    } else {
      fail('GET /binder filtrado', 'Status ${filtRes.statusCode}');
    }
  } catch (e) {
    fail('GET /binder filtrado', '$e');
  }

  // ─── 8. GET /community/marketplace ─────────────────────────
  print('\n🏪 8. GET /community/marketplace...');
  try {
    final mkRes = await http.get(
      Uri.parse('$baseUrl/community/marketplace?page=1&limit=5'),
    );
    if (mkRes.statusCode == 200) {
      final body = jsonDecode(mkRes.body);
      final items = body['data'] as List;
      ok('GET /community/marketplace → 200 (${items.length} itens, total: ${body['total']})');
    } else {
      fail('GET /community/marketplace', 'Status ${mkRes.statusCode}: ${mkRes.body}');
    }
  } catch (e) {
    fail('GET /community/marketplace', '$e');
  }

  // ─── 9. GET /community/decks/following ─────────────────────
  print('\n👥 9. GET /community/decks/following (rota refatorada)...');
  try {
    final followRes = await http.get(
      Uri.parse('$baseUrl/community/decks/following?page=1&limit=5'),
      headers: authHeaders(),
    );
    if (followRes.statusCode == 200) {
      final body = jsonDecode(followRes.body);
      ok('GET /community/decks/following → 200 (${(body['data'] as List).length} decks)');
    } else {
      fail('GET /community/decks/following', 'Status ${followRes.statusCode}: ${followRes.body}');
    }
  } catch (e) {
    fail('GET /community/decks/following', '$e');
  }

  // ─── 10. GET /community/decks (listar públicos) ────────────
  print('\n🌐 10. GET /community/decks (decks públicos)...');
  String? publicDeckId;
  try {
    final pubRes = await http.get(
      Uri.parse('$baseUrl/community/decks?page=1&limit=1'),
    );
    if (pubRes.statusCode == 200) {
      final body = jsonDecode(pubRes.body);
      final decks = body['data'] as List;
      ok('GET /community/decks → 200 (${decks.length} decks, total: ${body['total']})');
      if (decks.isNotEmpty) {
        publicDeckId = decks[0]['id']?.toString();
      }
    } else {
      fail('GET /community/decks', 'Status ${pubRes.statusCode}');
    }
  } catch (e) {
    fail('GET /community/decks', '$e');
  }

  // ─── 11. GET /community/decks/:id ──────────────────────────
  print('\n📖 11. GET /community/decks/:id (deck público individual)...');
  if (publicDeckId != null) {
    try {
      final deckRes = await http.get(
        Uri.parse('$baseUrl/community/decks/$publicDeckId'),
      );
      if (deckRes.statusCode == 200) {
        final body = jsonDecode(deckRes.body);
        ok('GET /community/decks/$publicDeckId → 200 (deck: ${body['name']})');
      } else {
        fail('GET /community/decks/:id', 'Status ${deckRes.statusCode}: ${deckRes.body}');
      }
    } catch (e) {
      fail('GET /community/decks/:id', '$e');
    }
  } else {
    print('  ⏭️ Pulado — nenhum deck público encontrado');
  }

  // ─── 12. DELETE /binder/:id (limpar) ───────────────────────
  print('\n🗑️ 12. DELETE /binder/:id (remover item de teste)...');
  if (binderItemId.isNotEmpty) {
    try {
      final delRes = await http.delete(
        Uri.parse('$baseUrl/binder/$binderItemId'),
        headers: authHeaders(),
      );
      if (delRes.statusCode == 204 || delRes.statusCode == 200) {
        ok('DELETE /binder/$binderItemId → ${delRes.statusCode}');
      } else {
        fail('DELETE /binder/:id', 'Status ${delRes.statusCode}: ${delRes.body}');
      }
    } catch (e) {
      fail('DELETE /binder/:id', '$e');
    }
  } else {
    fail('DELETE /binder/:id', 'Sem binderItemId');
  }

  // ─── 13. GET /binder/stats (pós-delete) ────────────────────
  print('\n📊 13. GET /binder/stats (após delete)...');
  try {
    final statsRes2 = await http.get(
      Uri.parse('$baseUrl/binder/stats'),
      headers: authHeaders(),
    );
    if (statsRes2.statusCode == 200) {
      ok('GET /binder/stats pós-delete → 200');
    } else {
      fail('GET /binder/stats pós-delete', 'Status ${statsRes2.statusCode}');
    }
  } catch (e) {
    fail('GET /binder/stats pós-delete', '$e');
  }

  // ─── 14. POST /binder sem auth (deve dar 401) ─────────────
  print('\n🔒 14. Testes de segurança...');
  try {
    final noAuthRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'card_id': testCardId}),
    );
    if (noAuthRes.statusCode == 401) {
      ok('POST /binder sem token → 401 (correto)');
    } else {
      fail('POST /binder sem token', 'Esperava 401, recebeu ${noAuthRes.statusCode}');
    }
  } catch (e) {
    fail('POST /binder sem token', '$e');
  }

  try {
    final badRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: authHeaders(),
      body: jsonEncode({'card_id': ''}),
    );
    if (badRes.statusCode == 400) {
      ok('POST /binder card_id vazio → 400 (validação OK)');
    } else {
      fail('POST /binder card_id vazio', 'Esperava 400, recebeu ${badRes.statusCode}');
    }
  } catch (e) {
    fail('POST /binder card_id vazio', '$e');
  }

  try {
    final fakeRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: authHeaders(),
      body: jsonEncode({'card_id': '00000000-0000-0000-0000-000000000000'}),
    );
    if (fakeRes.statusCode == 404) {
      ok('POST /binder carta inexistente → 404 (validação OK)');
    } else {
      fail('POST /binder carta inexistente', 'Esperava 404, recebeu ${fakeRes.statusCode}');
    }
  } catch (e) {
    fail('POST /binder carta inexistente', '$e');
  }

  try {
    final badCondRes = await http.post(
      Uri.parse('$baseUrl/binder'),
      headers: authHeaders(),
      body: jsonEncode({'card_id': testCardId, 'condition': 'INVALID'}),
    );
    if (badCondRes.statusCode == 400) {
      ok('POST /binder condition inválida → 400 (validação OK)');
    } else {
      fail('POST /binder condition inválida', 'Esperava 400, recebeu ${badCondRes.statusCode}');
    }
  } catch (e) {
    fail('POST /binder condition inválida', '$e');
  }

  // ─── RESULTADO FINAL ──────────────────────────────────────
  print('\n${'═' * 50}');
  print('📊 RESULTADO FINAL: $passed passed, $failed failed');
  if (failed == 0) {
    print('🎉 TODOS OS TESTES PASSARAM!');
  } else {
    print('⚠️ $failed teste(s) falharam.');
  }
  print('${'═' * 50}\n');

  exit(failed > 0 ? 1 : 0);
}
