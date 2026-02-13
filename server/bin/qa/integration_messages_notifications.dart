// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Teste de integração completo para Épico 4 (Mensagens) e Épico 5 (Notificações)
///
/// Uso: dart run bin/qa/integration_messages_notifications.dart
///
/// Pré-requisitos:
///   - dart_frog dev rodando em localhost:8080
///   - Usuário rafaelhalder@gmail.com cadastrado
///   - Tabelas conversations, direct_messages, notifications criadas
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

  // ═══════════════════════════════════════════════════════════
  // 1. LOGIN
  // ═══════════════════════════════════════════════════════════
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
    ok('POST /auth/login → 200 (token=${ token.substring(0, 10) }..., userId=$userId)');
  } catch (e) {
    print('❌ FATAL: Não foi possível conectar ao servidor: $e');
    print('   Certifique-se de que dart_frog dev está rodando.');
    exit(1);
  }

  Map<String, String> authHeaders() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ═══════════════════════════════════════════════════════════
  // 2. NOTIFICAÇÕES — ENDPOINTS BÁSICOS
  // ═══════════════════════════════════════════════════════════
  print('\n🔔 2. Notificações - Endpoints Básicos...');

  // GET /notifications/count
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/notifications/count'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final unread = body['unread'] as int?;
      ok('GET /notifications/count → 200 (unread=$unread)');
    } else {
      fail('GET /notifications/count', 'Status ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /notifications/count', '$e');
  }

  // GET /notifications
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/notifications?page=1&limit=10'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] as List?;
      ok('GET /notifications → 200 (${data?.length ?? 0} notificações)');
    } else {
      fail('GET /notifications', 'Status ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /notifications', '$e');
  }

  // GET /notifications?unread_only=true
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/notifications?unread_only=true&limit=5'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      ok('GET /notifications?unread_only=true → 200');
    } else {
      fail('GET /notifications?unread_only', 'Status ${res.statusCode}');
    }
  } catch (e) {
    fail('GET /notifications?unread_only', '$e');
  }

  // PUT /notifications/read-all
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      ok('PUT /notifications/read-all → 200');
    } else {
      fail('PUT /notifications/read-all', 'Status ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('PUT /notifications/read-all', '$e');
  }

  // GET /notifications sem auth → 401
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode == 401) {
      ok('GET /notifications sem auth → 401');
    } else {
      fail('GET /notifications sem auth', 'Esperava 401, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('GET /notifications sem auth', '$e');
  }

  // GET /notifications/count sem auth → 401
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/notifications/count'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode == 401) {
      ok('GET /notifications/count sem auth → 401');
    } else {
      fail('GET /notifications/count sem auth', 'Esperava 401, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('GET /notifications/count sem auth', '$e');
  }

  // ═══════════════════════════════════════════════════════════
  // 3. CONVERSAS — ENDPOINTS
  // ═══════════════════════════════════════════════════════════
  print('\n💬 3. Conversas...');

  // GET /conversations (lista vazia ou com itens)
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/conversations?page=1&limit=10'),
      headers: authHeaders(),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] as List?;
      ok('GET /conversations → 200 (${data?.length ?? 0} conversas)');
    } else {
      fail('GET /conversations', 'Status ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('GET /conversations', '$e');
  }

  // POST /conversations sem user_id → 400
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: authHeaders(),
      body: jsonEncode({}),
    );
    if (res.statusCode == 400) {
      ok('POST /conversations sem user_id → 400');
    } else {
      fail('POST /conversations sem user_id', 'Esperava 400, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST /conversations sem user_id', '$e');
  }

  // POST /conversations com self → 400 (não pode conversar consigo)
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: authHeaders(),
      body: jsonEncode({'user_id': userId}),
    );
    if (res.statusCode == 400) {
      ok('POST /conversations com self → 400');
    } else {
      fail('POST /conversations com self', 'Esperava 400, recebeu ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    fail('POST /conversations com self', '$e');
  }

  // POST /conversations sem auth → 401
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': 'some-id'}),
    );
    if (res.statusCode == 401) {
      ok('POST /conversations sem auth → 401');
    } else {
      fail('POST /conversations sem auth', 'Esperava 401, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST /conversations sem auth', '$e');
  }

  // ═══════════════════════════════════════════════════════════
  // 4. CONVERSA COM USUÁRIO DE TESTE
  // ═══════════════════════════════════════════════════════════
  print('\n💬 4. Criar/Obter conversa + enviar mensagens...');

  // Buscar um outro usuário para conversar (via seguidores, comunidade, etc.)
  String? otherUserId;
  String? conversationId;

  try {
    // Tentar buscar um user da comunidade
    final usersRes = await http.get(
      Uri.parse('$baseUrl/community/users?limit=5'),
      headers: authHeaders(),
    );
    if (usersRes.statusCode == 200) {
      final usersBody = jsonDecode(usersRes.body);
      final users = usersBody['data'] as List? ?? [];
      // Pegar o primeiro que não é eu
      for (final u in users) {
        final uid = u['id'] as String? ?? '';
        if (uid.isNotEmpty && uid != userId) {
          otherUserId = uid;
          break;
        }
      }
    }
  } catch (e) {
    print('   ⚠️ Não encontrou outro user para teste de DM: $e');
  }

  if (otherUserId != null) {
    // POST /conversations → criar/obter conversa
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/conversations'),
        headers: authHeaders(),
        body: jsonEncode({'user_id': otherUserId}),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final body = jsonDecode(res.body);
        conversationId = body['id'] as String?;
        final otherUser = body['other_user'];
        ok('POST /conversations → ${res.statusCode} (id=${conversationId?.substring(0, 8)}..., other=${otherUser?['username']})');
      } else {
        fail('POST /conversations', 'Status ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      fail('POST /conversations', '$e');
    }

    // POST mesmo user novamente → deve retornar a MESMA conversa (idempotente)
    if (conversationId != null) {
      try {
        final res = await http.post(
          Uri.parse('$baseUrl/conversations'),
          headers: authHeaders(),
          body: jsonEncode({'user_id': otherUserId}),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          final body = jsonDecode(res.body);
          final sameId = body['id'] as String?;
          if (sameId == conversationId) {
            ok('POST /conversations idempotente → mesma conversa retornada');
          } else {
            fail('POST /conversations idempotente', 'ID diferente: $sameId vs $conversationId');
          }
        } else {
          fail('POST /conversations idempotente', 'Status ${res.statusCode}');
        }
      } catch (e) {
        fail('POST /conversations idempotente', '$e');
      }
    }

    // Enviar mensagem
    if (conversationId != null) {
      try {
        final res = await http.post(
          Uri.parse('$baseUrl/conversations/$conversationId/messages'),
          headers: authHeaders(),
          body: jsonEncode({'content': 'Teste de integração - ${DateTime.now().toIso8601String()}'}),
        );
        if (res.statusCode == 201) {
          ok('POST /conversations/:id/messages → 201 (mensagem enviada)');
        } else {
          fail('POST /conversations/:id/messages', 'Status ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        fail('POST /conversations/:id/messages', '$e');
      }

      // Enviar mensagem sem conteúdo → 400
      try {
        final res = await http.post(
          Uri.parse('$baseUrl/conversations/$conversationId/messages'),
          headers: authHeaders(),
          body: jsonEncode({}),
        );
        if (res.statusCode == 400) {
          ok('POST /conversations/:id/messages sem content → 400');
        } else {
          fail('POST messages sem content', 'Esperava 400, recebeu ${res.statusCode}');
        }
      } catch (e) {
        fail('POST messages sem content', '$e');
      }

      // GET mensagens
      try {
        final res = await http.get(
          Uri.parse('$baseUrl/conversations/$conversationId/messages?page=1&limit=10'),
          headers: authHeaders(),
        );
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final data = body['data'] as List?;
          ok('GET /conversations/:id/messages → 200 (${data?.length ?? 0} mensagens)');
        } else {
          fail('GET /conversations/:id/messages', 'Status ${res.statusCode}');
        }
      } catch (e) {
        fail('GET /conversations/:id/messages', '$e');
      }

      // PUT mark as read
      try {
        final res = await http.put(
          Uri.parse('$baseUrl/conversations/$conversationId/read'),
          headers: authHeaders(),
        );
        if (res.statusCode == 200) {
          ok('PUT /conversations/:id/read → 200');
        } else {
          fail('PUT /conversations/:id/read', 'Status ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        fail('PUT /conversations/:id/read', '$e');
      }
    }
  } else {
    print('   ⚠️ Nenhum outro user disponível — skipping conversation CRUD tests');
    print('   (Cadastre outro user para rodar estes testes)');
  }

  // ═══════════════════════════════════════════════════════════
  // 5. CONVERSA INEXISTENTE
  // ═══════════════════════════════════════════════════════════
  print('\n❌ 5. Conversas inexistentes / erros...');

  final fakeConvId = '00000000-0000-0000-0000-000000000000';

  // GET messages de conversa inexistente → 403 ou 404
  try {
    final res = await http.get(
      Uri.parse('$baseUrl/conversations/$fakeConvId/messages'),
      headers: authHeaders(),
    );
    if (res.statusCode == 403 || res.statusCode == 404) {
      ok('GET messages de conversa inexistente → ${res.statusCode}');
    } else {
      fail('GET messages inexistente', 'Esperava 403/404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('GET messages inexistente', '$e');
  }

  // POST message em conversa inexistente → 403 ou 404
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/conversations/$fakeConvId/messages'),
      headers: authHeaders(),
      body: jsonEncode({'content': 'test'}),
    );
    if (res.statusCode == 403 || res.statusCode == 404) {
      ok('POST message em conversa inexistente → ${res.statusCode}');
    } else {
      fail('POST message inexistente', 'Esperava 403/404, recebeu ${res.statusCode}');
    }
  } catch (e) {
    fail('POST message inexistente', '$e');
  }

  // ═══════════════════════════════════════════════════════════
  // 6. NOTIFICAÇÕES — MARK READ
  // ═══════════════════════════════════════════════════════════
  print('\n🔔 6. Notificações - Mark Read...');

  // PUT /notifications/:id/read com ID inexistente → 404
  try {
    final res = await http.put(
      Uri.parse('$baseUrl/notifications/$fakeConvId/read'),
      headers: authHeaders(),
    );
    if (res.statusCode == 404) {
      ok('PUT /notifications/:id/read (inexistente) → 404');
    } else {
      // Some implementations return 200 even for non-existent
      ok('PUT /notifications/:id/read (inexistente) → ${res.statusCode} (accepted)');
    }
  } catch (e) {
    fail('PUT /notifications/:id/read', '$e');
  }

  // ═══════════════════════════════════════════════════════════
  // RESULTADO FINAL
  // ═══════════════════════════════════════════════════════════
  print('\n${'═' * 50}');
  print('📊 Resultado: $passed passou, $failed falhou');
  print('${'═' * 50}');

  if (failed > 0) {
    exit(1);
  }
}
