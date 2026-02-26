// ignore_for_file: avoid_print
import '../lib/database.dart';

/// Índices para acelerar consultas sociais de usuários/perfis.
Future<void> main() async {
  final db = Database();
  await db.connect();
  final pool = db.connection;

  print('🔄 Aplicando índices de performance social...');

  // Busca e ordenação de usuários
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_users_username_lower
    ON users (LOWER(username))
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_users_display_name_lower
    ON users (LOWER(COALESCE(display_name, '')))
  ''');

  // Contadores e joins usados em comunidade/perfil
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_decks_user_public
    ON decks (user_id, is_public)
  ''');

  // Reforça índices de follows caso ambiente legado não tenha migrado tudo
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_user_follows_follower
    ON user_follows (follower_id)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_user_follows_following
    ON user_follows (following_id)
  ''');

  print('✅ Índices sociais aplicados.');
  await db.close();
}
