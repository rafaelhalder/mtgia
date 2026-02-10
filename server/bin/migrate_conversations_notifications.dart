// ignore_for_file: avoid_print
import '../lib/database.dart';

/// Migration: Épico 4 (conversations + direct_messages) + Épico 5 (notifications)
Future<void> main() async {
  final db = Database();
  await db.connect();
  final pool = db.connection;

  print('🔄 Criando tabelas de mensagens diretas e notificações...');

  // ─── Épico 4: Conversas ────────────────────────────────────
  await pool.execute('''
    CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      last_message_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT uq_conversation UNIQUE (LEAST(user_a_id, user_b_id), GREATEST(user_a_id, user_b_id)),
      CONSTRAINT chk_no_self_chat CHECK (user_a_id != user_b_id)
    )
  ''');
  print('  ✅ conversations');

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
  print('  ✅ direct_messages');

  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_dm_conversation
    ON direct_messages (conversation_id, created_at DESC)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_dm_unread
    ON direct_messages (conversation_id) WHERE read_at IS NULL
  ''');
  print('  ✅ índices direct_messages');

  // ─── Épico 5: Notificações ─────────────────────────────────
  await pool.execute('''
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type TEXT NOT NULL CHECK (type IN (
        'new_follower',
        'trade_offer_received',
        'trade_accepted',
        'trade_declined',
        'trade_shipped',
        'trade_delivered',
        'trade_completed',
        'trade_message',
        'direct_message'
      )),
      reference_id UUID,
      title TEXT NOT NULL,
      body TEXT,
      read_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  print('  ✅ notifications');

  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON notifications (user_id, created_at DESC)
  ''');
  await pool.execute('''
    CREATE INDEX IF NOT EXISTS idx_notifications_unread
    ON notifications (user_id) WHERE read_at IS NULL
  ''');
  print('  ✅ índices notifications');

  print('✅ Migração completa!');
  await db.close();
}
