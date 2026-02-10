import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /community/marketplace → Busca global de cartas para troca/venda
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final pool = context.read<Pool>();
    final params = context.request.uri.queryParameters;

    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 100);
    final offset = (page - 1) * limit;

    // Filtros
    final search = params['search']?.trim();
    final condition = params['condition'];
    final forTrade = params['for_trade'];
    final forSale = params['for_sale'];
    final setCode = params['set_code'];
    final rarity = params['rarity'];

    final whereClauses = <String>[
      '(bi.for_trade = TRUE OR bi.for_sale = TRUE)',
    ];
    final sqlParams = <String, dynamic>{};

    if (search != null && search.isNotEmpty) {
      whereClauses.add('c.name ILIKE @search');
      sqlParams['search'] = '%$search%';
    }

    final validConditions = {'NM', 'LP', 'MP', 'HP', 'DMG'};
    if (condition != null && validConditions.contains(condition.toUpperCase())) {
      whereClauses.add('bi.condition = @condition');
      sqlParams['condition'] = condition.toUpperCase();
    }

    if (forTrade == 'true') {
      whereClauses.add('bi.for_trade = TRUE');
    }
    if (forSale == 'true') {
      whereClauses.add('bi.for_sale = TRUE');
    }

    if (setCode != null && setCode.isNotEmpty) {
      whereClauses.add('c.set_code = @setCode');
      sqlParams['setCode'] = setCode.toLowerCase();
    }
    if (rarity != null && rarity.isNotEmpty) {
      whereClauses.add('c.rarity = @rarity');
      sqlParams['rarity'] = rarity.toLowerCase();
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

    // Items com dados do dono e da carta
    final result = await pool.execute(Sql.named('''
      SELECT bi.id, bi.card_id, bi.quantity, bi.condition, bi.is_foil,
             bi.for_trade, bi.for_sale, bi.price, bi.currency, bi.notes,
             bi.user_id, bi.list_type,
             c.name AS card_name, c.image_url AS card_image_url,
             c.set_code AS card_set_code, c.mana_cost AS card_mana_cost,
             c.rarity AS card_rarity, c.type_line AS card_type_line,
             u.username AS owner_username, u.display_name AS owner_display_name,
             u.avatar_url AS owner_avatar_url,
             u.location_state AS owner_location_state,
             u.location_city AS owner_location_city,
             u.trade_notes AS owner_trade_notes
      FROM user_binder_items bi
      JOIN cards c ON c.id = bi.card_id
      JOIN users u ON u.id = bi.user_id
      WHERE $where
      ORDER BY bi.created_at DESC
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
          'rarity': cols['card_rarity'],
          'type_line': cols['card_type_line'],
        },
        'quantity': cols['quantity'],
        'condition': cols['condition'],
        'is_foil': cols['is_foil'],
        'for_trade': cols['for_trade'],
        'for_sale': cols['for_sale'],
        'price': cols['price'] != null
            ? double.tryParse(cols['price'].toString())
            : null,
        'currency': cols['currency'],
        'notes': cols['notes'],
        'list_type': cols['list_type'] ?? 'have',
        'owner': {
          'id': cols['user_id'],
          'username': cols['owner_username'],
          'display_name': cols['owner_display_name'],
          'avatar_url': cols['owner_avatar_url'],
          'location_state': cols['owner_location_state'],
          'location_city': cols['owner_location_city'],
          'trade_notes': cols['owner_trade_notes'],
        },
      };
    }).toList();

    return Response.json(body: {
      'data': items,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Erro ao buscar marketplace: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao buscar marketplace'},
    );
  }
}
