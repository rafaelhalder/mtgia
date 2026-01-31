import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/deck_rules_service.dart';

bool? _hasDeckMetaColumnsCache;
Future<bool> _hasDeckMetaColumns(Pool pool) async {
  if (_hasDeckMetaColumnsCache != null) return _hasDeckMetaColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('archetype', 'bracket')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckMetaColumnsCache = count >= 2;
  } catch (_) {
    _hasDeckMetaColumnsCache = false;
  }
  return _hasDeckMetaColumnsCache!;
}

bool? _hasDeckPricingColumnsCache;
Future<bool> _hasDeckPricingColumns(Pool pool) async {
  if (_hasDeckPricingColumnsCache != null) return _hasDeckPricingColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('pricing_currency','pricing_total','pricing_missing_cards','pricing_updated_at')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckPricingColumnsCache = count >= 4;
  } catch (_) {
    _hasDeckPricingColumnsCache = false;
  }
  return _hasDeckPricingColumnsCache!;
}

Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method == HttpMethod.get) {
    return _getDeckById(context, deckId);
  }

  if (context.request.method == HttpMethod.put) {
    return _updateDeck(context, deckId);
  }

  if (context.request.method == HttpMethod.delete) {
    return _deleteDeck(context, deckId);
  }

  // Futuramente, podemos adicionar PUT para atualizar e DELETE para remover.
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// Deleta um deck.
Future<Response> _deleteDeck(RequestContext context, String deckId) async {
  final userId = context.read<String>();
  final conn = context.read<Pool>();

  try {
    // Usamos uma transação para garantir que o deck e suas cartas sejam removidos atomicamente.
    await conn.runTx((session) async {
      // 1. Verifica se o deck existe e pertence ao usuário antes de deletar
      final result = await session.execute(
        Sql.named(
            'DELETE FROM decks WHERE id = @deckId AND user_id = @userId RETURNING id'),
        parameters: {'deckId': deckId, 'userId': userId},
      );

      // Se nenhum registro foi retornado, o deck não foi encontrado ou o usuário não tem permissão
      if (result.isEmpty) {
        throw Exception('Deck not found or permission denied.');
      }

      // A tabela `deck_cards` deve ter uma restrição de chave estrangeira com `ON DELETE CASCADE`,
      // o que removeria as cartas automaticamente. Se não, precisaríamos deletar manualmente:
      // await session.execute(
      //   Sql.named('DELETE FROM deck_cards WHERE deck_id = @deckId'),
      //   parameters: {'deckId': deckId},
      // );
    });

    return Response(
        statusCode: HttpStatus
            .noContent); // 204 No Content é a resposta padrão para sucesso em DELETE
  } on Exception catch (e) {
    if (e.toString().contains('permission denied')) {
      return Response.json(statusCode: 404, body: {'error': e.toString()});
    }
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to delete deck: $e'},
    );
  }
}

