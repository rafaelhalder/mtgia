// ignore_for_file: avoid_print
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Migração: cria tabelas do sistema de trades (Épico 3)
/// - trade_offers, trade_items, trade_messages, trade_status_history
///
/// Uso: dart run bin/migrate_trades.dart
void main() async {
  final env = DotEnv()..load(['../.env', '.env']);

  final host = env['DB_HOST'] ?? 'localhost';
  final port = int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432;
  final db = env['DB_NAME'] ?? 'mtg_deckbuilder';
  final user = env['DB_USER'] ?? 'postgres';
  final pass = env['DB_PASSWORD'] ?? env['DB_PASS'] ?? 'postgres';

  print('🔗 Conectando a $host:$port/$db...');

  final pool = Pool.withEndpoints(
    [Endpoint(host: host, port: port, database: db, username: user, password: pass)],
    settings: PoolSettings(
      maxConnectionCount: 2,
      sslMode: SslMode.disable,
    ),
  );

  try {
    // ─── trade_offers ───────────────────────────────────────
    print('📦 Criando tabela trade_offers...');
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS trade_offers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          status TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','accepted','declined','shipped','delivered','completed','cancelled','disputed')),
          type TEXT NOT NULL DEFAULT 'trade'
              CHECK (type IN ('trade', 'sale', 'mixed')),
          delivery_method TEXT
              CHECK (delivery_method IS NULL OR delivery_method IN ('correios', 'motoboy', 'pessoalmente', 'outro')),
          payment_method TEXT
              CHECK (payment_method IS NULL OR payment_method IN ('pix', 'cash', 'transfer', 'other')),
          payment_amount DECIMAL(10,2),
          payment_currency TEXT DEFAULT 'BRL',
          tracking_code TEXT,
          message TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT chk_no_self_trade CHECK (sender_id != receiver_id)
      )
    ''');

    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_sender ON trade_offers (sender_id)');
    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_receiver ON trade_offers (receiver_id)');
    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_status ON trade_offers (status)');
    print('  ✅ trade_offers OK');

    // ─── trade_items ────────────────────────────────────────
    print('📦 Criando tabela trade_items...');
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS trade_items (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
          binder_item_id UUID NOT NULL REFERENCES user_binder_items(id) ON DELETE RESTRICT,
          owner_id UUID NOT NULL REFERENCES users(id),
          direction TEXT NOT NULL CHECK (direction IN ('offering', 'requesting')),
          quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
          agreed_price DECIMAL(10,2)
      )
    ''');

    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_items_offer ON trade_items (trade_offer_id)');
    print('  ✅ trade_items OK');

    // ─── trade_messages ─────────────────────────────────────
    print('📦 Criando tabela trade_messages...');
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS trade_messages (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
          sender_id UUID NOT NULL REFERENCES users(id),
          message TEXT,
          attachment_url TEXT,
          attachment_type TEXT
              CHECK (attachment_type IS NULL OR attachment_type IN ('receipt','tracking','photo','other')),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_messages_offer ON trade_messages (trade_offer_id)');
    print('  ✅ trade_messages OK');

    // ─── trade_status_history ───────────────────────────────
    print('📦 Criando tabela trade_status_history...');
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS trade_status_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
          old_status TEXT,
          new_status TEXT NOT NULL,
          changed_by UUID NOT NULL REFERENCES users(id),
          notes TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await pool.execute('CREATE INDEX IF NOT EXISTS idx_trade_history_offer ON trade_status_history (trade_offer_id)');
    print('  ✅ trade_status_history OK');

    print('\n🎉 Migração de trades concluída com sucesso!');
  } catch (e) {
    print('❌ Erro na migração: $e');
    exit(1);
  } finally {
    await pool.close();
  }
}
