import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /decks/:id/export — Exporta o deck como lista de texto
/// Formato: "1x Card Name (set_code)"
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final conn = context.read<Pool>();

  try {
    // Verificar propriedade
    final deckResult = await conn.execute(
      Sql.named(
          'SELECT name, format FROM decks WHERE id = @deckId AND user_id = @userId'),
      parameters: {'deckId': id, 'userId': userId},
    );

    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Deck not found or permission denied.'},
      );
    }

    final deckName = deckResult.first[0] as String;
    final deckFormat = deckResult.first[1] as String;

    // Buscar cartas
    final cardsResult = await conn.execute(
      Sql.named('''
        SELECT
          dc.quantity,
          dc.is_commander,
          c.name,
          c.set_code
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
        ORDER BY dc.is_commander DESC, c.name ASC
      '''),
      parameters: {'deckId': id},
    );

    final buffer = StringBuffer();
    buffer.writeln('// $deckName ($deckFormat)');
    buffer.writeln('// Exported from ManaLoom');
    buffer.writeln();

    final commanders = <String>[];
    final mainCards = <String>[];

    for (final row in cardsResult) {
      final quantity = row[0] as int;
      final isCommander = row[1] as bool? ?? false;
      final name = row[2] as String;
      final setCode = (row[3] as String?) ?? '';

      final line =
          setCode.isNotEmpty ? '${quantity}x $name ($setCode)' : '${quantity}x $name';

      if (isCommander) {
        commanders.add(line);
      } else {
        mainCards.add(line);
      }
    }

    if (commanders.isNotEmpty) {
      buffer.writeln('// Commander');
      for (final line in commanders) {
        buffer.writeln(line);
      }
      buffer.writeln();
    }

    if (mainCards.isNotEmpty) {
      buffer.writeln('// Main Board');
      for (final line in mainCards) {
        buffer.writeln(line);
      }
    }

    final text = buffer.toString();

    return Response.json(body: {
      'deck_name': deckName,
      'format': deckFormat,
      'text': text,
      'card_count': commanders.length + mainCards.length,
    });
  } catch (e) {
    print('[ERROR] Failed to export deck: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to export deck'},
    );
  }
}
