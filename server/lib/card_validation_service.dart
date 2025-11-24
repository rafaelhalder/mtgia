import 'dart:io';
import 'package:postgres/postgres.dart';
import 'dart:developer' as developer;

/// Serviço de validação de cartas para prevenir alucinações da IA
/// 
/// **Problema:**
/// A IA (GPT) ocasionalmente sugere cartas que não existem ou têm nomes incorretos.
/// Isso é chamado de "hallucination" e pode causar erros no sistema.
/// 
/// **Solução:**
/// Este serviço valida todas as cartas sugeridas pela IA contra o banco de dados
/// antes de aplicá-las ao deck, garantindo que apenas cartas reais sejam usadas.
class CardValidationService {
  final Pool _pool;

  CardValidationService(this._pool);

  /// Valida uma lista de nomes de cartas
  /// Retorna um mapa com:
  /// - `valid`: Lista de cartas válidas com seus IDs
  /// - `invalid`: Lista de nomes de cartas não encontradas
  /// - `suggestions`: Sugestões de cartas similares para nomes inválidos
  Future<Map<String, dynamic>> validateCardNames(List<String> cardNames) async {
    final validCards = <Map<String, dynamic>>[];
    final invalidCards = <String>[];
    final suggestions = <String, List<String>>{};

    for (final cardName in cardNames) {
      final result = await _findCard(cardName);
      
      if (result != null) {
        validCards.add(result);
      } else {
        invalidCards.add(cardName);
        
        // Tentar encontrar cartas similares (fuzzy search)
        final similarCards = await _findSimilarCards(cardName);
        if (similarCards.isNotEmpty) {
          suggestions[cardName] = similarCards;
        }
      }
    }

    return {
      'valid': validCards,
      'invalid': invalidCards,
      'suggestions': suggestions,
    };
  }

  /// Busca uma carta exata pelo nome (case-insensitive)
  Future<Map<String, String>?> _findCard(String cardName) async {
    try {
      final result = await _pool.execute(
        Sql.named(
          'SELECT id, name FROM cards WHERE LOWER(name) = LOWER(@name) LIMIT 1',
        ),
        parameters: {'name': cardName},
      );

      if (result.isNotEmpty) {
        return {
          'id': result.first[0] as String,
          'name': result.first[1] as String,
        };
      }
    } catch (e) {
      developer.log('Erro ao buscar carta $cardName', error: e, name: 'CardValidation');
    }

    return null;
  }

  /// Busca cartas com nomes similares usando LIKE (fuzzy search básico)
  Future<List<String>> _findSimilarCards(String cardName) async {
    try {
      // Remove caracteres especiais e espaços extras
      final cleanName = cardName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
      
      if (cleanName.isEmpty) return [];

      // Busca usando ILIKE com % (similar ao LIKE mas case-insensitive)
      final result = await _pool.execute(
        Sql.named(
          "SELECT name FROM cards WHERE name ILIKE @pattern LIMIT 5",
        ),
        parameters: {'pattern': '%$cleanName%'},
      );

      return result.map((row) => row[0] as String).toList();
    } catch (e) {
      developer.log('Erro ao buscar cartas similares', error: e, name: 'CardValidation');
      return [];
    }
  }

  /// Valida se uma carta é legal em um formato específico
  Future<bool> isCardLegalInFormat(String cardId, String format) async {
    try {
      final result = await _pool.execute(
        Sql.named(
          '''
          SELECT status FROM card_legalities 
          WHERE card_id = @cardId AND format = @format
          LIMIT 1
          ''',
        ),
        parameters: {'cardId': cardId, 'format': format.toLowerCase()},
      );

      if (result.isEmpty) {
        // Se não tem registro de legalidade, assume legal por padrão
        return true;
      }

      final status = result.first[0] as String;
      return status == 'legal' || status == 'restricted';
    } catch (e) {
      developer.log('Erro ao verificar legalidade', error: e, name: 'CardValidation');
      return false; // Por segurança, assume ilegal em caso de erro
    }
  }

  /// Valida uma lista completa de cartas para um deck
  /// Verifica:
  /// - Existência das cartas
  /// - Legalidade no formato
  /// - Limites de quantidade
  Future<Map<String, dynamic>> validateDeckCards(
    List<Map<String, dynamic>> cards,
    String format,
  ) async {
    final errors = <String>[];
    final warnings = <String>[];
    final validatedCards = <Map<String, dynamic>>[];

    for (final card in cards) {
      final cardId = card['card_id'] as String?;
      final quantity = card['quantity'] as int? ?? 1;
      
      if (cardId == null) {
        errors.add('Carta sem ID fornecido');
        continue;
      }

      // Verifica se a carta existe
      final cardInfo = await _getCardInfo(cardId);
      if (cardInfo == null) {
        errors.add('Carta com ID $cardId não encontrada');
        continue;
      }

      // Verifica legalidade
      if (!await isCardLegalInFormat(cardId, format)) {
        errors.add('${cardInfo['name']} não é legal no formato $format');
        continue;
      }

      // Verifica limite de quantidade
      final isBasicLand = (cardInfo['type_line'] as String).toLowerCase().contains('basic land');
      
      if (!isBasicLand) {
        final maxQuantity = (format == 'commander' || format == 'brawl') ? 1 : 4;
        
        if (quantity > maxQuantity) {
          errors.add('${cardInfo['name']} excede o limite de $maxQuantity cópia(s) para o formato $format');
          continue;
        }
      }

      validatedCards.add(card);
    }

    return {
      'valid': validatedCards,
      'errors': errors,
      'warnings': warnings,
      'is_valid': errors.isEmpty,
    };
  }

  /// Busca informações básicas de uma carta
  Future<Map<String, dynamic>?> _getCardInfo(String cardId) async {
    try {
      final result = await _pool.execute(
        Sql.named('SELECT id, name, type_line FROM cards WHERE id = @id LIMIT 1'),
        parameters: {'id': cardId},
      );

      if (result.isNotEmpty) {
        return {
          'id': result.first[0] as String,
          'name': result.first[1] as String,
          'type_line': result.first[2] as String,
        };
      }
    } catch (e) {
      developer.log('Erro ao buscar info da carta', error: e, name: 'CardValidation');
    }

    return null;
  }

  /// Sanitiza e valida nomes de cartas sugeridos pela IA
  /// Remove caracteres especiais, corrige capitalização, etc.
  static String sanitizeCardName(String name) {
    // Remove espaços extras
    var cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove caracteres problemáticos mas mantém aspas e apóstrofos
    // Regex corrigido: hífen no final para evitar escape
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\s\',\-]'), '');
    
    // Capitalização: primeira letra de cada palavra em maiúscula
    cleaned = cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

    return cleaned;
  }
}
