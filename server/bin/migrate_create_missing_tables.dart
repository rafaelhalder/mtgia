import 'package:postgres/postgres.dart';
import '../lib/database.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    print('Criando tabelas faltantes...');

    await conn.run((session) async {
      // 10. Tabela de Staples por Formato
      print('Criando tabela format_staples...');
      await session.execute(Sql.named('''
        CREATE TABLE IF NOT EXISTS format_staples (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            card_name TEXT NOT NULL,
            format TEXT NOT NULL,
            archetype TEXT,
            color_identity TEXT[],
            edhrec_rank INTEGER,
            category TEXT,
            scryfall_id UUID,
            is_banned BOOLEAN DEFAULT FALSE,
            last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(card_name, format, archetype)
        )
      '''));
      
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_format_staples_format ON format_staples (format)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_format_staples_archetype ON format_staples (archetype)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_format_staples_color ON format_staples USING GIN (color_identity)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_format_staples_category ON format_staples (category)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_format_staples_rank ON format_staples (edhrec_rank)'));

      // 11. Tabela de Histórico de Sincronização
      print('Criando tabela sync_log...');
      await session.execute(Sql.named('''
        CREATE TABLE IF NOT EXISTS sync_log (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            sync_type TEXT NOT NULL,
            format TEXT,
            records_updated INTEGER DEFAULT 0,
            records_inserted INTEGER DEFAULT 0,
            records_deleted INTEGER DEFAULT 0,
            status TEXT NOT NULL,
            error_message TEXT,
            started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            finished_at TIMESTAMP WITH TIME ZONE
        )
      '''));

      // 12. Tabela de Counters por Arquétipo
      print('Criando tabela archetype_counters...');
      await session.execute(Sql.named('''
        CREATE TABLE IF NOT EXISTS archetype_counters (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            archetype TEXT NOT NULL,
            counter_archetype TEXT,
            hate_cards TEXT[] NOT NULL,
            priority INTEGER DEFAULT 1,
            format TEXT DEFAULT 'commander',
            color_identity TEXT[],
            notes TEXT,
            effectiveness_score INTEGER DEFAULT 5,
            last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      '''));

      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_archetype_counters_archetype ON archetype_counters (archetype)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_archetype_counters_format ON archetype_counters (format)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_archetype_counters_priority ON archetype_counters (priority)'));

      // Inserir dados iniciais de archetype_counters
      print('Inserindo dados iniciais em archetype_counters...');
      await session.execute(Sql.named('''
        INSERT INTO archetype_counters (archetype, hate_cards, priority, notes, effectiveness_score) VALUES
            ('graveyard', ARRAY['Rest in Peace', 'Grafdigger''s Cage', 'Soul-Guide Lantern', 'Leyline of the Void', 'Bojuka Bog', 'Tormod''s Crypt', 'Relic of Progenitus'], 1, 'Essencial contra Muldrotha, Meren, Karador', 9),
            ('artifacts', ARRAY['Collector Ouphe', 'Stony Silence', 'Null Rod', 'Vandalblast', 'Kataki, War''s Wage', 'Energy Flux'], 1, 'Essencial contra Urza, Breya, artifact storm', 8),
            ('tokens', ARRAY['Massacre Wurm', 'Rakdos Charm', 'Illness in the Ranks', 'Virulent Plague', 'Echoing Truth', 'Aetherspouts'], 2, 'Bom contra go-wide strategies', 7),
            ('ramp', ARRAY['Confiscate', 'Collector Ouphe', 'Blood Moon', 'Back to Basics', 'Stranglehold', 'Aven Mindcensor'], 2, 'Contra decks que dependem de ramp excessivo', 6),
            ('combo', ARRAY['Rule of Law', 'Deafening Silence', 'Drannith Magistrate', 'Cursed Totem', 'Linvala, Keeper of Silence', 'Torpor Orb'], 1, 'Essencial contra storm e infinite combos', 9),
            ('enchantments', ARRAY['Tranquil Grove', 'Back to Nature', 'Bane of Progress', 'Aura Shards', 'Primeval Light'], 2, 'Contra enchantress e aura-based strategies', 7),
            ('planeswalkers', ARRAY['The Immortal Sun', 'Vampire Hexmage', 'Hex Parasite', 'Pithing Needle', 'Sorcerous Spyglass'], 2, 'Contra superfriends', 7),
            ('voltron', ARRAY['Maze of Ith', 'Fog Bank', 'Ghostly Prison', 'Propaganda', 'Constant Mists', 'Spore Frog'], 2, 'Contra voltron e commander damage', 6),
            ('control', ARRAY['Cavern of Souls', 'Boseiju, Who Shelters All', 'Destiny Spinner', 'Vexing Shusher', 'Defense Grid'], 2, 'Contra counterspell-heavy decks', 7),
            ('aggro', ARRAY['Ensnaring Bridge', 'Crawlspace', 'Silent Arbiter', 'Meekstone', 'Sphere of Safety'], 2, 'Contra creature aggro', 6)
        ON CONFLICT DO NOTHING
      '''));

      // 13. Tabela de Análise de Fraquezas
      print('Criando tabela deck_weakness_reports...');
      await session.execute(Sql.named('''
        CREATE TABLE IF NOT EXISTS deck_weakness_reports (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            deck_id UUID REFERENCES decks(id) ON DELETE CASCADE,
            weakness_type TEXT NOT NULL,
            severity TEXT NOT NULL,
            description TEXT NOT NULL,
            recommendations TEXT[],
            auto_detected BOOLEAN DEFAULT TRUE,
            addressed BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      '''));

      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_weakness_reports_deck ON deck_weakness_reports (deck_id)'));
      await session.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_weakness_reports_severity ON deck_weakness_reports (severity)'));
    });

    print('✅ Todas as tabelas foram criadas com sucesso!');

  } catch (e) {
    print('❌ Erro ao criar tabelas: $e');
  } finally {
    print('Migração finalizada.');
  }
}
