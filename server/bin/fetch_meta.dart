import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../lib/database.dart';

// Script para buscar decks do Meta (MTGTop8)
// Uso: dart run bin/fetch_meta.dart [format]
// Se format for 'ALL', busca de todos os formatos principais.

const supportedFormats = {
  'ST': 'Standard',
  'PI': 'Pioneer',
  'MO': 'Modern',
  'LE': 'Legacy',
  'VI': 'Vintage',
  'EDH': 'Duel Commander',
  'cEDH': 'Competitive EDH',
  'PAU': 'Pauper',
  'PREM': 'Premodern',
};

void main(List<String> args) async {
  final inputFormat = args.isNotEmpty ? args[0] : 'ST';
  final baseUrl = 'https://www.mtgtop8.com';
  
  final formatsToProcess = inputFormat == 'ALL' 
      ? supportedFormats.keys.toList() 
      : [inputFormat];

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    for (final formatCode in formatsToProcess) {
      if (!supportedFormats.containsKey(formatCode)) {
        print('Formato desconhecido: $formatCode. Pulando...');
        continue;
      }

      print('\n=== Iniciando crawler para ${supportedFormats[formatCode]} ($formatCode) ===');

      // 1. Buscar a página principal do formato para pegar os últimos eventos
      final formatUrl = '$baseUrl/format?f=$formatCode';
      print('Acessando $formatUrl...');
      
      final response = await http.get(Uri.parse(formatUrl));
      if (response.statusCode != 200) {
        print('Falha ao acessar MTGTop8 para $formatCode: ${response.statusCode}');
        continue;
      }

      final document = parser.parse(response.body);
      
      // Encontrar links de eventos recentes
      final eventLinks = document.querySelectorAll('a[href*="event?e="]')
          .map((e) => e.attributes['href'])
          .where((href) => href != null)
          .toSet()
          .take(6); // 6 eventos por formato = ~300-400 decks no total

      print('Encontrados ${eventLinks.length} eventos recentes.');

      for (final link in eventLinks) {
        final eventUrl = '$baseUrl/$link';
        print('  -> Processando evento: $eventUrl');
        
        await _processEvent(conn, eventUrl);
        
        sleep(Duration(seconds: 2));
      }
    }

    print('\nCrawler finalizado com sucesso!');

  } catch (e) {
    print('Erro crítico: $e');
  } finally {
    await conn.close();
  }
}

Future<void> _processEvent(dynamic conn, String eventUrl) async {
  try {
    final response = await http.get(Uri.parse(eventUrl));
    final document = parser.parse(response.body);
    
    // MTGTop8 lista os decks na esquerda. Ao clicar, carrega o deck.
    // Mas a página do evento já contém os IDs dos decks nos links.
    // Links de deck: "event?e=XXXXX&d=YYYYY&f=ST"
    
    final rows = document.querySelectorAll('div.hover_tr');
    print('     Encontrados ${rows.length} linhas de decks neste evento.');

    // Processa apenas os Top 8 (ou menos para teste)
    for (final row in rows.take(8)) {
      final link = row.querySelector('a');
      if (link == null || !link.attributes['href']!.contains('&d=')) continue;

      final href = link.attributes['href']!;
      final deckUrl = 'https://www.mtgtop8.com/$href';
      final deckName = link.text.trim();
      
      // Tenta extrair a posição (Rank)
      // Geralmente é o primeiro texto dentro da div.hover_tr ou em uma div filha
      // Estrutura comum: <div>Rank</div> <div><a href>Deck</a></div>
      var placement = '';
      final divs = row.querySelectorAll('div');
      if (divs.isNotEmpty) {
        // O primeiro div costuma ser o rank
        placement = divs.first.text.trim();
      }
      
      // Se não achou em div, tenta pegar o texto direto do row antes do link
      if (placement.isEmpty) {
         // Fallback simples
         placement = '?';
      }

      // Verifica se já importamos
      final exists = await conn.execute(
        Sql.named('SELECT 1 FROM meta_decks WHERE source_url = @url'),
        parameters: {'url': deckUrl},
      );
      
      if (exists.isNotEmpty) {
        print('     [SKIP] Deck já importado: $deckName ($placement)');
        continue;
      }

      print('     [NEW] Importando deck: $deckName ($placement)...');
      
      // Para pegar a lista de texto, o MTGTop8 tem um endpoint de exportação
      // A URL é algo como: mtgtop8.com/mtgo?d=YYYYY&f=ST
      // Precisamos extrair o ID do deck (d=YYYYY) da URL
      final uri = Uri.parse(deckUrl);
      final deckId = uri.queryParameters['d'];
      
      if (deckId != null) {
        final exportUrl = 'https://www.mtgtop8.com/mtgo?d=$deckId';
        final exportResponse = await http.get(Uri.parse(exportUrl));
        
        if (exportResponse.statusCode == 200) {
          final cardList = exportResponse.body; // O corpo já é o texto do deck
          
          // Salva no banco
          await conn.execute(
            Sql.named('''
            INSERT INTO meta_decks (format, archetype, source_url, card_list, placement)
            VALUES (@format, @archetype, @url, @list, @placement)
            '''),
            parameters: {
              'format': uri.queryParameters['f'] ?? 'Unknown',
              'archetype': deckName, // MTGTop8 usa o nome do arquétipo como link text
              'url': deckUrl,
              'list': cardList,
              'placement': placement,
            },
          );
          print('     [OK] Salvo no banco.');
        }
      }
      
      sleep(Duration(milliseconds: 500)); // Delay entre decks
    }

  } catch (e) {
    print('     Erro ao processar evento: $e');
  }
}
