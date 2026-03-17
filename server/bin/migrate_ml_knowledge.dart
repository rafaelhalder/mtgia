import 'dart:io';
import '../lib/database.dart';

/// Migration para criar as tabelas de conhecimento do sistema ML
///
/// Este sistema implementa "Imitation Learning" - aprendemos com decks
/// bem-sucedidos (meta decks do MTGTop8, EDHREC, MTGGoldfish) para
/// melhorar as sugestões de otimização.
///
/// Tabelas criadas:
/// 1. card_meta_insights - Conhecimento sobre cartas individuais
/// 2. synergy_packages - Combos e sinergias de cartas
/// 3. archetype_patterns - Padrões de construção por arquétipo
/// 4. ml_prompt_feedback - Feedback do usuário para refinar prompts
/// 5. ml_learning_state - Estado do aprendizado (versões, métricas)

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('  MIGRATION: ML Knowledge Tables');
  print('  Data: ${DateTime.now().toIso8601String()}');
  print('═══════════════════════════════════════════════════════════════\n');

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    // 1. Tabela de Insights por Carta
    print('📊 Criando tabela card_meta_insights...');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS card_meta_insights (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        card_name TEXT NOT NULL,
        card_id UUID REFERENCES cards(id) ON DELETE SET NULL,
        
        -- Frequência de uso
        usage_count INTEGER DEFAULT 0,
        meta_deck_count INTEGER DEFAULT 0,
        commander_deck_count INTEGER DEFAULT 0,
        
        -- Contexto de uso
        common_archetypes TEXT[] DEFAULT '{}',
        common_commanders TEXT[] DEFAULT '{}',
        common_formats TEXT[] DEFAULT '{}',
        
        -- Co-ocorrência (cartas que frequentemente aparecem junto)
        top_pairs JSONB DEFAULT '[]',
        
        -- Categorização aprendida
        learned_role TEXT,
        learned_category TEXT,
        
        -- Scores calculados
        versatility_score FLOAT DEFAULT 0.0,
        win_correlation FLOAT,
        
        -- Metadados
        last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        data_source TEXT DEFAULT 'meta_decks',
        
        CONSTRAINT unique_card_insight UNIQUE(card_name)
      )
    ''');
    print('   ✅ card_meta_insights criada\n');

    // 2. Tabela de Sinergias/Combos
    print('🔗 Criando tabela synergy_packages...');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS synergy_packages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Identificação do pacote
        package_name TEXT NOT NULL,
        package_type TEXT NOT NULL CHECK (package_type IN ('combo', 'synergy', 'engine', 'package')),
        
        -- Cartas do pacote (lista de nomes)
        card_names TEXT[] NOT NULL,
        
        -- Contexto
        primary_archetype TEXT,
        supported_formats TEXT[] DEFAULT '{}',
        color_identity TEXT[] DEFAULT '{}',
        
        -- Descrição e uso
        description TEXT,
        strategy_notes TEXT,
        
        -- Estatísticas
        occurrence_count INTEGER DEFAULT 0,
        win_rate_with FLOAT,
        
        -- Metadados
        discovered_from TEXT,
        confidence_score FLOAT DEFAULT 0.5,
        is_verified BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        
        CONSTRAINT unique_package UNIQUE(package_name)
      )
    ''');
    print('   ✅ synergy_packages criada\n');

    // 3. Tabela de Padrões de Arquétipo
    print('🎯 Criando tabela archetype_patterns...');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS archetype_patterns (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Identificação
        archetype TEXT NOT NULL,
        format TEXT NOT NULL,
        
        -- Padrões de construção
        ideal_land_count INTEGER,
        ideal_creature_count INTEGER,
        ideal_spell_count INTEGER,
        ideal_avg_cmc FLOAT,
        
        -- Distribuição de curva de mana
        cmc_distribution JSONB,
        
        -- Cartas típicas por categoria
        typical_ramp TEXT[] DEFAULT '{}',
        typical_draw TEXT[] DEFAULT '{}',
        typical_removal TEXT[] DEFAULT '{}',
        typical_finishers TEXT[] DEFAULT '{}',
        typical_enablers TEXT[] DEFAULT '{}',
        
        -- Core cards (aparecem em >80% dos decks)
        core_cards TEXT[] DEFAULT '{}',
        
        -- Flex slots (cartas intercambiáveis)
        flex_options JSONB DEFAULT '{}',
        
        -- Estratégia
        win_conditions TEXT[] DEFAULT '{}',
        key_synergies TEXT[] DEFAULT '{}',
        
        -- Matchups
        good_against TEXT[] DEFAULT '{}',
        weak_against TEXT[] DEFAULT '{}',
        
        -- Estatísticas
        sample_size INTEGER DEFAULT 0,
        avg_win_rate FLOAT,
        
        -- Metadados
        last_analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        data_sources TEXT[] DEFAULT '{}',
        
        CONSTRAINT unique_archetype_format UNIQUE(archetype, format)
      )
    ''');
    print('   ✅ archetype_patterns criada\n');

    // 4. Tabela de Feedback do Usuário (para refinar prompts)
    print('📝 Criando tabela ml_prompt_feedback...');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS ml_prompt_feedback (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Referência à otimização
        optimization_log_id UUID,
        deck_id UUID,
        user_id UUID,
        
        -- O que foi sugerido
        prompt_version TEXT,
        archetype TEXT,
        commander_name TEXT,
        
        -- Resposta do usuário
        cards_accepted TEXT[] DEFAULT '{}',
        cards_rejected TEXT[] DEFAULT '{}',
        partial_applied BOOLEAN DEFAULT false,
        
        -- Scores
        effectiveness_score INTEGER,
        user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
        
        -- Feedback qualitativo
        user_comment TEXT,
        rejection_reasons JSONB,
        
        -- Contexto de análise
        before_cmc FLOAT,
        after_cmc FLOAT,
        before_lands INTEGER,
        after_lands INTEGER,
        
        -- Timestamp
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    print('   ✅ ml_prompt_feedback criada\n');

    // 5. Tabela de Estado do Aprendizado
    print('🧠 Criando tabela ml_learning_state...');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS ml_learning_state (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Versão do modelo/prompt
        model_version TEXT NOT NULL,
        prompt_template_hash TEXT,
        
        -- Estatísticas agregadas
        total_optimizations INTEGER DEFAULT 0,
        avg_effectiveness_score FLOAT DEFAULT 0.0,
        avg_user_rating FLOAT,
        
        -- Métricas por arquétipo
        archetype_performance JSONB DEFAULT '{}',
        
        -- Aprendizados aplicados
        active_rules JSONB DEFAULT '{}',
        disabled_rules JSONB DEFAULT '{}',
        
        -- A/B Testing
        is_active BOOLEAN DEFAULT true,
        traffic_percentage FLOAT DEFAULT 100.0,
        
        -- Timestamps
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        
        CONSTRAINT unique_model_version UNIQUE(model_version)
      )
    ''');
    print('   ✅ ml_learning_state criada\n');

    // Criar índices para performance
    print('🔍 Criando índices...');

    await conn.execute('''
      CREATE INDEX IF NOT EXISTS idx_card_insights_name 
        ON card_meta_insights(card_name);
      CREATE INDEX IF NOT EXISTS idx_card_insights_usage 
        ON card_meta_insights(usage_count DESC);
      CREATE INDEX IF NOT EXISTS idx_synergy_packages_type 
        ON synergy_packages(package_type);
      CREATE INDEX IF NOT EXISTS idx_synergy_packages_archetype 
        ON synergy_packages(primary_archetype);
      CREATE INDEX IF NOT EXISTS idx_archetype_patterns_format 
        ON archetype_patterns(format);
      CREATE INDEX IF NOT EXISTS idx_ml_feedback_user 
        ON ml_prompt_feedback(user_id);
      CREATE INDEX IF NOT EXISTS idx_ml_feedback_archetype 
        ON ml_prompt_feedback(archetype);
      CREATE INDEX IF NOT EXISTS idx_ml_learning_active 
        ON ml_learning_state(is_active);
    ''');
    print('   ✅ Índices criados\n');

    // Inserir versão inicial do modelo
    print('📌 Inserindo estado inicial do modelo...');
    await conn.execute('''
      INSERT INTO ml_learning_state (model_version, prompt_template_hash)
      VALUES ('v1.0-imitation-learning', 'initial')
      ON CONFLICT (model_version) DO NOTHING
    ''');
    print('   ✅ Estado inicial criado\n');

    print('═══════════════════════════════════════════════════════════════');
    print('  ✅ MIGRATION CONCLUÍDA COM SUCESSO!');
    print('═══════════════════════════════════════════════════════════════');
    print('\n📋 Tabelas criadas:');
    print('   • card_meta_insights    - Conhecimento sobre cartas');
    print('   • synergy_packages      - Combos e sinergias');
    print('   • archetype_patterns    - Padrões por arquétipo');
    print('   • ml_prompt_feedback    - Feedback do usuário');
    print('   • ml_learning_state     - Estado do modelo');
    print('\n🚀 Próximo passo: Execute bin/extract_meta_insights.dart');
  } catch (e, st) {
    print('❌ Erro na migration: $e');
    print(st);
    exit(1);
  } finally {
    await conn.close();
  }
}
