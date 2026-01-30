import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';

Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method == HttpMethod.post) {
    return _generateRecommendations(context, deckId);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _generateRecommendations(RequestContext context, String deckId) async {
  final pool = context.read<Pool>();
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final apiKey = env['OPENAI_API_KEY'];

  if (apiKey == null) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'OpenAI API Key not configured.'},
    );
  }

  try {
    // 1. Buscar dados do deck
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format, description FROM decks WHERE id = @deckId'),
      parameters: {'deckId': deckId},
    );

    if (deckResult.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Deck not found'});
    }

    final deck = deckResult.first.toColumnMap();
    final deckName = deck['name'];
    final format = deck['format'];
    final description = deck['description'] ?? '';

    // 2. Buscar lista de cartas (apenas nomes para economizar tokens)
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, dc.quantity 
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    final cardList = cardsResult.map((row) {
      final data = row.toColumnMap();
      return "${data['quantity']}x ${data['name']}";
    }).join(', ');

    // 3. Construir o Prompt para a IA
    final prompt = '''
      You are a professional Magic: The Gathering deck builder expert.
      Analyze the following deck and provide recommendations.
      
      Deck Name: $deckName
      Format: $format
      Description: $description
      Cards: $cardList
      
      Task:
      1. Identify the deck's archetype and main strategy.
      2. Suggest 5 cards to ADD that improve synergy or cover weaknesses.
      3. Suggest 5 cards to REMOVE that are weak or don't fit.
      4. Rate the deck's power level (1-10) for casual play.
      
      Output strictly in JSON format:
      {
        "archetype": "string",
        "power_level": number,
        "analysis": "string (brief summary)",
        "recommendations": {
          "add": [ {"card_name": "string", "reason": "string"} ],
          "remove": [ {"card_name": "string", "reason": "string"} ]
        }
      }
    ''';

    // 4. Chamar a API da OpenAI
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo', // Ou gpt-4 se disponível/necessário
        'messages': [
          {'role': 'system', 'content': 'You are a helpful assistant that outputs JSON.'},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode != 200) {
      return Response.json(
        statusCode: response.statusCode,
        body: {'error': 'OpenAI API Error: ${response.body}'},
      );
    }

    final aiData = jsonDecode(utf8.decode(response.bodyBytes));
    final content = aiData['choices'][0]['message']['content'];
    
    // Tentar fazer o parse do JSON retornado pela IA
    try {
      final recommendations = jsonDecode(content);
      return Response.json(body: recommendations);
    } catch (e) {
      // Fallback se a IA não retornar JSON válido
      return Response.json(body: {'raw_response': content});
    }

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to generate recommendations: $e'},
    );
  }
}