/// Atualiza um deck existente (nome, formato, cartas, etc.).
Future<Response> _updateDeck(RequestContext context, String deckId) async {
  final userId = context.read<String>();
  final conn = context.read<Pool>();
  final hasMeta = await _hasDeckMetaColumns(conn);

  final body = await context.request.json();
  final name = body['name'] as String?;
  final format = body['format'] as String?;
  final description = body['description'] as String?;
  final archetype = body['archetype'] as String?;
  final bracketRaw = body['bracket'];
  final bracket =
      bracketRaw is int ? bracketRaw : int.tryParse('${bracketRaw ?? ''}');
  final cards = body['cards'] as List?; // Lista completa e nova de cartas

  try {
    final updatedDeck = await conn.runTx((session) async {
      // 1. Verifica se o deck existe e pertence ao usuário
      final deckCheck = await session.execute(
        Sql.named(hasMeta
            ? 'SELECT id, name, format, description, archetype, bracket FROM decks WHERE id = @deckId AND user_id = @userId'
            : 'SELECT id, name, format, description, NULL::text as archetype, NULL::int as bracket FROM decks WHERE id = @deckId AND user_id = @userId'),
        parameters: {'deckId': deckId, 'userId': userId},
      );

      if (deckCheck.isEmpty) {
        throw Exception('Deck not found or permission denied.');
      }

      final existingName = deckCheck.first[1] as String;
      final existingFormat = deckCheck.first[2] as String;
      final existingDescription = deckCheck.first[3] as String?;
      final existingArchetype = deckCheck.first[4] as String?;
      final existingBracket = deckCheck.first[5] as int?;

      final nextName = name ?? existingName;
      final nextFormat = format ?? existingFormat;
      final nextDescription = description ?? existingDescription;
      final nextArchetype = archetype ?? existingArchetype;
      final nextBracket = bracket ?? existingBracket;

      final currentFormat = nextFormat.toLowerCase();

      // 2. Atualiza os dados do deck
      if (name != null ||
          format != null ||
          description != null ||
          archetype != null ||
          bracket != null) {
        await session.execute(
          Sql.named(
            hasMeta
                ? 'UPDATE decks SET name = @name, format = @format, description = @desc, archetype = @archetype, bracket = @bracket WHERE id = @deckId'
                : 'UPDATE decks SET name = @name, format = @format, description = @desc WHERE id = @deckId',
          ),
          parameters: {
            'name': nextName,
            'format': nextFormat,
            'desc': nextDescription,
            if (hasMeta) 'archetype': nextArchetype,
            if (hasMeta) 'bracket': nextBracket,
            'deckId': deckId,
          },
        );
      }

      // 3. Se uma nova lista de cartas for enviada, substitui a antiga
      if (cards != null) {
        final normalized = cards
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        await DeckRulesService(session).validateAndThrow(
          format: currentFormat,
          cards: normalized,
          strict: false,
        );

        // Apaga as cartas antigas
        await session.execute(
          Sql.named('DELETE FROM deck_cards WHERE deck_id = @deckId'),
          parameters: {'deckId': deckId},
        );

        // Insere as novas cartas usando Batch Insert (MUITO MAIS RÁPIDO)
        if (cards.isNotEmpty) {
          // Construir query dinâmica para inserção em lote
          // INSERT INTO deck_cards (...) VALUES ($1, $2...), ($5, $6...), ...
          final values = <String>[];
          final params = <String, dynamic>{'deckId': deckId};

          for (var i = 0; i < cards.length; i++) {
            final card = cards[i];
            final pId = 'c$i';
            final pQty = 'q$i';
            final pCmdr = 'cmd$i';

            values.add('(@deckId, @$pId, @$pQty, @$pCmdr)');
            params[pId] = card['card_id'];
            params[pQty] = card['quantity'];
            params[pCmdr] = card['is_commander'] ?? false;
          }

          final batchInsertSql =
              'INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander) VALUES ${values.join(', ')}';

          await session.execute(
            Sql.named(batchInsertSql),
            parameters: params,
          );
        }
      }

      // Retorna o deck atualizado (sem a lista de cartas, para simplicidade)
      final result = await session.execute(
        Sql.named('SELECT * FROM decks WHERE id = @deckId'),
        parameters: {'deckId': deckId},
      );
      final deckMap = result.first.toColumnMap();
      // Converter todos os DateTime para ISO string
      for (final key in deckMap.keys.toList()) {
        if (deckMap[key] is DateTime) {
          deckMap[key] = (deckMap[key] as DateTime).toIso8601String();
        }
      }
      return deckMap;
    });

    return Response.json(body: {'success': true, 'deck': updatedDeck});
  } on DeckRulesException catch (e) {
    return Response.json(
        statusCode: HttpStatus.badRequest, body: {'error': e.message});
  } on Exception catch (e) {
    if (e.toString().contains('permission denied')) {
      return Response.json(statusCode: 404, body: {'error': e.toString()});
    }
    return Response.json(
        statusCode: 500, body: {'error': 'Failed to update deck: $e'});
  }
}

