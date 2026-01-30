import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// POST /decks/:id/ai-analysis
///
/// Gera (ou atualiza) os campos de análise do deck:
/// - decks.synergy_score
/// - decks.strengths
/// - decks.weaknesses
///
/// Body opcional:
/// { "force": true }
Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final pool = context.read<Pool>();

  try {
    final body = await context.request
        .json()
        .catchError((_) => const <String, dynamic>{});
    final force = body is Map ? (body['force'] == true) : false;

    final deckResult = await pool.execute(
      Sql.named(
        'SELECT id, format, COALESCE(archetype, \'\') as archetype, bracket, synergy_score, strengths, weaknesses '
        'FROM decks WHERE id = @deckId AND user_id = @userId',
      ),
      parameters: {'deckId': deckId, 'userId': userId},
    );

    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Deck not found.'},
      );
    }

    final deckRow = deckResult.first.toColumnMap();
    final format = (deckRow['format'] as String).toLowerCase();
    final archetype = (deckRow['archetype'] as String?)?.trim() ?? '';
    final bracket = deckRow['bracket'] as int?;

    final existingScore = deckRow['synergy_score'] as int?;
    final existingStrengths = deckRow['strengths'] as String?;
    final existingWeaknesses = deckRow['weaknesses'] as String?;

    if (!force &&
        existingScore != null &&
        existingScore > 0 &&
        (existingStrengths ?? '').trim().isNotEmpty &&
        (existingWeaknesses ?? '').trim().isNotEmpty) {
      return Response.json(
        body: {
          'deck_id': deckId,
          'synergy_score': existingScore,
          'strengths': existingStrengths,
          'weaknesses': existingWeaknesses,
          'cached': true,
        },
      );
    }

    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT
          dc.quantity,
          dc.is_commander,
          c.name,
          c.type_line,
          c.oracle_text,
          c.mana_cost,
          c.colors,
          c.color_identity,
          COALESCE(
            (SELECT SUM(
              CASE
                WHEN m[1] ~ '^[0-9]+\$' THEN m[1]::int
                WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
                WHEN m[1] = 'X' THEN 0
                ELSE 1
              END
            ) FROM regexp_matches(c.mana_cost, '\\{([^}]+)\\}', 'g') AS m(m)),
            0
          ) as cmc
        FROM deck_cards dc
        JOIN cards c ON c.id = dc.card_id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    final metrics = _computeMetrics(cardsResult, format: format);

    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    Map<String, dynamic> analysis;
    var isMock = false;
    if (apiKey == null || apiKey.isEmpty) {
      analysis = _heuristicAnalysis(
        format: format,
        archetype: archetype,
        bracket: bracket,
        metrics: metrics,
      );
      isMock = true;
    } else {
      try {
        analysis = await _aiAnalysis(
          apiKey: apiKey,
          format: format,
          archetype: archetype,
          bracket: bracket,
          metrics: metrics,
        );
      } catch (_) {
        isMock = true;
        analysis = _heuristicAnalysis(
          format: format,
          archetype: archetype,
          bracket: bracket,
          metrics: metrics,
        );
      }
    }

    final synergyScore = _clampInt(analysis['synergy_score'], min: 0, max: 100);
    final strengths = (analysis['strengths'] as String?)?.trim() ?? '';
    final weaknesses = (analysis['weaknesses'] as String?)?.trim() ?? '';

    await pool.execute(
      Sql.named('''
        UPDATE decks
        SET synergy_score = @score,
            strengths = @strengths,
            weaknesses = @weaknesses
        WHERE id = @deckId AND user_id = @userId
      '''),
      parameters: {
        'score': synergyScore,
        'strengths': strengths,
        'weaknesses': weaknesses,
        'deckId': deckId,
        'userId': userId,
      },
    );

    return Response.json(
      body: {
        'deck_id': deckId,
        'synergy_score': synergyScore,
        'strengths': strengths,
        'weaknesses': weaknesses,
        'metrics': metrics.toJson(),
        if (isMock) 'is_mock': true,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to analyze deck: $e'},
    );
  }
}

class _DeckMetrics {
  final int totalCards;
  final int nonLandCards;
  final int landCount;
  final int commanderCount;
  final List<String> commanders;
  final double averageCmcNonLands;
  final int rampCount;
  final int drawCount;
  final int removalCount;
  final int boardWipeCount;
  final int protectionCount;

