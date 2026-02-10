import 'package:postgres/postgres.dart';

/// Serviço helper para criar notificações de forma consistente.
/// Usado nos handlers de follow, trade, e mensagens.
class NotificationService {
  /// Cria uma notificação para o usuário destino.
  /// Silencioso: nunca lança exceção (erros são printados no console).
  static Future<void> create({
    required Pool pool,
    required String userId,
    required String type,
    required String title,
    String? body,
    String? referenceId,
  }) async {
    try {
      await pool.execute(
        Sql.named('''
          INSERT INTO notifications (user_id, type, reference_id, title, body)
          VALUES (@userId, @type, @referenceId, @title, @body)
        '''),
        parameters: {
          'userId': userId,
          'type': type,
          'referenceId': referenceId,
          'title': title,
          'body': body,
        },
      );
    } catch (e) {
      print('[⚠️ NotificationService] Falha ao criar notificação: $e');
    }
  }
}
