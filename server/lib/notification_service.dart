import 'package:postgres/postgres.dart';

import 'push_notification_service.dart';

/// Serviço helper para criar notificações de forma consistente.
/// Usado nos handlers de follow, trade, e mensagens.
/// Agora também envia push notification via FCM (se configurado).
class NotificationService {
  /// Cria uma notificação para o usuário destino.
  /// Também envia push notification se o usuário tem FCM token.
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

      // Envia push notification em background (não bloqueia)
      PushNotificationService.sendToUser(
        pool: pool,
        userId: userId,
        title: title,
        body: body,
        data: {
          'type': type,
          if (referenceId != null) 'reference_id': referenceId,
        },
      );
    } catch (e) {
      print('[⚠️ NotificationService] Falha ao criar notificação: $e');
    }
  }
}