  _DeckMetrics({
    required this.totalCards,
    required this.nonLandCards,
    required this.landCount,
    required this.commanderCount,
    required this.commanders,
    required this.averageCmcNonLands,
    required this.rampCount,
    required this.drawCount,
    required this.removalCount,
    required this.boardWipeCount,
    required this.protectionCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'total_cards': totalCards,
      'non_land_cards': nonLandCards,
      'land_count': landCount,
      'commander_count': commanderCount,
      'commanders': commanders,
      'average_cmc_non_lands':
          double.parse(averageCmcNonLands.toStringAsFixed(2)),
      'ramp_count': rampCount,
      'draw_count': drawCount,
      'removal_count': removalCount,
      'board_wipe_count': boardWipeCount,
      'protection_count': protectionCount,
    };
  }
}

_DeckMetrics _computeMetrics(Result cardsResult, {required String format}) {
  var total = 0;
  var lands = 0;
  var nonLands = 0;
  var commanderCount = 0;
  final commanders = <String>[];

  var ramp = 0;
  var draw = 0;
  var removal = 0;
  var wipes = 0;
  var protection = 0;

  double totalCmcNonLands = 0;

  for (final row in cardsResult) {
    final m = row.toColumnMap();
    final qty = (m['quantity'] as int?) ?? 0;
    final isCommander = (m['is_commander'] as bool?) ?? false;
    final name = (m['name'] as String?) ?? '';
    final typeLine = ((m['type_line'] as String?) ?? '').toLowerCase();
    final oracle = ((m['oracle_text'] as String?) ?? '').toLowerCase();
    final cmc = (m['cmc'] as num?)?.toDouble() ?? 0.0;

    total += qty;

    if (isCommander) {
      commanderCount += qty;
      if (name.trim().isNotEmpty) commanders.add(name);
    }

    if (typeLine.contains('land')) {
      lands += qty;
      continue;
    }

    nonLands += qty;
    totalCmcNonLands += cmc * qty;

    // Ramp (heurística simples)
    if (oracle.contains('add {') ||
        (oracle.contains('search your library') && oracle.contains('land')) ||
        oracle.contains('put a land card')) {
      ramp += qty;
    }

    // Draw
    if (oracle.contains('draw') && oracle.contains('card')) {
      draw += qty;
    }

    // Removal
    if (oracle.contains('destroy target') ||
        oracle.contains('exile target') ||
        (oracle.contains('deal') && oracle.contains('damage to target'))) {
      removal += qty;
    }

    // Wipes
    if (oracle.contains('destroy all') || oracle.contains('exile all')) {
      wipes += qty;
    }

    // Protection
    if (oracle.contains('hexproof') ||
        oracle.contains('indestructible') ||
        oracle.contains('protection from') ||
        oracle.contains('shroud')) {
      protection += qty;
    }
  }

  final avgCmc = nonLands > 0 ? (totalCmcNonLands / nonLands) : 0.0;

  return _DeckMetrics(
    totalCards: total,
    nonLandCards: nonLands,
    landCount: lands,
    commanderCount: commanderCount,
    commanders: commanders,
    averageCmcNonLands: avgCmc,
    rampCount: ramp,
    drawCount: draw,
    removalCount: removal,
    boardWipeCount: wipes,
    protectionCount: protection,
  );
}

