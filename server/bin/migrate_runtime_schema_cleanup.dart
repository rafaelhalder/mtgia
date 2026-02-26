// ignore_for_file: avoid_print
import '../lib/database.dart';

/// Migração de hardening para remover dependência de DDL em runtime.
///
/// Esta migração consolida todos os objetos que antes eram garantidos durante
/// requisições HTTP (middleware/rotas), evitando lock e latência no request path.
Future<void> main() async {
  final db = Database();
  await db.connect();
  final pool = db.connection;

  print('🔄 Aplicando migração de schema (runtime cleanup)...');

  // Cards: suporte a color identity (Commander)
  await pool.execute('''
    ALTER TABLE cards
    ADD COLUMN IF NOT EXISTS color_identity TEXT[]
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_cards_color_identity
    ON cards USING GIN (color_identity)
  ''');
  print('  ✅ cards.color_identity + índice');

  // Users: campos de perfil/push usados por módulos sociais
  await pool.execute('''
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS display_name TEXT
  ''');
  await pool.execute('''
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT
  ''');
  await pool.execute('''
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS fcm_token TEXT
  ''');
  print('  ✅ users.display_name/avatar_url/fcm_token');

  // Social follows
  await pool.execute('''
    CREATE TABLE IF NOT EXISTS user_follows (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT uq_follow UNIQUE (follower_id, following_id),
      CONSTRAINT chk_no_self_follow CHECK (follower_id != following_id)
    )
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_user_follows_follower
    ON user_follows (follower_id)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_user_follows_following
    ON user_follows (following_id)
  ''');
  print('  ✅ user_follows + índices');

  // Conversations + direct messages
  await pool.execute('''
    CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      last_message_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT chk_no_self_chat CHECK (user_a_id != user_b_id)
    )
  ''');

  await pool.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_pair
    ON conversations (LEAST(user_a_id, user_b_id), GREATEST(user_a_id, user_b_id))
  ''');

  await pool.execute('''
    CREATE TABLE IF NOT EXISTS direct_messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id),
      message TEXT NOT NULL,
      read_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_dm_conversation
    ON direct_messages (conversation_id, created_at DESC)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_dm_unread
    ON direct_messages (conversation_id)
    WHERE read_at IS NULL
  ''');
  print('  ✅ conversations/direct_messages + índices');

  // Notifications
  await pool.execute('''
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      reference_id UUID,
      title TEXT NOT NULL,
      body TEXT,
      read_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON notifications (user_id, created_at DESC)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_notifications_unread
    ON notifications (user_id)
    WHERE read_at IS NULL
  ''');
  print('  ✅ notifications + índices');

  print('✅ Migração concluída.');
  await db.close();
}
