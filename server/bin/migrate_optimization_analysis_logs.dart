#!/usr/bin/env dart
// ignore_for_file: avoid_print

/// =============================================================================
/// Migration: Create optimization_analysis_logs table
/// =============================================================================
/// 
/// Esta tabela armazena análises detalhadas de cada otimização realizada,
/// servindo como base de aprendizado para melhorar o algoritmo ao longo do tempo.
/// 
/// Uso: dart run bin/migrate_optimization_analysis_logs.dart
/// =============================================================================

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final env = DotEnv()..load();
  
  final pool = Pool.withEndpoints(
    [
      Endpoint(
        host: env['DB_HOST'] ?? 'localhost',
        database: env['DB_NAME'] ?? 'mtg_db',
        username: env['DB_USER'] ?? 'postgres',
        password: env['DB_PASSWORD'] ?? 'postgres',
        port: int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432,
      ),
    ],
    settings: PoolSettings(
      maxConnectionCount: 2,
      sslMode: SslMode.disable,
    ),
  );

  print('🔄 Creating optimization_analysis_logs table...');

  try {
    await pool.execute(Sql('''
      CREATE TABLE IF NOT EXISTS optimization_analysis_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Identificação do teste
        test_run_id UUID NOT NULL,
        test_number INTEGER NOT NULL,
        test_timestamp TIMESTAMPTZ DEFAULT NOW(),
        
        -- Contexto do deck
        commander_name TEXT NOT NULL,
        commander_colors TEXT[] NOT NULL,
        deck_format TEXT DEFAULT 'commander',
        initial_card_count INTEGER NOT NULL,
        final_card_count INTEGER NOT NULL,
        operation_mode TEXT NOT NULL, -- 'optimize' ou 'complete'
        target_archetype TEXT,
        
        -- Decisões da IA
        detected_theme TEXT,
        edhrec_themes TEXT[],
        theme_match BOOLEAN DEFAULT FALSE,
        hybrid_mode_used BOOLEAN DEFAULT FALSE,
        
        -- Métricas de entrada (antes)
        before_avg_cmc FLOAT,
        before_land_count INTEGER,
        before_creature_count INTEGER,
        before_instant_count INTEGER,
        before_sorcery_count INTEGER,
        before_artifact_count INTEGER,
        before_enchantment_count INTEGER,
        before_consistency_score FLOAT,
        before_mana_screw_rate FLOAT,
        before_mana_flood_rate FLOAT,
        before_keep_at_7_rate FLOAT,
        
        -- Métricas de saída (depois)
        after_avg_cmc FLOAT,
        after_land_count INTEGER,
        after_creature_count INTEGER,
        after_instant_count INTEGER,
        after_sorcery_count INTEGER,
        after_artifact_count INTEGER,
        after_enchantment_count INTEGER,
        after_consistency_score FLOAT,
        after_mana_screw_rate FLOAT,
        after_mana_flood_rate FLOAT,
        after_keep_at_7_rate FLOAT,
        
        -- Alterações realizadas
        removals_count INTEGER DEFAULT 0,
        additions_count INTEGER DEFAULT 0,
        removals_list JSONB,
        additions_list JSONB,
        
        -- Validação
        validation_score INTEGER,
        validation_verdict TEXT,
        color_identity_violations INTEGER DEFAULT 0,
        edhrec_validated_count INTEGER DEFAULT 0,
        edhrec_not_validated_count INTEGER DEFAULT 0,
        validation_warnings JSONB,
        
        -- Análise de decisões
        decisions_reasoning JSONB,
        swap_analysis JSONB,
        role_delta JSONB,
        
        -- Performance
        execution_time_ms INTEGER,
        api_calls_count INTEGER DEFAULT 1,
        
        -- Debate/Análise crítica
        effectiveness_score FLOAT, -- 0-100, calculado após análise
        improvements_achieved JSONB,
        potential_issues JSONB,
        alternative_approaches JSONB,
        lessons_learned TEXT,
        
        -- Meta
        algorithm_version TEXT DEFAULT 'v1.1-hybrid',
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
      
      -- Índices para queries de análise
      CREATE INDEX IF NOT EXISTS idx_oal_test_run ON optimization_analysis_logs(test_run_id);
      CREATE INDEX IF NOT EXISTS idx_oal_commander ON optimization_analysis_logs(commander_name);
      CREATE INDEX IF NOT EXISTS idx_oal_mode ON optimization_analysis_logs(operation_mode);
      CREATE INDEX IF NOT EXISTS idx_oal_effectiveness ON optimization_analysis_logs(effectiveness_score);
      CREATE INDEX IF NOT EXISTS idx_oal_timestamp ON optimization_analysis_logs(test_timestamp);
    '''));
    
    print('✅ Table optimization_analysis_logs created successfully!');
    
    // Criar view para análise agregada
    await pool.execute(Sql('''
      CREATE OR REPLACE VIEW optimization_effectiveness_summary AS
      SELECT 
        commander_name,
        operation_mode,
        COUNT(*) as total_tests,
        AVG(effectiveness_score) as avg_effectiveness,
        AVG(validation_score) as avg_validation_score,
        AVG(after_consistency_score - before_consistency_score) as avg_consistency_improvement,
        AVG(after_keep_at_7_rate - before_keep_at_7_rate) as avg_keepable_improvement,
        AVG(execution_time_ms) as avg_execution_time_ms,
        SUM(CASE WHEN hybrid_mode_used THEN 1 ELSE 0 END) as hybrid_mode_count,
        SUM(color_identity_violations) as total_color_violations
      FROM optimization_analysis_logs
      GROUP BY commander_name, operation_mode
      ORDER BY avg_effectiveness DESC;
    '''));
    
    print('✅ View optimization_effectiveness_summary created!');
    
  } catch (e) {
    print('❌ Error: $e');
  } finally {
    await pool.close();
  }
}
