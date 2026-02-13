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

    if (deckId == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'deck_id is required'},
      );
    }

    // 1. Fetch Deck Data
    final pool = context.read<Pool>();
    
    // Get Deck Info
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format, description FROM decks WHERE id = @id'),
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
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      // Mock response for development without API Key
      return Response.json(body: {
        'options': [
          {
            'id': 'aggro',
            'title': 'Aggro / Token Swarm',
            'description': 'Focar em criar muitas criaturas pequenas e atacar rápido.',
            'difficulty': 'Baixa'
          },
          {
            'id': 'control',
            'title': 'Control / Stax',
            'description': 'Controlar o campo de batalha e impedir os oponentes de jogar.',
            'difficulty': 'Alta'
          },
          {
            'id': 'combo',
            'title': 'Combo',
            'description': 'Montar uma combinação específica de cartas para vencer em um turno.',
            'difficulty': 'Média'
          }
        ],
        'is_mock': true
      });
    }

    final prompt = '''
    Analise este deck de Magic: The Gathering ($deckFormat).
    Nome: $deckName
    Comandante(s): ${commanders.join(', ')}
    Lista (amostra): ${otherCards.take(30).join(', ')}... (total ${otherCards.length} cartas)

    Identifique 3 caminhos estratégicos distintos (arquétipos) para otimizar este deck, baseados no comandante e nas cores.
    Retorne APENAS um JSON válido com o seguinte formato, sem markdown:
    {
      "options": [
        {
          "id": "string_curta_identificadora",
          "title": "Nome do Arquétipo (ex: Aristocrats, Voltron)",
          "description": "Breve explicação do foco estratégico (max 2 frases).",
          "difficulty": "Baixa/Média/Alta"
        }
      ]
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
          {
            'role': 'system',
            'content': 'Você é um especialista em construção de decks de Magic: The Gathering. Responda sempre em JSON.'
          },
          {
            'role': 'user',
            'content': prompt
          }
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices'][0]['message']['content'] as String;
      
      // Tenta limpar markdown se houver (```json ... ```)
      String jsonStr = content;
      if (content.contains('```json')) {
        jsonStr = content.split('```json')[1].split('```')[0].trim();
      } else if (content.contains('```')) {
        jsonStr = content.split('```')[1].split('```')[0].trim();
      }

      final jsonResult = jsonDecode(jsonStr);
      return Response.json(body: jsonResult);
    } else {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'OpenAI API Error: ${response.statusCode}'},
      );
    }

  } catch (e) {
    print('[ERROR] Failed to analyze archetypes: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to analyze archetypes'},
    );
  }
}