Map<String, dynamic> _heuristicAnalysis({
  required String format,
  required String archetype,
  required int? bracket,
  required _DeckMetrics metrics,
}) {
  final maxTotal =
      format == 'commander' ? 100 : (format == 'brawl' ? 60 : null);

  final completionPct = (maxTotal == null || maxTotal == 0)
      ? 1.0
      : (metrics.totalCards / maxTotal).clamp(0.0, 1.0);

  var score = 0;

  // Base: progresso do deck (peso alto para evitar "sinergia alta" em deck incompleto).
  score += (completionPct * 55).round();

  // Commander presente
  if ((format == 'commander' || format == 'brawl') &&
      metrics.commanderCount > 0) {
    score += 5;
  }

  // Terrenos
  if (format == 'commander') {
    score += _bandScore(metrics.landCount,
        idealMin: 34, idealMax: 39, maxPoints: 15);
  } else if (format == 'brawl') {
    score += _bandScore(metrics.landCount,
        idealMin: 22, idealMax: 26, maxPoints: 12);
  } else {
    score += _bandScore(metrics.landCount,
        idealMin: 22, idealMax: 28, maxPoints: 10);
  }

  // Pacote mínimo (ramp/draw/removal)
  score += min(10, (metrics.rampCount * 10 / 10).round());
  score += min(10, (metrics.drawCount * 10 / 10).round());
  score += min(8, (metrics.removalCount * 8 / 8).round());
  score += min(5, (metrics.boardWipeCount * 5 / 2).round());
  score += min(4, (metrics.protectionCount * 4 / 3).round());

  if (archetype.trim().isNotEmpty) score += 5;
  if (bracket != null) score += 2;

  score = score.clamp(0, 100);

  final strengths = <String>[];
  final weaknesses = <String>[];

  strengths.add('Progresso do deck: ${(completionPct * 100).round()}%');
  if (metrics.commanderCount > 0 && metrics.commanders.isNotEmpty) {
    strengths
        .add('Comandante definido: ${metrics.commanders.take(2).join(', ')}');
  }
  if (metrics.rampCount >= 8) strengths.add('Ramp OK (${metrics.rampCount})');
  if (metrics.drawCount >= 8)
    strengths.add('Card draw OK (${metrics.drawCount})');
  if (metrics.removalCount >= 6)
    strengths.add('Remoções OK (${metrics.removalCount})');

  if (maxTotal != null && metrics.totalCards < maxTotal) {
    weaknesses.add('Deck incompleto: ${metrics.totalCards}/$maxTotal');
  }
  if (format == 'commander' && metrics.landCount < 33) {
    weaknesses.add('Poucos terrenos (${metrics.landCount}) — ideal 35-38');
  }
  if (metrics.rampCount < 8)
    weaknesses.add('Falta ramp (${metrics.rampCount}) — ideal 10-12');
  if (metrics.drawCount < 8)
    weaknesses.add('Falta card draw (${metrics.drawCount}) — ideal 10-12');
  if (metrics.removalCount < 6)
    weaknesses.add('Falta remoções (${metrics.removalCount}) — ideal 8+');

  final sText = strengths.join('. ') + '.';
  final wText = weaknesses.isEmpty
      ? 'Nenhuma fraqueza crítica detectada no heurístico.'
      : (weaknesses.join('. ') + '.');

  return {
    'synergy_score': score,
    'strengths': sText,
    'weaknesses': wText,
  };
}

int _bandScore(int value,
    {required int idealMin, required int idealMax, required int maxPoints}) {
  if (value >= idealMin && value <= idealMax) return maxPoints;
  final delta = value < idealMin ? (idealMin - value) : (value - idealMax);
  return max(0, maxPoints - (delta * (maxPoints / 6)).round());
}

Future<Map<String, dynamic>> _aiAnalysis({
  required String apiKey,
  required String format,
  required String archetype,
  required int? bracket,
  required _DeckMetrics metrics,
}) async {
  final systemPrompt = '''
Você é um especialista em Magic: The Gathering e análise de decks.
Gere uma análise curta e objetiva em JSON, seguindo EXATAMENTE este formato:
{
  "synergy_score": 0-100,
  "strengths": "texto curto em PT-BR (2-5 frases)",
  "weaknesses": "texto curto em PT-BR (2-5 frases)"
}
Regras:
- Seja consistente entre execuções: use os mesmos critérios para pontuar.
- Penalize forte decks incompletos (Commander=100, Brawl=60).
- Considere ramp/draw/removal/terrenos/CMC médio.
- Não invente cartas específicas; foque em avaliação do estado atual.
''';

  final maxTotal =
      format == 'commander' ? 100 : (format == 'brawl' ? 60 : null);

  final payload = {
    'format': format,
    'archetype': archetype,
    'bracket': bracket,
    'max_total_cards': maxTotal,
    'metrics': metrics.toJson(),
  };

  final response = await http.post(
    Uri.parse('https://api.openai.com/v1/chat/completions'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': jsonEncode(payload)},
      ],
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('OpenAI error: status=${response.statusCode}');
  }

  final decoded =
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  final content = (((decoded['choices'] as List).first as Map)['message']
      as Map)['content'] as String;
  final json = jsonDecode(content) as Map<String, dynamic>;

  return json;
}

int _clampInt(dynamic value, {required int min, required int max}) {
  final parsed = value is int ? value : int.tryParse('${value ?? ''}');
  if (parsed == null) return min;
  if (parsed < min) return min;
  if (parsed > max) return max;
  return parsed;
}
