import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Migration: Add list_type to user_binder_items + location/trade_notes to users
///
/// Changes:
/// 1. user_binder_items: ADD list_type VARCHAR(4) DEFAULT 'have' CHECK ('have','want')
/// 2. users: ADD location_state VARCHAR(2), location_city VARCHAR(100), trade_notes TEXT
/// 3. Update UNIQUE constraint to include list_type
/// 4. Add index on list_type
Future<void> main() async {
  print('═══════════════════════════════════════════════════════');
  print('  Migration: Binder Have/Want + User Location');
  print('═══════════════════════════════════════════════════════');

  final env = DotEnv(includePlatformEnvironment: true)..load();

  final host = env['DB_HOST'] ?? 'localhost';
  final port = int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432;
  final dbName = env['DB_NAME'] ?? 'mtg';
  final username = env['DB_USER'] ?? 'postgres';
  final password = env['DB_PASS'] ?? '';

  print('[1/6] Conectando ao banco $host:$port/$dbName ...');

  final pool = Pool.withEndpoints(
    [Endpoint(host: host, port: port, database: dbName, username: username, password: password)],
    settings: PoolSettings(
      maxConnectionCount: 2,
      sslMode: SslMode.disable,
    ),
  );

  try {
    // Test connection
    await pool.execute(Sql.named('SELECT 1'));
    print('[✓] Conexão estabelecida');

    // 1. Add list_type column to user_binder_items
    print('\n[2/6] Adicionando coluna list_type a user_binder_items ...');
    try {
      await pool.execute(Sql.named('''
        ALTER TABLE user_binder_items
        ADD COLUMN IF NOT EXISTS list_type VARCHAR(4) NOT NULL DEFAULT 'have'
      '''));
      print('[✓] Coluna list_type adicionada (ou já existia)');
    } catch (e) {
      print('[!] list_type: $e');
    }

    // 2. Add CHECK constraint for list_type
    print('\n[3/6] Adicionando CHECK constraint para list_type ...');
    try {
      // First check if constraint exists
      final checkResult = await pool.execute(Sql.named('''
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'chk_list_type' 
        AND table_name = 'user_binder_items'
      '''));
      if (checkResult.isEmpty) {
        await pool.execute(Sql.named('''
          ALTER TABLE user_binder_items
          ADD CONSTRAINT chk_list_type CHECK (list_type IN ('have', 'want'))
        '''));
        print('[✓] CHECK constraint chk_list_type adicionada');
      } else {
        print('[✓] CHECK constraint chk_list_type já existe');
      }
    } catch (e) {
      print('[!] CHECK constraint: $e');
    }

    // 3. Update UNIQUE constraint to include list_type
    print('\n[4/6] Atualizando UNIQUE constraint para incluir list_type ...');
    try {
      // Drop old constraint if exists
      await pool.execute(Sql.named('''
        ALTER TABLE user_binder_items
        DROP CONSTRAINT IF EXISTS user_binder_items_user_id_card_id_condition_is_foil_key
      '''));
      // Create new constraint including list_type
      final uniqueCheck = await pool.execute(Sql.named('''
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'uq_binder_user_card_cond_foil_list' 
        AND table_name = 'user_binder_items'
      '''));
      if (uniqueCheck.isEmpty) {
        await pool.execute(Sql.named('''
          ALTER TABLE user_binder_items
          ADD CONSTRAINT uq_binder_user_card_cond_foil_list 
          UNIQUE (user_id, card_id, condition, is_foil, list_type)
        '''));
        print('[✓] UNIQUE constraint atualizada com list_type');
      } else {
        print('[✓] UNIQUE constraint já existe');
      }
    } catch (e) {
      print('[!] UNIQUE constraint: $e');
    }

    // 4. Add index on list_type
    print('\n[5/6] Criando índice em list_type ...');
    try {
      await pool.execute(Sql.named('''
        CREATE INDEX IF NOT EXISTS idx_binder_list_type 
        ON user_binder_items (user_id, list_type)
      '''));
      print('[✓] Índice idx_binder_list_type criado');
    } catch (e) {
      print('[!] Index: $e');
    }

    // 5. Add location + trade_notes to users table
    print('\n[6/6] Adicionando colunas de localização e notas de troca a users ...');
    try {
      await pool.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS location_state VARCHAR(2)',
      ));
      await pool.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS location_city VARCHAR(100)',
      ));
      await pool.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS trade_notes TEXT',
      ));
      print('[✓] Colunas location_state, location_city, trade_notes adicionadas');
    } catch (e) {
      print('[!] User columns: $e');
    }

    // Verify
    print('\n─── Verificação ───');
    final verifyBinder = await pool.execute(Sql.named('''
      SELECT column_name, data_type, column_default 
      FROM information_schema.columns 
      WHERE table_name = 'user_binder_items' AND column_name = 'list_type'
    '''));
    if (verifyBinder.isNotEmpty) {
      final col = verifyBinder.first.toColumnMap();
      print('[✓] user_binder_items.list_type: ${col['data_type']} default=${col['column_default']}');
    }

    final verifyUser = await pool.execute(Sql.named('''
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'users' AND column_name IN ('location_state', 'location_city', 'trade_notes')
      ORDER BY column_name
    '''));
    for (final row in verifyUser) {
      final col = row.toColumnMap();
      print('[✓] users.${col['column_name']}: ${col['data_type']}');
    }

    print('\n═══════════════════════════════════════════════════════');
    print('  Migration concluída com sucesso! ✅');
    print('═══════════════════════════════════════════════════════');
  } catch (e) {
    print('\n[FATAL] Erro na migration: $e');
  } finally {
    await pool.close();
  }
}
