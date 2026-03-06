import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';
import '../../../lib/card_validation_service.dart';
import '../../../lib/http_responses.dart';
import '../../../lib/logger.dart';
import '../../../lib/openai_runtime_config.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return methodNotAllowed();
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final prompt = body['prompt'] as String?;
    final format = body['format'] as String? ?? 'Commander';

    if (prompt == null || prompt.isEmpty) {
      return badRequest('Prompt is required');
    }

    // Carregar variáveis de ambiente
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final aiConfig = OpenAiRuntimeConfig(env);
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      final mockCards = _mockDeckCards(format);
      return Response.json(body: {
        'prompt': prompt,
        'format': format,
        'generated_deck': {'cards': mockCards},
        'meta_context_used': false,
        'is_mock': true,
        'stats': {
          'total_suggested': mockCards.length,
          'valid_cards': mockCards.length,
          'invalid_cards': 0,
        },
        'warnings': {
          'message':
              'OPENAI_API_KEY não configurada. Retornando deck mock para desenvolvimento.',
        },
      });
    }

    // 1. RAG: Buscar contexto no Meta (Opcional, mas recomendado)
    // Tenta encontrar decks no meta que tenham palavras-chave do prompt
    final pool = context.read<Pool>();
    String metaContext = '';

    try {
      // Extrai palavras-chave simples (remove stop words básicas)
      final keywords = prompt
          .split(' ')
          .where((w) => w.length > 3)
          .map((w) => "'%${w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}%'")
          .join(' OR archetype ILIKE ');

      if (keywords.isNotEmpty) {
        final metaResult = await pool.execute(
          Sql.named('''
            SELECT archetype, card_list 
            FROM meta_decks 
            WHERE format = @format 
            AND (archetype ILIKE $keywords)
            LIMIT 3
          '''),
          parameters: {
            'format': format == 'Commander'
                ? 'EDH'
                : (format == 'Standard' ? 'ST' : format),
          },
        );

        if (metaResult.isNotEmpty) {
          metaContext =
              'Here are some successful meta decks for inspiration:\n';
          for (final row in metaResult) {
            metaContext +=
                'Archetype: ${row[0]}\nList: ${(row[1] as String).substring(0, 200)}...\n\n';
          }
        }
      }
    } catch (e) {
      print('[ERROR] handler: $e');
      Log.w('Erro ao buscar contexto do meta: $e');
      // Segue sem contexto
    }

    // 2. Chamada para OpenAI
    final systemPrompt = '''
You are a world-class Magic: The Gathering deck builder and Level 3 judge.
Your goal is to build a competitive, consistent, and fully legal deck for the format "$format".
Think like a judge verifying legality and a pro player maximizing consistency.

Return ONLY a JSON object (no markdown). Use this schema:
{
  "commander": { "name": "Exact English card name" },   // REQUIRED for Commander/Brawl, otherwise omit or null
  "cards": [
    { "name": "Exact English card name", "quantity": 1 }
  ]
}

Format-specific rules:

Commander (EDH):
1. Commander is REQUIRED (a legendary creature or allowed planeswalker).
2. Total must be exactly 100 cards including the commander (1 commander + 99 others).
3. Only 1 copy of each card except basic lands (singleton rule).
4. ALL cards must respect the commander's color identity (rule 903.4): mana symbols in cost + rules text (not reminder text) + color indicator + back faces of MDFCs. Hybrid mana counts as BOTH colors.
5. Do NOT include banned cards in the Commander format.
6. Starting life: 40. This means aggro must be explosive; drain/life-gain scale better.

Brawl:
1. Commander required (legendary creature or planeswalker).
2. Total must be exactly 60 cards including the commander.
3. Singleton (1 copy except basics). Cards must be Standard-legal.

Standard/Pioneer/Modern/Legacy/Vintage/Pauper (60-card formats):
1. Minimum 60 cards in the main deck.
2. Maximum 4 copies of any non-basic-land card.
3. Include 22-26 lands (adjust by curve: aggro ~20-22, midrange ~23-25, control ~25-27).
4. No commander field needed; set "commander" to null.
5. Respect the ban list for the specific format.
6. Pauper: commons only. Vintage: restricted list applies (max 1 copy of restricted cards).

Deck construction guidelines (apply to ALL formats):
- Include a functional mana base: lands that fix colors proportional to pip distribution.
- For Commander: 35-38 lands, 10-12 ramp sources, 10+ card draw, 8-10 removal, 3-4 board wipes.
- For 60-card: 22-26 lands, 4+ removal, adequate draw for the archetype.
- Include 2-3 distinct win conditions (do not rely on a single card to win).
- Mana curve should be smooth: majority of spells at MV 1-3 for aggro, 2-4 for midrange, 2-5 for control.
- Prioritize instant-speed interaction over sorcery-speed when available.
- Use EXACT real card names (English). Do NOT invent card names.
''';

    final userMessage = '''
Build a deck based on this description: "$prompt".
Format: $format.

$metaContext
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': aiConfig.modelFor(
          key: 'OPENAI_MODEL_GENERATE',
          fallback: 'gpt-4o-mini',
          devFallback: 'gpt-4o-mini',
          stagingFallback: 'gpt-4o-mini',
          prodFallback: 'gpt-4o-mini',
        ),
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': aiConfig.temperatureFor(
          key: 'OPENAI_TEMP_GENERATE',
          fallback: 0.4,
          devFallback: 0.45,
          stagingFallback: 0.4,
          prodFallback: 0.35,
        ),
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode != 200) {
      return apiError(response.statusCode, 'OpenAI API Error: ${response.body}');
    }

    final aiData = jsonDecode(utf8.decode(response.bodyBytes));
    var content = aiData['choices'][0]['message']['content'] as String;

    // Limpeza básica se a IA mandar markdown
    content = content.replaceAll('```json', '').replaceAll('```', '').trim();

    final deckList = jsonDecode(content) as Map<String, dynamic>;
    final commanderRaw = deckList['commander'];
    final cards =
        (deckList['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Validar cartas geradas pela IA
    final validationService = CardValidationService(pool);

    // Extrair nomes das cartas e sanitizar
    final cardNames = cards.map((card) {
      final name = card['name'] as String;
      return CardValidationService.sanitizeCardName(name);
    }).toList();

    String? commanderName;
    if (commanderRaw is Map && commanderRaw['name'] != null) {
      commanderName = CardValidationService.sanitizeCardName(
          commanderRaw['name'] as String);
    } else if (commanderRaw is String && commanderRaw.trim().isNotEmpty) {
      commanderName = CardValidationService.sanitizeCardName(commanderRaw);
    }

    // Validar todas as cartas
    final validation = await validationService.validateCardNames(cardNames);
    final commanderValidation = (commanderName == null || commanderName.isEmpty)
        ? null
        : await validationService.validateCardNames([commanderName]);

    // Filtrar apenas cartas válidas e reconstruir a lista
    final validCards = <Map<String, dynamic>>[];
    final invalidCards = validation['invalid'] as List<String>;

    for (final card in cards) {
      final name =
          CardValidationService.sanitizeCardName(card['name'] as String);

      // Verificar se a carta é válida
      final isValid = (validation['valid'] as List).any((validCard) =>
          (validCard['name'] as String).toLowerCase() == name.toLowerCase());

      if (isValid) {
        validCards.add({
          'name': name,
          'quantity': card['quantity'] ?? 1,
        });
      }
    }

    // Preparar resposta
    final responseBody = {
      'prompt': prompt,
      'format': format,
      'generated_deck': {
        if (commanderName != null) 'commander': {'name': commanderName},
        'cards': validCards,
      },
      'meta_context_used': metaContext.isNotEmpty,
      'stats': {
        'total_suggested': cards.length,
        'valid_cards': validCards.length,
        'invalid_cards': invalidCards.length,
      },
    };

    // Adicionar avisos se houver cartas inválidas
    if (invalidCards.isNotEmpty) {
      responseBody['warnings'] = {
        'invalid_cards': invalidCards,
        'message':
            'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
        'suggestions': validation['suggestions'],
      };
    }

    if (commanderValidation != null) {
      responseBody['commander_validation'] = commanderValidation;
    }

    return Response.json(body: responseBody);
  } catch (e) {
    print('[ERROR] Failed to generate deck: $e');
    return internalServerError('Failed to generate deck');
  }
}

List<Map<String, dynamic>> _mockDeckCards(String format) {
  final normalized = format.trim().toLowerCase();
  final isCommander =
      normalized == 'commander' || normalized == 'edh' || normalized == 'brawl';
  final total = isCommander ? 100 : 60;

  final basics = ['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'];
  final per = (total / basics.length).floor();
  final cards = <Map<String, dynamic>>[];

  for (final land in basics) {
    cards.add({'name': land, 'quantity': per});
  }

  var current = cards.fold<int>(0, (sum, c) => sum + (c['quantity'] as int));
  var i = 0;
  while (current < total) {
    cards[i % basics.length]['quantity'] =
        (cards[i % basics.length]['quantity'] as int) + 1;
    current++;
    i++;
  }

  return cards;
}
