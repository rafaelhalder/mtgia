import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET  /conversations  → Listar conversas do usuário
/// POST /conversations  → Criar/obter conversa com outro usuário
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _listConversations(context),
    HttpMethod.post => _createConversation(context),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

// ─── GET /conversations ──────────────────────────────────────
Future<Response> _listConversations(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final params = context.request.uri.queryParameters;
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    // Conta total
    final countResult = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int FROM conversations
        WHERE user_a_id = @userId OR user_b_id = @userId
      '''),
      parameters: {'userId': userId},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Lista com preview da última mensagem + contagem de não lidas
    final result = await pool.execute(
      Sql.named('''
        SELECT
          c.id,
          c.user_a_id,
          c.user_b_id,
          c.last_message_at,
          c.created_at,
          -- dados do "outro" usuário
          CASE WHEN c.user_a_id = @userId THEN c.user_b_id ELSE c.user_a_id END AS other_user_id,
          u.username AS other_username,
          u.display_name AS other_display_name,
          u.avatar_url AS other_avatar_url,
          -- última mensagem (preview)
          (SELECT dm.message FROM direct_messages dm
           WHERE dm.conversation_id = c.id
           ORDER BY dm.created_at DESC LIMIT 1) AS last_message,
          (SELECT dm.sender_id FROM direct_messages dm
           WHERE dm.conversation_id = c.id
           ORDER BY dm.created_at DESC LIMIT 1) AS last_message_sender_id,
          -- contagem de não lidas
          (SELECT COUNT(*)::int FROM direct_messages dm
           WHERE dm.conversation_id = c.id
             AND dm.sender_id != @userId
             AND dm.read_at IS NULL) AS unread_count
        FROM conversations c
        JOIN users u ON u.id = CASE WHEN c.user_a_id = @userId THEN c.user_b_id ELSE c.user_a_id END
        WHERE c.user_a_id = @userId OR c.user_b_id = @userId
        ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {'userId': userId, 'lim': limit, 'off': offset},
    );

    final conversations = result.map((row) {
      final m = row.toColumnMap();
      for (final k in ['last_message_at', 'created_at']) {
        if (m[k] is DateTime) m[k] = (m[k] as DateTime).toIso8601String();
      }
      return {
        'id': m['id'],
        'other_user': {
          'id': m['other_user_id'],
          'username': m['other_username'],
          'display_name': m['other_display_name'],
          'avatar_url': m['other_avatar_url'],
        },
        'last_message': m['last_message'],
        'last_message_sender_id': m['last_message_sender_id'],
        'unread_count': m['unread_count'],
        'last_message_at': m['last_message_at'],
        'created_at': m['created_at'],
      };
    }).toList();

    return Response.json(body: {
      'data': conversations,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Erro ao listar conversas: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao listar conversas'},
    );
  }
}

// ─── POST /conversations ─────────────────────────────────────
/// Cria ou retorna conversa existente com outro usuário.
/// Body: { "user_id": "<other_user_id>" }
Future<Response> _createConversation(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final body = await context.request.json() as Map<String, dynamic>;

    final otherUserId = body['user_id'] as String?;
    if (otherUserId == null || otherUserId.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'user_id é obrigatório'},
      );
    }
    if (otherUserId == userId) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Não é possível conversar consigo mesmo'},
      );
    }

    // Verificar que o outro usuário existe
    final userCheck = await pool.execute(
      Sql.named('SELECT id, username, display_name, avatar_url FROM users WHERE id = @id'),
      parameters: {'id': otherUserId},
    );
    if (userCheck.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Usuário não encontrado'},
      );
    }
    final otherUser = userCheck.first.toColumnMap();

    // Usar LEAST/GREATEST para manter constraint UNIQUE
    final userA = userId.compareTo(otherUserId) < 0 ? userId : otherUserId;
    final userB = userId.compareTo(otherUserId) < 0 ? otherUserId : userId;

    // Tentar inserir, ON CONFLICT retorna existente
    final result = await pool.execute(
      Sql.named('''
        INSERT INTO conversations (user_a_id, user_b_id)
        VALUES (@userA, @userB)
        ON CONFLICT ON CONSTRAINT uq_conversation DO UPDATE SET created_at = conversations.created_at
        RETURNING id, created_at
      '''),
      parameters: {'userA': userA, 'userB': userB},
    );

    final conv = result.first.toColumnMap();
    final createdAt = conv['created_at'];

    return Response.json(
      statusCode: HttpStatus.ok,
      body: {
        'id': conv['id'],
        'other_user': {
          'id': otherUser['id'],
          'username': otherUser['username'],
          'display_name': otherUser['display_name'],
          'avatar_url': otherUser['avatar_url'],
        },
        'created_at': createdAt is DateTime ? createdAt.toIso8601String() : createdAt?.toString(),
      },
    );
  } catch (e) {
    print('[ERROR] Erro ao criar conversa: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao criar conversa'},
    );
  }
}