/// Busca um deck específico pelo seu ID, incluindo a lista de cartas.
Future<Response> _getDeckById(RequestContext context, String deckId) async {
  final userId = context.read<String>();
  final conn = context.read<Pool>();
  final hasMeta = await _hasDeckMetaColumns(conn);
  final hasPricing = await _hasDeckPricingColumns(conn);

  try {
    // 1. Buscar os detalhes do deck e verificar se pertence ao usuário
    final deckResult = await conn.execute(
      Sql.named(
        [
          'SELECT id, name, format, description,',
          hasMeta
              ? 'archetype, bracket,'
              : 'NULL::text as archetype, NULL::int as bracket,',
          'synergy_score, strengths, weaknesses,',
          hasPricing
              ? 'pricing_currency, pricing_total, pricing_missing_cards, pricing_updated_at,'
              : "NULL::text as pricing_currency, NULL::numeric as pricing_total, 0::int as pricing_missing_cards, NULL::timestamptz as pricing_updated_at,",
          'created_at',
          'FROM decks WHERE id = @deckId AND user_id = @userId',
        ].join(' '),
      ),
      parameters: {
        'deckId': deckId,
        'userId': userId,
      },
    );

    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {
          'error': 'Deck not found or you do not have permission to view it.'
        },
      );
    }

    final deckInfo = deckResult.first.toColumnMap();
    if (deckInfo['created_at'] is DateTime) {
      deckInfo['created_at'] =
          (deckInfo['created_at'] as DateTime).toIso8601String();
    }
    if (deckInfo['pricing_updated_at'] is DateTime) {
      deckInfo['pricing_updated_at'] =
          (deckInfo['pricing_updated_at'] as DateTime).toIso8601String();
    }
    // PostgreSQL DECIMAL retorna String, converter para double
    final rawPricingTotal = deckInfo['pricing_total'];
    if (rawPricingTotal is String) {
      deckInfo['pricing_total'] = double.tryParse(rawPricingTotal);
    } else if (rawPricingTotal is num) {
      deckInfo['pricing_total'] = rawPricingTotal.toDouble();
    }

    // 2. Buscar todas as cartas associadas a esse deck com detalhes
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

    final cardsList = cardsResult.map((row) => row.toColumnMap()).toList();

    // 3. Organizar para visualização (Separar Comandante e Agrupar por Tipo)
    final commander = <Map<String, dynamic>>[];
    final mainBoard = <Map<String, dynamic>>[];

    for (final card in cardsList) {
      if (card['is_commander'] == true) {
        commander.add(card);
      } else {
        mainBoard.add(card);
      }
    }

    // Helper to get main type
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

    // Helper to calculate CMC (Approximation)
    int calculateCmc(String? manaCost) {
      if (manaCost == null || manaCost.isEmpty) return 0;
      int cmc = 0;
      final regex = RegExp(r'\{(\w+)\}');
      final matches = regex.allMatches(manaCost);
      for (final match in matches) {
        final symbol = match.group(1)!;
        if (int.tryParse(symbol) != null) {
          cmc += int.parse(symbol);
        } else if (symbol.toUpperCase() == 'X') {
          // X counts as 0
        } else {
          // W, U, B, R, G, C, P, etc count as 1
          cmc += 1;
        }
      }
      return cmc;
    }

    final groupedMainBoard = <String, List<Map<String, dynamic>>>{};
    final manaCurve = <String, int>{};
    final colorDistribution = <String, int>{
      'W': 0,
      'U': 0,
      'B': 0,
      'R': 0,
      'G': 0,
      'C': 0
    };

    for (final card in cardsList) {
      // Grouping
      if (card['is_commander'] != true) {
        final type = getMainType(card['type_line'] as String? ?? '');
        if (!groupedMainBoard.containsKey(type)) {
          groupedMainBoard[type] = [];
        }
        groupedMainBoard[type]!.add(card);
      }

      // Stats Calculation (ignoring lands for curve usually, but let's include everything that has a cost)
      final cost = card['mana_cost'] as String?;
      final typeLine = (card['type_line'] as String? ?? '').toLowerCase();

      if (!typeLine.contains('land')) {
        final cmc = calculateCmc(cost);
        final cmcKey = cmc >= 7 ? '7+' : cmc.toString();
        manaCurve[cmcKey] =
            (manaCurve[cmcKey] ?? 0) + (card['quantity'] as int);
      }

      // Color Distribution
      final colors = card['colors'] as List?;
      if (colors != null && colors.isNotEmpty) {
        for (final color in colors) {
          if (colorDistribution.containsKey(color)) {
            colorDistribution[color as String] =
                colorDistribution[color]! + (card['quantity'] as int);
          }
        }
      } else if (cost != null && cost.contains('{C}')) {
        colorDistribution['C'] =
            colorDistribution['C']! + (card['quantity'] as int);
      }
    }

    final responseBody = {
      ...deckInfo,
      'stats': {
        'total_cards': cardsList.fold<int>(
            0, (sum, item) => sum + (item['quantity'] as int)),
        'unique_cards': cardsList.length,
        'mana_curve': manaCurve,
        'color_distribution': colorDistribution,
      },
      'commander': commander,
      'main_board': groupedMainBoard,
      'all_cards_flat': cardsList,
    };

    return Response.json(body: responseBody);
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to retrieve deck details: $e'},
    );
  }
}
