// ignore_for_file: avoid_print

import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Sistema de Migrações Versionado para MTG IA
/// 
/// Gerencia migrações de banco de dados de forma ordenada e idempotente.
/// Cada migração é executada apenas uma vez e registrada na tabela `schema_migrations`.
/// 
/// Uso: dart run bin/migrate.dart [--status] [--rollback N]
/// 
/// Opções:
///   --status    Mostra o status das migrações
///   --rollback N  Reverte as últimas N migrações (não implementado - apenas placeholder)

// Lista de migrações em ordem cronológica
// Cada migração tem: versão, nome, SQL de up e SQL de down (opcional)
final migrations = <Migration>[
  Migration(
    version: '001',
    name: 'create_ai_logs',
    up: '''
      CREATE TABLE IF NOT EXISTS ai_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        deck_id UUID REFERENCES decks(id) ON DELETE SET NULL,
        endpoint TEXT NOT NULL,
        model TEXT NOT NULL,
        prompt_summary TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        response_summary TEXT,
        success BOOLEAN NOT NULL DEFAULT TRUE,
        error_message TEXT,
        latency_ms INTEGER NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_ai_logs_user ON ai_logs (user_id);
      CREATE INDEX IF NOT EXISTS idx_ai_logs_deck ON ai_logs (deck_id);
      CREATE INDEX IF NOT EXISTS idx_ai_logs_endpoint ON ai_logs (endpoint);
      CREATE INDEX IF NOT EXISTS idx_ai_logs_created ON ai_logs (created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_ai_logs_success ON ai_logs (success);
    ''',
    down: 'DROP TABLE IF EXISTS ai_logs CASCADE;',
  ),
  Migration(
    version: '002',
    name: 'create_critical_indexes',
    up: '''
      CREATE INDEX IF NOT EXISTS idx_cards_name_lower ON cards (LOWER(name));
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX IF NOT EXISTS idx_cards_name_trgm ON cards USING gin (name gin_trgm_ops);
      CREATE INDEX IF NOT EXISTS idx_cards_color_identity_gin ON cards USING gin (color_identity);
      CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id ON deck_cards (deck_id);
      CREATE INDEX IF NOT EXISTS idx_card_legalities_card_format ON card_legalities (card_id, format);
      CREATE INDEX IF NOT EXISTS idx_decks_user_id ON decks (user_id);
      CREATE INDEX IF NOT EXISTS idx_cards_scryfall_id ON cards (scryfall_id);
      CREATE INDEX IF NOT EXISTS idx_cards_type_line ON cards (type_line);
    ''',
    down: '''
      DROP INDEX IF EXISTS idx_cards_name_lower;
      DROP INDEX IF EXISTS idx_cards_name_trgm;
      DROP INDEX IF EXISTS idx_cards_color_identity_gin;
      DROP INDEX IF EXISTS idx_deck_cards_deck_id;
      DROP INDEX IF EXISTS idx_card_legalities_card_format;
      DROP INDEX IF EXISTS idx_decks_user_id;
      DROP INDEX IF EXISTS idx_cards_scryfall_id;
      DROP INDEX IF EXISTS idx_cards_type_line;
    ''',
  ),
  Migration(
    version: '003',
    name: 'add_deck_deleted_at',
    up: '''
      ALTER TABLE decks ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
      CREATE INDEX IF NOT EXISTS idx_decks_deleted_at ON decks (deleted_at) WHERE deleted_at IS NULL;
    ''',
    down: '''
      DROP INDEX IF EXISTS idx_decks_deleted_at;
      ALTER TABLE decks DROP COLUMN IF EXISTS deleted_at;
    ''',
  ),
  Migration(
    version: '004',
    name: 'add_card_price_columns',
    up: '''
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS price_usd DECIMAL(10, 2);
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS price_usd_foil DECIMAL(10, 2);
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS price_updated_at TIMESTAMP WITH TIME ZONE;
      CREATE INDEX IF NOT EXISTS idx_cards_price ON cards (price_usd) WHERE price_usd IS NOT NULL;
    ''',
    down: '''
      DROP INDEX IF EXISTS idx_cards_price;
      ALTER TABLE cards DROP COLUMN IF EXISTS price_usd;
      ALTER TABLE cards DROP COLUMN IF EXISTS price_usd_foil;
      ALTER TABLE cards DROP COLUMN IF EXISTS price_updated_at;
    ''',
  ),
  Migration(
    version: '005',
    name: 'update_battle_simulations',
    up: '''
      ALTER TABLE battle_simulations ADD COLUMN IF NOT EXISTS simulation_type TEXT;
      UPDATE battle_simulations SET simulation_type = 'legacy' WHERE simulation_type IS NULL;
      ALTER TABLE battle_simulations ALTER COLUMN simulation_type SET NOT NULL;
      ALTER TABLE battle_simulations ADD COLUMN IF NOT EXISTS metrics JSONB DEFAULT '{}';
      UPDATE battle_simulations SET metrics = COALESCE(game_log, '{}') WHERE metrics IS NULL OR metrics = '{}';
      CREATE INDEX IF NOT EXISTS idx_battle_sim_deck_a ON battle_simulations (deck_a_id);
      CREATE INDEX IF NOT EXISTS idx_battle_sim_deck_b ON battle_simulations (deck_b_id);
      CREATE INDEX IF NOT EXISTS idx_battle_sim_type ON battle_simulations (simulation_type);
      CREATE INDEX IF NOT EXISTS idx_battle_sim_created ON battle_simulations (created_at DESC);
    ''',
    down: '''
      ALTER TABLE battle_simulations DROP COLUMN IF EXISTS simulation_type;
      ALTER TABLE battle_simulations DROP COLUMN IF EXISTS metrics;
    ''',
  ),
  Migration(
    version: '006',
    name: 'add_card_cmc_column',
    up: '''
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS cmc DECIMAL(4, 1) DEFAULT 0;
      CREATE INDEX IF NOT EXISTS idx_cards_cmc ON cards (cmc);
    ''',
    down: '''
      DROP INDEX IF EXISTS idx_cards_cmc;
      ALTER TABLE cards DROP COLUMN IF EXISTS cmc;
    ''',
  ),
];

