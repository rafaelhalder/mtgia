import 'package:postgres/postgres.dart';

/// Script para verificar duplicatas em deck_cards no banco remoto
Future<void> main(List<String> args) async {
  final deckId = args.isNotEmpty 
      ? args[0] 
      : 'f2a2a34a-4561-4a77-886d-7067b672ac85';

  print('Conectando ao banco Render...');
  
  final conn = await Connection.open(
    Endpoint(
      host: 'dpg-cvc8fv5ds78s73f82t4g-a.oregon-postgres.render.com',
      port: 5432,
      database: 'mtg_qp5k',
      username: 'mtg_qp5k_user',
      password: 'K70KSZeOgHMFx9gDJBE3zHNibXN5WbWR',
    ),
    settings: ConnectionSettings(
      sslMode: SslMode.require,
    ),
  );

  try {
    print('\n=== Verificando deck: $deckId ===\n');

    // 1. Buscar todas as cartas Jin-Gitaxias no deck
    final jinResult = await conn.execute(
      Sql.named('''
        SELECT dc.id, dc.card_id, c.name, dc.quantity, dc.is_commander
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
          AND c.name ILIKE '%jin-gitaxias%'
        ORDER BY dc.is_commander DESC
      '''),
      parameters: {'deckId': deckId},
    );

    print('Cartas Jin-Gitaxias no deck:');
    if (jinResult.isEmpty) {
      print('  Nenhuma encontrada');
    } else {
      for (final row in jinResult) {
        print('  ID: ${row[0]}');
        print('  card_id: ${row[1]}');
        print('  name: ${row[2]}');
        print('  quantity: ${row[3]}');
        print('  is_commander: ${row[4]}');
        print('  ---');
      }
    }

    // 2. Verificar duplicatas por card_id
    print('\n=== Verificando duplicatas por card_id ===');
    final dupeResult = await conn.execute(
      Sql.named('''
        SELECT dc.card_id, c.name, COUNT(*) as cnt
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
        GROUP BY dc.card_id, c.name
        HAVING COUNT(*) > 1
      '''),
      parameters: {'deckId': deckId},
    );

    if (dupeResult.isEmpty) {
      print('  Nenhuma duplicata encontrada!');
    } else {
      print('  DUPLICATAS ENCONTRADAS:');
      for (final row in dupeResult) {
        print('    card_id: ${row[0]}');
        print('    name: ${row[1]}');
        print('    count: ${row[2]}');
        print('    ---');
      }
    }

    // 3. Contar total de cartas no deck
    final countResult = await conn.execute(
      Sql.named('SELECT COUNT(*) FROM deck_cards WHERE deck_id = @deckId'),
      parameters: {'deckId': deckId},
    );
    print('\nTotal de entradas em deck_cards: ${countResult.first[0]}');

    // 4. Verificar commanders
    print('\n=== Commanders do deck ===');
    final commanderResult = await conn.execute(
      Sql.named('''
        SELECT dc.card_id, c.name, dc.quantity
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId AND dc.is_commander = true
      '''),
      parameters: {'deckId': deckId},
    );
    
    if (commanderResult.isEmpty) {
      print('  Nenhum commander marcado');
    } else {
      for (final row in commanderResult) {
        print('  ${row[1]} (qty: ${row[2]})');
      }
    }

  } finally {
    await conn.close();
  }
}
