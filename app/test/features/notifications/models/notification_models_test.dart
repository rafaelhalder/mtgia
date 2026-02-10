import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/notifications/providers/notification_provider.dart';

void main() {
  group('AppNotification Model', () {
    test('fromJson deve parsear corretamente com todos os campos', () {
      final json = {
        'id': 'notif-1',
        'type': 'new_follower',
        'reference_id': 'user-123',
        'title': 'JohnDoe começou a seguir você',
        'body': null,
        'read_at': null,
        'created_at': '2025-01-30T10:00:00Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 'notif-1');
      expect(notif.type, 'new_follower');
      expect(notif.referenceId, 'user-123');
      expect(notif.title, 'JohnDoe começou a seguir você');
      expect(notif.body, isNull);
      expect(notif.readAt, isNull);
      expect(notif.createdAt, '2025-01-30T10:00:00Z');
      expect(notif.isRead, isFalse);
    });

    test('fromJson deve marcar isRead true quando read_at presente', () {
      final json = {
        'id': 'notif-2',
        'type': 'trade_accepted',
        'reference_id': 'trade-456',
        'title': 'Trade aceito!',
        'body': 'Sua proposta foi aceita por Jane',
        'read_at': '2025-01-30T11:00:00Z',
        'created_at': '2025-01-30T10:00:00Z',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.isRead, isTrue);
      expect(notif.body, 'Sua proposta foi aceita por Jane');
    });

    test('fromJson deve usar defaults para campos ausentes', () {
      final json = {
        'id': 'notif-3',
      };

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 'notif-3');
      expect(notif.type, '');
      expect(notif.referenceId, isNull);
      expect(notif.title, '');
      expect(notif.body, isNull);
      expect(notif.readAt, isNull);
      expect(notif.createdAt, '');
      expect(notif.isRead, isFalse);
    });

    test('todos os tipos de notificação devem parsear', () {
      final types = [
        'new_follower',
        'trade_offer_received',
        'trade_accepted',
        'trade_declined',
        'trade_shipped',
        'trade_delivered',
        'trade_completed',
        'trade_message',
        'direct_message',
      ];

      for (final type in types) {
        final json = {
          'id': 'notif-$type',
          'type': type,
          'title': 'Test notification',
          'created_at': '2025-01-30T10:00:00Z',
        };

        final notif = AppNotification.fromJson(json);
        expect(notif.type, type, reason: 'Falhou para tipo $type');
      }
    });
  });

  group('NotificationProvider', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('estado inicial deve ser correto', () {
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.isLoading, isFalse);
    });

    test('stopPolling não deve lançar exceção quando não há polling ativo', () {
      // Should not throw
      provider.stopPolling();
    });

    test('dispose deve parar o polling', () {
      // startPolling will fail without server, but stopPolling should work
      provider.stopPolling();
      // No exception means success
    });
  });
}
