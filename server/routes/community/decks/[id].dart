import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/auth_service.dart';

String? _normalizeScryfallImageUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('https://api.scryfall.com/')) return trimmed;
  try {
    final uri = Uri.parse(trimmed);
    final qp = Map<String, String>.from(uri.queryParameters);
    if (qp['set'] != null) qp['set'] = qp['set']!.toLowerCase();
    final exact = qp['exact'];
    if (uri.path == '/cards/named' && exact != null && exact.contains('//')) {
      final left = exact.split('//').first.trim();
      if (left.isNotEmpty) qp['exact'] = left;
    }
    return uri.replace(queryParameters: qp).toString();
  } catch (_) {
    return trimmed;
  }
}

Future<Response> onRequest(RequestContext context, String id) async {
  // Caso especial: /community/decks/following é capturado como id="following"
  if (id == 'following') return _getFollowingFeed(context);

  if (context.request.method == HttpMethod.get) {
    return _getPublicDeck(context, id);
  }

  if (context.request.method == HttpMethod.post) {
    return _copyPublicDeck(context, id);
  }

  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// GET /community/decks/:id — visualizar deck público (sem auth)
Future<Response> _getPublicDeck(RequestContext context, String deckId) async {
  final conn = context.read<Pool>();

  try {
    // Buscar deck público
    final deckResult = await conn.execute(
      Sql.named('''
        SELECT d.id, d.name, d.format, d.description,
               d.synergy_score, d.strengths, d.weaknesses,
               d.is_public, d.created_at,
               u.id as owner_id,
               u.username as owner_username
        FROM decks d
        JOIN users u ON u.id = d.user_id
        WHERE d.id = @deckId AND d.is_public = true
      '''),
      parameters: {'deckId': deckId},
    );

    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Deck not found or is not public.'},
      );
    }

    final deckInfo = deckResult.first.toColumnMap();
    if (deckInfo['created_at'] is DateTime) {
      deckInfo['created_at'] =
          (deckInfo['created_at'] as DateTime).toIso8601String();
    }

    // Buscar cartas
    final cardsResult = await conn.execute(
      Sql.named('''
        SELECT
          dc.quantity,
          dc.is_commander,
          c.id,
          c.name,
          c.mana_cost,
          c.type_line,
          c.oracle_text,
          c.colors,
          c.color_identity,
          c.image_url,
          c.set_code,
          c.rarity
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    final cardsList = cardsResult.map((row) {
      final m = row.toColumnMap();
      m['image_url'] = _normalizeScryfallImageUrl(m['image_url']?.toString());
      return m;
    }).toList();

    // Organizar
    final commander = <Map<String, dynamic>>[];
    final mainBoard = <String, List<Map<String, dynamic>>>{};

    String getMainType(String typeLine) {
      final t = typeLine.toLowerCase();
      if (t.contains('land')) return 'Land';
      if (t.contains('creature')) return 'Creature';
      if (t.contains('planeswalker')) return 'Planeswalker';
      if (t.contains('artifact')) return 'Artifact';
      if (t.contains('enchantment')) return 'Enchantment';
      if (t.contains('instant')) return 'Instant';
      if (t.contains('sorcery')) return 'Sorcery';
      if (t.contains('battle')) return 'Battle';
      return 'Other';
    }

    int calculateCmc(String? manaCost) {
      if (manaCost == null || manaCost.isEmpty) return 0;
      int cmc = 0;
      final regex = RegExp(r'\{(\w+)\}');
      for (final match in regex.allMatches(manaCost)) {
        final symbol = match.group(1)!;
        if (int.tryParse(symbol) != null) {
          cmc += int.parse(symbol);
        } else if (symbol.toUpperCase() != 'X') {
          cmc += 1;
        }
      }
      return cmc;
    }

    final manaCurve = <String, int>{};
    final colorDistribution = <String, int>{
      'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0, 'C': 0
    };

    for (final card in cardsList) {
      if (card['is_commander'] == true) {
        commander.add(card);
      } else {
        final type = getMainType(card['type_line'] as String? ?? '');
        mainBoard.putIfAbsent(type, () => []).add(card);
      }

      final cost = card['mana_cost'] as String?;
      final typeLine = (card['type_line'] as String? ?? '').toLowerCase();

      if (!typeLine.contains('land')) {
        final cmc = calculateCmc(cost);
        final cmcKey = cmc >= 7 ? '7+' : cmc.toString();
        manaCurve[cmcKey] =
            (manaCurve[cmcKey] ?? 0) + (card['quantity'] as int);
      }

      final colors = card['colors'] as List?;
      if (colors != null && colors.isNotEmpty) {
        for (final color in colors) {
          if (colorDistribution.containsKey(color)) {
            colorDistribution[color as String] =
                colorDistribution[color]! + (card['quantity'] as int);
          }
        }
      }
    }

    return Response.json(body: {
      ...deckInfo,
      'stats': {
        'total_cards': cardsList.fold<int>(
            0, (sum, item) => sum + (item['quantity'] as int)),
        'unique_cards': cardsList.length,
        'mana_curve': manaCurve,
        'color_distribution': colorDistribution,
      },
      'commander': commander,
      'main_board': mainBoard,
      'all_cards_flat': cardsList,
    });
  } catch (e) {
    print('[ERROR] Failed to get public deck: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to get public deck'},
    );
  }
}

/// POST /community/decks/:id — copiar deck público para conta do usuário (requer auth)
Future<Response> _copyPublicDeck(RequestContext context, String deckId) async {
  // Autenticação manual (não há middleware de auth nesta rota)
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Token de autenticação necessário para copiar decks.'},
    );
  }

  final token = authHeader.substring(7);
  final authService = AuthService();
  final payload = authService.verifyToken(token);
  if (payload == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Token inválido ou expirado.'},
    );
  }

  final userId = payload['userId'] as String;
  final conn = context.read<Pool>();

  try {
    final newDeck = await conn.runTx((session) async {
      // 1. Verificar que o deck original existe e é público
      final original = await session.execute(
        Sql.named(
            'SELECT id, name, format, description FROM decks WHERE id = @deckId AND is_public = true'),
        parameters: {'deckId': deckId},
      );

      if (original.isEmpty) {
        throw Exception('Deck not found or is not public.');
      }

      final origMap = original.first.toColumnMap();
      final newName = 'Cópia de ${origMap['name']}';

      // 2. Criar novo deck para o usuário
      final insertResult = await session.execute(
        Sql.named('''
          INSERT INTO decks (user_id, name, format, description)
          VALUES (@userId, @name, @format, @desc)
          RETURNING id, name, format, description, created_at
        '''),
        parameters: {
          'userId': userId,
          'name': newName,
          'format': origMap['format'],
          'desc': origMap['description'],
        },
      );

      final newDeckMap = insertResult.first.toColumnMap();
      if (newDeckMap['created_at'] is DateTime) {
        newDeckMap['created_at'] =
            (newDeckMap['created_at'] as DateTime).toIso8601String();
      }

      final newDeckId = newDeckMap['id'];

      // 3. Copiar todas as cartas
      await session.execute(
        Sql.named('''
          INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander)
          SELECT @newDeckId, card_id, quantity, is_commander
          FROM deck_cards WHERE deck_id = @deckId
        '''),
        parameters: {
          'newDeckId': newDeckId,
          'deckId': deckId,
        },
      );

      return newDeckMap;
    });

    return Response.json(
      statusCode: HttpStatus.created,
      body: {'success': true, 'deck': newDeck},
    );
  } on Exception catch (e) {
    print('[ERROR] Failed to copy deck: $e');
    final msg = e.toString();
    if (msg.contains('not found') || msg.contains('not public')) {
      return Response.json(statusCode: 404, body: {'error': msg});
    }
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to copy deck'},
    );
  }
}

/// GET /community/decks/following?page=1&limit=20
/// Retorna decks públicos dos usuários que o autenticado segue.
/// Requer JWT (Authorization header).
Future<Response> _getFollowingFeed(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // Auth manual (comunidade é sem middleware de auth)
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Authentication required.'},
    );
  }

  final token = authHeader.substring(7);
  final authService = AuthService();
  final payload = authService.verifyToken(token);
  if (payload == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Invalid or expired token.'},
    );
  }

  final userId = payload['userId'] as String;

  try {
    final conn = context.read<Pool>();
    final params = context.request.uri.queryParameters;
    final page = int.tryParse(params['page'] ?? '') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    // Count total
    final countResult = await conn.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM decks d
        JOIN user_follows uf ON uf.following_id = d.user_id
        WHERE uf.follower_id = @userId
          AND d.is_public = true
      '''),
      parameters: {'userId': userId},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch decks from followed users
    final result = await conn.execute(
      Sql.named('''
        SELECT
          d.id,
          d.name,
          d.format,
          d.description,
          d.synergy_score,
          d.created_at,
          u.username as owner_username,
          u.id as owner_id,
          cmd.commander_name,
          COALESCE(cmd.commander_image_url, first_card.first_image_url) as commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        JOIN users u ON u.id = d.user_id
        JOIN user_follows uf ON uf.following_id = d.user_id
        LEFT JOIN LATERAL (
          SELECT
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN LATERAL (
          SELECT c.image_url as first_image_url
          FROM deck_cards dc_fc
          JOIN cards c ON c.id = dc_fc.card_id
          WHERE dc_fc.deck_id = d.id
            AND c.image_url IS NOT NULL
            AND c.image_url != ''
          ORDER BY dc_fc.quantity DESC, c.name
          LIMIT 1
        ) first_card ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE uf.follower_id = @userId
          AND d.is_public = true
        GROUP BY d.id, u.username, u.id, cmd.commander_name, cmd.commander_image_url, first_card.first_image_url
        ORDER BY d.created_at DESC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {
        'userId': userId,
        'lim': limit,
        'off': offset,
      },
    );

    final decks = result.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      m['commander_image_url'] =
          _normalizeScryfallImageUrl(m['commander_image_url']?.toString());
      return m;
    }).toList();

    return Response.json(body: {
      'data': decks,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Internal server error: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error'},
    );
  }
}
