import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';
import '../../../lib/card_validation_service.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final prompt = body['prompt'] as String?;
    final format = body['format'] as String? ?? 'Commander';

    if (prompt == null || prompt.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Prompt is required'},
      );
    }

    // Carregar variáveis de ambiente
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'OpenAI API Key not configured'},
      );
    }

    // 1. RAG: Buscar contexto no Meta (Opcional, mas recomendado)
    // Tenta encontrar decks no meta que tenham palavras-chave do prompt
    final conn = context.read<Connection>();
    String metaContext = '';
    
    try {
      // Extrai palavras-chave simples (remove stop words básicas)
      final keywords = prompt.split(' ')
          .where((w) => w.length > 3)
          .map((w) => "'%${w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}%'")
          .join(' OR archetype ILIKE ');

      if (keywords.isNotEmpty) {
        final metaResult = await conn.execute(
          Sql.named('''
            SELECT archetype, card_list 
            FROM meta_decks 
            WHERE format = @format 
            AND (archetype ILIKE $keywords)
            LIMIT 3
          '''),
          parameters: {
            'format': format == 'Commander' ? 'EDH' : (format == 'Standard' ? 'ST' : format),
          },
        );

        if (metaResult.isNotEmpty) {
          metaContext = 'Here are some successful meta decks for inspiration:\n';
          for (final row in metaResult) {
            metaContext += 'Archetype: ${row[0]}\nList: ${(row[1] as String).substring(0, 200)}...\n\n';
          }
        }
      }
    } catch (e) {
      print('Erro ao buscar contexto do meta: $e');
      // Segue sem contexto
    }

    // 2. Chamada para OpenAI
    final systemPrompt = '''
    You are a world-class Magic: The Gathering deck builder.
    Your goal is to build a competitive, consistent, and legal deck for the format "$format".
    
    Rules:
    1. Return ONLY a JSON object with a "cards" field.
    2. "cards" must be a list of objects with "name" (exact English card name) and "quantity" (integer).
    3. Do not include markdown formatting (like ```json). Just the raw JSON string.
    4. For Commander, ensure exactly 100 cards (1 Commander + 99 Main).
    5. Ensure a good land count (approx 36-38 for Commander).
    ''';

    final userMessage = '''
    Build a deck based on this description: "$prompt".
    
    $metaContext
    ''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini', // Modelo rápido e eficiente
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
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
    var content = aiData['choices'][0]['message']['content'] as String;

    // Limpeza básica se a IA mandar markdown
    content = content.replaceAll('```json', '').replaceAll('```', '').trim();

    final deckList = jsonDecode(content) as Map<String, dynamic>;
    final cards = (deckList['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Validar cartas geradas pela IA
    final pool = context.read<Pool>();
    final validationService = CardValidationService(pool);
    
    // Extrair nomes das cartas e sanitizar
    final cardNames = cards.map((card) {
      final name = card['name'] as String;
      return CardValidationService.sanitizeCardName(name);
    }).toList();
    
    // Validar todas as cartas
    final validation = await validationService.validateCardNames(cardNames);
    
    // Filtrar apenas cartas válidas e reconstruir a lista
    final validCards = <Map<String, dynamic>>[];
    final invalidCards = validation['invalid'] as List<String>;
    
    for (final card in cards) {
      final name = CardValidationService.sanitizeCardName(card['name'] as String);
      
      // Verificar se a carta é válida
      final isValid = (validation['valid'] as List).any((validCard) =>
        (validCard['name'] as String).toLowerCase() == name.toLowerCase()
      );
      
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
        'message': 'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
        'suggestions': validation['suggestions'],
      };
    }

    return Response.json(body: responseBody);

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to generate deck: $e'},
    );
  }
}