class Migration {
  final String version;
  final String name;
  final String up;
  final String? down;

  Migration({
    required this.version,
    required this.name,
    required this.up,
    this.down,
  });

  String get fullName => '${version}_$name';
}

void main(List<String> args) async {
  final showStatus = args.contains('--status');
  
  final env = DotEnv()..load();

  final connection = await Connection.open(
    Endpoint(
      host: env['DB_HOST'] ?? 'localhost',
      database: env['DB_NAME'] ?? 'mtg_db',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASS'] ?? 'postgres',
      port: int.parse(env['DB_PORT'] ?? '5432'),
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    // Criar tabela de controle de migrações
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Buscar migrações já executadas
    final executedResult = await connection.execute(
      'SELECT version FROM schema_migrations ORDER BY version',
    );
    final executedVersions = executedResult.map((r) => r[0] as String).toSet();

    if (showStatus) {
      print('📊 Status das Migrações\n');
      print('${'Versão'.padRight(10)} ${'Nome'.padRight(30)} Status');
      print('-' * 60);
      
      for (final m in migrations) {
        final status = executedVersions.contains(m.version) ? '✅ Executada' : '⬜ Pendente';
        print('${m.version.padRight(10)} ${m.name.padRight(30)} $status');
      }
      
      print('\nTotal: ${migrations.length} migrações');
      print('Executadas: ${executedVersions.length}');
      print('Pendentes: ${migrations.length - executedVersions.length}');
      return;
    }

    // Executar migrações pendentes
    print('🔄 Executando migrações...\n');
    var migratedCount = 0;

    for (final migration in migrations) {
      if (executedVersions.contains(migration.version)) {
        print('⏭️  ${migration.fullName} (já executada)');
        continue;
      }

      print('▶️  Executando ${migration.fullName}...');
      
      try {
        // Executar cada statement da migração separadamente
        final statements = migration.up
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        
        for (final statement in statements) {
          await connection.execute(statement);
        }
        
        // Registrar como executada
        await connection.execute(
          Sql.named('''
            INSERT INTO schema_migrations (version, name)
            VALUES (@version, @name)
            ON CONFLICT (version) DO NOTHING
          '''),
          parameters: {
            'version': migration.version,
            'name': migration.name,
          },
        );
        
        print('   ✅ Sucesso');
        migratedCount++;
      } catch (e) {
        print('   ❌ Erro: $e');
        print('\n⚠️  Migração interrompida. Corrija o erro e execute novamente.');
        exit(1);
      }
    }

    print('\n' + '=' * 50);
    if (migratedCount > 0) {
      print('✅ $migratedCount migração(ões) executada(s) com sucesso!');
    } else {
      print('✅ Banco de dados já está atualizado!');
    }
    print('=' * 50);

  } catch (e) {
    print('❌ Erro na migração: $e');
    exit(1);
  } finally {
    await connection.close();
  }
}
