import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/messages/providers/message_provider.dart';

void main() {
  group('ConversationUser Model', () {
    test('fromJson deve parsear todos os campos', () {
      final json = {
        'id': 'user-1',
        'username': 'johndoe',
        'display_name': 'John Doe',
        'avatar_url': 'https://img.example.com/avatar.png',
      };

      final user = ConversationUser.fromJson(json);

      expect(user.id, 'user-1');
      expect(user.username, 'johndoe');
      expect(user.displayName, 'John Doe');
      expect(user.avatarUrl, 'https://img.example.com/avatar.png');
    });

    test('fromJson deve usar defaults para campos ausentes', () {
      final json = {
        'id': 'user-2',
      };

      final user = ConversationUser.fromJson(json);

      expect(user.id, 'user-2');
      expect(user.username, '');
      expect(user.displayName, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('label deve preferir displayName', () {
      final user = ConversationUser(
        id: 'u1',
        username: 'john',
        displayName: 'John Doe',
      );

      expect(user.label, 'John Doe');
    });

    test('label deve usar username quando displayName é null', () {
      final user = ConversationUser(
        id: 'u1',
        username: 'john',
      );

      expect(user.label, 'john');
    });
  });

  group('Conversation Model', () {
    test('fromJson deve parsear corretamente com todos os campos', () {
      final json = {
        'id': 'conv-1',
        'other_user': {
          'id': 'user-2',
          'username': 'jane',
          'display_name': 'Jane',
        },
        'last_message': 'Oi, tudo bem?',
        'last_message_sender_id': 'user-2',
        'unread_count': 3,
        'last_message_at': '2025-01-30T10:00:00Z',
        'created_at': '2025-01-28T08:00:00Z',
      };

      final conv = Conversation.fromJson(json);

      expect(conv.id, 'conv-1');
      expect(conv.otherUser.id, 'user-2');
      expect(conv.otherUser.username, 'jane');
      expect(conv.lastMessage, 'Oi, tudo bem?');
      expect(conv.lastMessageSenderId, 'user-2');
      expect(conv.unreadCount, 3);
      expect(conv.lastMessageAt, '2025-01-30T10:00:00Z');
    });

    test('fromJson deve lidar com other_user parcial', () {
      final json = {
        'id': 'conv-2',
        'other_user': {
          'id': 'user-unknown',
        },
        'unread_count': 0,
      };

      final conv = Conversation.fromJson(json);

      expect(conv.id, 'conv-2');
      expect(conv.otherUser.id, 'user-unknown');
      expect(conv.otherUser.username, '');
      expect(conv.lastMessage, isNull);
      expect(conv.unreadCount, 0);
    });

    test('unreadCount default deve ser 0', () {
      final conv = Conversation(
        id: 'c1',
        otherUser: ConversationUser(id: 'u1', username: 'user'),
      );

      expect(conv.unreadCount, 0);
    });
  });

  group('DirectMessage Model', () {
    test('fromJson deve parsear corretamente', () {
      final json = {
        'id': 'msg-1',
        'sender_id': 'user-1',
        'sender_username': 'john',
        'sender_display_name': 'John',
        'sender_avatar_url': 'https://img.com/john.png',
        'message': 'Olá!',
        'read_at': '2025-01-30T10:05:00Z',
        'created_at': '2025-01-30T10:00:00Z',
      };

      final msg = DirectMessage.fromJson(json);

      expect(msg.id, 'msg-1');
      expect(msg.senderId, 'user-1');
      expect(msg.senderUsername, 'john');
      expect(msg.senderDisplayName, 'John');
      expect(msg.senderAvatarUrl, 'https://img.com/john.png');
      expect(msg.message, 'Olá!');
      expect(msg.readAt, '2025-01-30T10:05:00Z');
      expect(msg.createdAt, '2025-01-30T10:00:00Z');
    });

    test('fromJson deve usar defaults para campos ausentes', () {
      final json = {
        'id': 'msg-2',
        'sender_id': 'user-2',
      };

      final msg = DirectMessage.fromJson(json);

      expect(msg.id, 'msg-2');
      expect(msg.senderId, 'user-2');
      expect(msg.senderUsername, isNull);
      expect(msg.senderDisplayName, isNull);
      expect(msg.message, '');
      expect(msg.readAt, isNull);
      expect(msg.createdAt, '');
    });
  });
}
