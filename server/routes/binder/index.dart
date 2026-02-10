import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /binder  → Lista itens do binder do usuário autenticado
/// POST /binder → Adiciona carta ao binder
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method == HttpMethod.get) return _listBinder(context);
  if (method == HttpMethod.post) return _addToBinder(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// GET /binder?page=1&limit=20&condition=NM&for_trade=true&for_sale=true&search=...
Future<Response> _listBinder(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final params = context.request.uri.queryParameters;

    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 100);
    final offset = (page - 1) * limit;
    final condition = params['condition'];
    final forTrade = params['for_trade'];
    final forSale = params['for_sale'];
    final search = params['search'];
    final listType = params['list_type']; // 'have' or 'want'

    // Build dynamic WHERE
    final whereClauses = <String>['bi.user_id = @userId'];
    final sqlParams = <String, dynamic>{'userId': userId};

    if (listType != null && (listType == 'have' || listType == 'want')) {
      whereClauses.add('bi.list_type = @listType');
      sqlParams['listType'] = listType;
    }

    if (condition != null && condition.isNotEmpty) {
      whereClauses.add('bi.condition = @condition');
      sqlParams['condition'] = condition;
    }
    if (forTrade == 'true') {
      whereClauses.add('bi.for_trade = TRUE');
    }
    if (forSale == 'true') {
      whereClauses.add('bi.for_sale = TRUE');
    }
    if (search != null && search.isNotEmpty) {
      whereClauses.add('LOWER(c.name) LIKE LOWER(@search)');
      sqlParams['search'] = '%$search%';
    }

    final where = whereClauses.join(' AND ');

    // Count total
    final countResult = await pool.execute(Sql.named('''
      SELECT COUNT(*) as cnt
      FROM user_binder_items bi
      JOIN cards c ON c.id = bi.card_id
      WHERE $where
    '''), parameters: sqlParams);
    final total = countResult.first[0] as int? ?? 0;

    // Fetch items
    final result = await pool.execute(Sql.named('''
      SELECT bi.id, bi.card_id, bi.quantity, bi.condition, bi.is_foil,
             bi.for_trade, bi.for_sale, bi.price, bi.currency,
             bi.notes, bi.language, bi.list_type, bi.created_at, bi.updated_at,
             c.name AS card_name, c.image_url AS card_image_url,
             c.set_code AS card_set_code, c.mana_cost AS card_mana_cost,
             c.type_line AS card_type_line, c.rarity AS card_rarity
      FROM user_binder_items bi
      JOIN cards c ON c.id = bi.card_id
      WHERE $where
      ORDER BY c.name ASC, bi.condition ASC
      LIMIT @limit OFFSET @offset
    '''), parameters: {...sqlParams, 'limit': limit, 'offset': offset});

    final items = result.map((row) {
      final cols = row.toColumnMap();
      return {
        'id': cols['id'],
        'card': {
          'id': cols['card_id'],
          'name': cols['card_name'],
          'image_url': cols['card_image_url'],
          'set_code': cols['card_set_code'],
          'mana_cost': cols['card_mana_cost'],
          'type_line': cols['card_type_line'],
          'rarity': cols['card_rarity'],
        },
        'quantity': cols['quantity'],
        'condition': cols['condition'],
        'is_foil': cols['is_foil'],
        'for_trade': cols['for_trade'],
        'for_sale': cols['for_sale'],
        'price': cols['price'] != null ? double.tryParse(cols['price'].toString()) : null,
        'currency': cols['currency'],
        'notes': cols['notes'],
        'language': cols['language'],
        'list_type': cols['list_type'] ?? 'have',
        'created_at': cols['created_at']?.toString(),
        'updated_at': cols['updated_at']?.toString(),
      };
    }).toList();

    return Response.json(body: {
      'data': items,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Erro ao listar binder: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao listar binder'},
    );
  }
}

/// POST /binder
/// Body: { card_id, quantity?, condition?, is_foil?, for_trade?, for_sale?, price?, notes?, language? }
Future<Response> _addToBinder(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final body = await context.request.json() as Map<String, dynamic>;

    final cardId = body['card_id'] as String?;
    if (cardId == null || cardId.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'card_id é obrigatório'},
      );
    }

    // Verifica que a carta existe
    final cardCheck = await pool.execute(Sql.named(
        'SELECT id FROM cards WHERE id = @cardId'),
        parameters: {'cardId': cardId});
    if (cardCheck.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Carta não encontrada'},
      );
    }

    final quantity = body['quantity'] as int? ?? 1;
    final condition = body['condition'] as String? ?? 'NM';
    final isFoil = body['is_foil'] as bool? ?? false;
    final forTrade = body['for_trade'] as bool? ?? false;
    final forSale = body['for_sale'] as bool? ?? false;
    final price = body['price'];
    final notes = body['notes'] as String?;
    final language = body['language'] as String? ?? 'en';
    final listType = body['list_type'] as String? ?? 'have';

    // Valida list_type
    if (listType != 'have' && listType != 'want') {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'list_type inválido. Use: have, want'},
      );
    }

    // Valida condition
    if (!['NM', 'LP', 'MP', 'HP', 'DMG'].contains(condition)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Condição inválida. Use: NM, LP, MP, HP, DMG'},
      );
    }

    if (quantity < 1) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Quantidade deve ser >= 1'},
      );
    }

    // Verifica duplicata
    final dupCheck = await pool.execute(Sql.named('''
      SELECT id FROM user_binder_items
      WHERE user_id = @userId AND card_id = @cardId
        AND condition = @condition AND is_foil = @isFoil
        AND list_type = @listType
    '''), parameters: {
      'userId': userId, 'cardId': cardId,
      'condition': condition, 'isFoil': isFoil,
      'listType': listType,
    });

    if (dupCheck.isNotEmpty) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {
          'error': 'Item já existe no binder com mesma condição e foil. Use PUT para atualizar.',
          'existing_id': dupCheck.first[0],
        },
      );
    }

    // Insere
    final insertResult = await pool.execute(Sql.named('''
      INSERT INTO user_binder_items
        (user_id, card_id, quantity, condition, is_foil, for_trade, for_sale, price, notes, language, list_type)
      VALUES
        (@userId, @cardId, @quantity, @condition, @isFoil, @forTrade, @forSale, @price, @notes, @language, @listType)
      RETURNING id
    '''), parameters: {
      'userId': userId, 'cardId': cardId, 'quantity': quantity,
      'condition': condition, 'isFoil': isFoil,
      'forTrade': forTrade, 'forSale': forSale,
      'price': price != null ? double.tryParse(price.toString()) : null,
      'notes': notes, 'language': language, 'listType': listType,
    });

    final newId = insertResult.first[0];

    return Response.json(
      statusCode: HttpStatus.created,
      body: {
        'id': newId,
        'card_id': cardId,
        'quantity': quantity,
        'condition': condition,
        'is_foil': isFoil,
        'for_trade': forTrade,
        'for_sale': forSale,
        'message': 'Carta adicionada ao fichário',
      },
    );
  } catch (e) {
    print('[ERROR] Erro ao adicionar ao binder: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao adicionar ao binder'},
    );
  }
}
