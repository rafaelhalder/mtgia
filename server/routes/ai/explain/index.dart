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
    final cardName = body['card_name'] as String?;
    final oracleText = body['oracle_text'] as String?;
    final typeLine = body['type_line'] as String?;
    final cardId = body['card_id'] as String?;

    if (cardName == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Card name is required'},
      );
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
        print('Error checking cache: $e');
      }
    }

    // Carregar variáveis de ambiente
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
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
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'Você é um juiz experiente de Magic: The Gathering. Explique de forma simples, didática e em Português (PT-BR) como a carta funciona, suas interações principais e por que ela é boa (ou ruim). Use formatação Markdown.'
          },
          {
            'role': 'user',
            'content': 'Carta: $cardName\nTipo: $typeLine\nTexto: $oracleText\n\nExplique esta carta.'
          }
        ],
        'temperature': 0.7,
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
          print('Failed to cache AI description: $e');
        }
      }

      return Response.json(body: {'explanation': content, 'is_mock': false});
    } else {
      return Response.json(
        statusCode: response.statusCode,
        body: {'error': 'Failed to call AI provider: ${response.body}'},
      );
    }

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error: $e'},
    );
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
