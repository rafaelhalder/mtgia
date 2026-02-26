import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/http_responses.dart';
import '../../../lib/openai_runtime_config.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return methodNotAllowed();
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final cardName = body['card_name'] as String?;
    final oracleText = body['oracle_text'] as String?;
    final typeLine = body['type_line'] as String?;
    final cardId = body['card_id'] as String?;

    if (cardName == null) {
      return badRequest('Card name is required');
    }

    // 1. Check Database Cache
    final pool = context.read<Pool>();
    if (cardId != null) {
      try {
        final result = await pool.execute(
          Sql.named('SELECT ai_description FROM cards WHERE id = @id'),
          parameters: {'id': cardId},
        );
        if (result.isNotEmpty) {
          final description = result.first[0] as String?;
          if (description != null && description.isNotEmpty) {
            return Response.json(body: {
              'explanation': description,
              'is_mock': false,
              'cached': true
            });
          }
        }
      } catch (e) {
        print('[ERROR] handler: $e');
        print('Error checking cache: $e');
      }
    }

    // Carregar variáveis de ambiente
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final aiConfig = OpenAiRuntimeConfig(env);
    final apiKey = env['OPENAI_API_KEY'];

    // Se não tiver chave da API, retorna uma explicação mockada/heurística
    if (apiKey == null || apiKey.isEmpty) {
      return Response.json(
        body: {
          'explanation': _generateFallbackExplanation(cardName, oracleText, typeLine),
          'is_mock': true,
        },
      );
    }

    // Chamada à OpenAI
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': aiConfig.modelFor(
          key: 'OPENAI_MODEL_EXPLAIN',
          fallback: 'gpt-4o-mini',
          devFallback: 'gpt-4o-mini',
          stagingFallback: 'gpt-4o-mini',
          prodFallback: 'gpt-4o-mini',
        ),
        'messages': [
          {
            'role': 'system',
            'content': '''
Você é um juiz experiente e coach de MTG.

Objetivo: explicar cartas de forma didática e acionável para jogadores reais.

Instruções obrigatórias:
1) Responda em PT-BR com Markdown.
2) Estruture em seções curtas:
   - O que a carta faz
   - Como jogar melhor com ela
   - Erros comuns / cuidados
   - Sinergias típicas
3) Seja fiel ao texto Oracle informado; não invente regras não presentes.
4) Se faltar contexto (formato/board state), diga explicitamente a limitação.
5) Evite jargão excessivo sem explicação.
'''
          },
          {
            'role': 'user',
            'content': '''
Carta: $cardName
Tipo: $typeLine
Texto Oracle: $oracleText

Explique esta carta para ajudar o jogador a tomar melhores decisões durante a partida.
'''
          }
        ],
        'temperature': aiConfig.temperatureFor(
          key: 'OPENAI_TEMP_EXPLAIN',
          fallback: 0.5,
          devFallback: 0.55,
          stagingFallback: 0.5,
          prodFallback: 0.45,
        ),
        'max_tokens': 500,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices'][0]['message']['content'] as String;
      
      // 2. Save to Database Cache
      if (cardId != null) {
        try {
          await pool.execute(
            Sql.named('UPDATE cards SET ai_description = @desc WHERE id = @id'),
            parameters: {'desc': content, 'id': cardId},
          );
        } catch (e) {
          print('[ERROR] Failed to call AI provider: ${response.body}: $e');
          print('Failed to cache AI description: $e');
        }
      }

      return Response.json(body: {'explanation': content, 'is_mock': false});
    } else {
      return apiError(
        response.statusCode,
        'Failed to call AI provider: ${response.body}',
      );
    }

  } catch (e) {
    print('[ERROR] Internal server error: $e');
    return internalServerError('Internal server error');
  }
}

String _generateFallbackExplanation(String name, String? text, String? type) {
  return '''
### Explicação Simplificada (Modo Offline)

**$name** é uma carta do tipo **$type**.

${text != null ? 'O texto dela diz: "$text"' : 'Ela não tem texto de regras.'}

*Nota: Para uma explicação detalhada com inteligência artificial, configure a chave da OpenAI no servidor.*
''';
}
