import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import '../../../lib/database.dart';

/// GET /ai/ml-status
/// 
/// Retorna o status do sistema de Machine Learning (Imitation Learning),
/// incluindo estatísticas das tabelas de conhecimento e métricas de performance.
/// 
/// Response:
/// {
///   "status": "active",
///   "model_version": "v1.0-imitation-learning",
///   "stats": {
///     "card_insights": 1234,
///     "synergy_packages": 567,
///     "archetype_patterns": 45,
///     "feedback_records": 89,
///     "meta_decks_loaded": 200
///   },
///   "performance": {
///     "avg_effectiveness_score": 67.5,
///     "total_optimizations": 150
///   },
///   "last_extraction": "2025-01-15T10:30:00Z"
/// }
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      body: {'error': 'Method not allowed'},
      statusCode: 405,
    );
  }

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    // Verificar se as tabelas existem
    final tablesExist = await _checkTablesExist(conn);
    
    if (!tablesExist) {
      return Response.json(body: {
        'status': 'not_initialized',
        'message': 'ML tables not found. Run: dart run bin/migrate_ml_knowledge.dart',
        'setup_required': true,
      });
    }

    // Buscar estatísticas das tabelas de conhecimento
    final stats = await _getKnowledgeStats(conn);
    
    // Buscar estado do modelo
    final modelState = await _getModelState(conn);
    
    // Buscar métricas de performance
    final performance = await _getPerformanceMetrics(conn);
    
    return Response.json(body: {
      'status': stats['total_knowledge'] > 0 ? 'active' : 'empty',
      'model_version': modelState['model_version'] ?? 'unknown',
      'stats': stats,
      'performance': performance,
      'last_extraction': modelState['last_updated_at'],
      'extraction_stats': modelState['extraction_stats'],
    });

  } catch (e) {
    return Response.json(
      body: {
        'status': 'error',
        'error': e.toString(),
      },
      statusCode: 500,
    );
  }
  // Note: Do not close the connection - Database is a singleton and the pool 
  // should remain open for other requests
}

Future<bool> _checkTablesExist(dynamic conn) async {
  try {
    final result = await conn.execute('''
      SELECT COUNT(*)::int as count FROM information_schema.tables 
      WHERE table_name IN ('card_meta_insights', 'synergy_packages', 'archetype_patterns', 'ml_learning_state')
    ''');
    final count = result.first.toColumnMap()['count'];
    return (count is int ? count : int.tryParse(count.toString()) ?? 0) >= 4;
  } catch (e) {
    print('[ML-Status] Error checking tables: $e');
    return false;
  }
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}

Future<Map<String, dynamic>> _getKnowledgeStats(dynamic conn) async {
  final cardInsights = await conn.execute('SELECT COUNT(*)::int as c FROM card_meta_insights');
  final synergies = await conn.execute('SELECT COUNT(*)::int as c FROM synergy_packages');
  final patterns = await conn.execute('SELECT COUNT(*)::int as c FROM archetype_patterns');
  final feedback = await conn.execute('SELECT COUNT(*)::int as c FROM ml_prompt_feedback');
  final metaDecks = await conn.execute('SELECT COUNT(*)::int as c FROM meta_decks');
  
  final cardCount = _toInt(cardInsights.first.toColumnMap()['c']);
  final synergyCount = _toInt(synergies.first.toColumnMap()['c']);
  final patternCount = _toInt(patterns.first.toColumnMap()['c']);
  final feedbackCount = _toInt(feedback.first.toColumnMap()['c']);
  final metaDeckCount = _toInt(metaDecks.first.toColumnMap()['c']);
  
  return {
    'card_insights': cardCount,
    'synergy_packages': synergyCount,
    'archetype_patterns': patternCount,
    'feedback_records': feedbackCount,
    'meta_decks_loaded': metaDeckCount,
    'total_knowledge': cardCount + synergyCount + patternCount,
  };
}

Future<Map<String, dynamic>> _getModelState(dynamic conn) async {
  try {
    final result = await conn.execute('''
      SELECT model_version, active_rules, last_updated_at
      FROM ml_learning_state
      WHERE is_active = true
      ORDER BY last_updated_at DESC
      LIMIT 1
    ''');
    
    if (result.isEmpty) {
      return {'model_version': 'not_configured'};
    }
    
    final row = result.first.toColumnMap();
    Map<String, dynamic>? extractionStats;
    
    if (row['active_rules'] != null) {
      try {
        final rules = row['active_rules'] is String 
            ? jsonDecode(row['active_rules']) 
            : row['active_rules'];
        extractionStats = rules['extraction_stats'] as Map<String, dynamic>?;
      } catch (_) {}
    }
    
    return {
      'model_version': row['model_version']?.toString(),
      'last_updated_at': row['last_updated_at']?.toString(),
      'extraction_stats': extractionStats,
    };
  } catch (e) {
    return {'model_version': 'error', 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _getPerformanceMetrics(dynamic conn) async {
  try {
    // Buscar métricas de otimizações recentes (últimos 30 dias)
    final result = await conn.execute('''
      SELECT 
        COUNT(*)::int as total_optimizations,
        AVG(effectiveness_score)::float as avg_effectiveness
      FROM optimization_analysis_logs
      WHERE test_timestamp > NOW() - INTERVAL '30 days'
    ''');
    
    if (result.isEmpty) {
      return {'total_optimizations': 0, 'avg_effectiveness_score': null};
    }
    
    final row = result.first.toColumnMap();
    return {
      'total_optimizations': _toInt(row['total_optimizations']),
      'avg_effectiveness_score': row['avg_effectiveness'] != null 
          ? (row['avg_effectiveness'] is num ? (row['avg_effectiveness'] as num).toDouble() : double.tryParse(row['avg_effectiveness'].toString()))
          : null,
    };
  } catch (e) {
    // Se a tabela não existir, retorna zeros
    return {'total_optimizations': 0, 'avg_effectiveness_score': null};
  }
}
