// ignore_for_file: avoid_print
/// Migração para corrigir URLs de imagem das cartas, adicionando o set code
/// para mostrar a arte correta da edição específica.
///
/// Antes:  https://api.scryfall.com/cards/named?exact=Goblin+King&format=image
/// Depois: https://api.scryfall.com/cards/named?exact=Goblin+King&set=10E&format=image

import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final env = DotEnv()..load();
  final dbUrl = env['DATABASE_URL'];
  if (dbUrl == null || dbUrl.isEmpty) {
    print('❌ DATABASE_URL não configurada');
    exit(1);
  }

  print('🔄 Conectando ao banco...');
  final pool = Pool.withEndpoints(
    [Endpoint(uri: Uri.parse(dbUrl))],
    settings: PoolSettings(
      maxConnectionCount: 2,
      sslMode: SslMode.disable,
    ),
  );

  try {
    // Contar cartas que precisam de correção
    final countResult = await pool.execute(
      Sql.named('''
        SELECT COUNT(*) 
        FROM cards 
        WHERE set_code IS NOT NULL 
          AND set_code != ''
          AND image_url NOT LIKE '%&set=%'
      '''),
    );
    final total = (countResult.first[0] as int?) ?? 0;
    print('📊 Cartas a corrigir: $total');

    if (total == 0) {
      print('✅ Todas as URLs já estão corretas!');
      return;
    }

    // Atualizar em batch
    print('🔧 Atualizando URLs de imagem...');
    
    final result = await pool.execute(
      Sql.named('''
        UPDATE cards
        SET image_url = REPLACE(
          image_url,
          '&format=image',
          '&set=' || set_code || '&format=image'
        )
        WHERE set_code IS NOT NULL 
          AND set_code != ''
          AND image_url NOT LIKE '%&set=%'
      '''),
    );

    print('✅ URLs atualizadas: ${result.affectedRows}');

    // Verificar algumas cartas para confirmar
    print('\n🔍 Verificando algumas cartas...');
    final sample = await pool.execute(
      Sql.named('''
        SELECT name, set_code, image_url 
        FROM cards 
        WHERE image_url LIKE '%&set=%' 
        LIMIT 5
      '''),
    );

    for (final row in sample) {
      final map = row.toColumnMap();
      print('  • ${map['name']} (${map['set_code']}): ${map['image_url']}');
    }

    print('\n✅ Migração concluída!');
  } finally {
    await pool.close();
  }
}
