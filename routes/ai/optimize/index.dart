import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;
    final archetype = body['archetype'] as String?;

    if (deckId == null || archetype == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'deck_id and archetype are required'},
      );
    }

    // 1. Fetch Deck Data
    final pool = context.read<Pool>();
    
    // Get Deck Info
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );
    
    if (deckResult.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Deck not found'});
    }
    
    final deckName = deckResult.first[0] as String;
    final deckFormat = deckResult.first[1] as String;

    // Get Cards
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, dc.is_commander 
        FROM deck_cards dc 
        JOIN cards c ON c.id = dc.card_id 
        WHERE dc.deck_id = @id
      '''),
      parameters: {'id': deckId},
    );

    final commanders = <String>[];
    final otherCards = <String>[];

    for (final row in cardsResult) {
      final name = row[0] as String;
      final isCmdr = row[1] as bool;
      if (isCmdr) {
        commanders.add(name);
      } else {
        otherCards.add(name);
      }
    }

    // 2. Prepare Prompt
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      // Mock response for development
      return Response.json(body: {
        'removals': ['Basic Land', 'Weak Card'],
        'additions': ['Sol Ring', 'Arcane Signet'],
        'reasoning': 'Mock optimization: Adding ramp and removing filler.',
        'is_mock': true
      });
    }

    final prompt = '''
    Atue como um especialista em Magic: The Gathering.
    Tenho um deck de formato $deckFormat chamado "$deckName".
    Comandante(s): ${commanders.join(', ')}
    
    Quero otimizar este deck seguindo este arquétipo/estratégia: "$archetype".
    
    Lista atual de cartas (algumas): ${otherCards.take(50).join(', ')}...
    
    Sua tarefa:
    1. Identifique 3 a 5 cartas da lista atual que NÃO sinergizam bem com a estratégia "$archetype" e devem ser removidas.
    2. Sugira 3 a 5 cartas que DEVEM ser adicionadas para fortalecer essa estratégia (considere cartas populares e eficientes).
    3. Forneça uma breve justificativa.
    
    Responda APENAS um JSON válido (sem markdown, sem ```json) no seguinte formato:
    {
      "removals": ["Nome Exato Carta 1", "Nome Exato Carta 2"],
      "additions": ["Nome Exato Carta A", "Nome Exato Carta B"],
      "reasoning": "Explicação resumida..."
    }
    ''';

    // 3. Call OpenAI
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'system', 'content': 'You are a helpful MTG deck building assistant that outputs only JSON.'},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode != 200) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'OpenAI API error: ${response.body}'},
      );
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final content = data['choices'][0]['message']['content'] as String;
    
    // Clean up potential markdown code blocks if the model ignores instructions
    final cleanContent = content.replaceAll('```json', '').replaceAll('```', '').trim();
    
    try {
      final jsonResponse = jsonDecode(cleanContent);
      return Response.json(body: jsonResponse);
    } catch (e) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Failed to parse AI response', 'raw': content},
      );
    }

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}
