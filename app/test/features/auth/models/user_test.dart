import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/auth/models/user.dart';

void main() {
  group('User Model', () {
    test('fromJson deve parsear todos os campos corretamente', () {
      final json = {
        'id': 'user-123',
        'username': 'johndoe',
        'email': 'john@example.com',
        'display_name': 'John Doe',
        'avatar_url': 'https://img.example.com/avatar.png',
      };

      final user = User.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.username, 'johndoe');
      expect(user.email, 'john@example.com');
      expect(user.displayName, 'John Doe');
      expect(user.avatarUrl, 'https://img.example.com/avatar.png');
    });

    test('fromJson deve lidar com campos opcionais nulos', () {
      final json = {
        'id': 'user-456',
        'username': 'jane',
        'email': 'jane@example.com',
      };

      final user = User.fromJson(json);

      expect(user.id, 'user-456');
      expect(user.username, 'jane');
      expect(user.email, 'jane@example.com');
      expect(user.displayName, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('toJson deve serializar corretamente', () {
      final user = User(
        id: 'u1',
        username: 'test',
        email: 'test@test.com',
        displayName: 'Test User',
        avatarUrl: 'https://avatar.url',
      );

      final json = user.toJson();

      expect(json['id'], 'u1');
      expect(json['username'], 'test');
      expect(json['email'], 'test@test.com');
      expect(json['display_name'], 'Test User');
      expect(json['avatar_url'], 'https://avatar.url');
    });

    test('toJson deve incluir nulos para campos opcionais ausentes', () {
      final user = User(
        id: 'u2',
        username: 'bare',
        email: 'bare@test.com',
      );

      final json = user.toJson();

      expect(json['display_name'], isNull);
      expect(json['avatar_url'], isNull);
    });

    test('fromJson → toJson roundtrip mantém dados', () {
      final original = {
        'id': 'round-trip',
        'username': 'roundtrip',
        'email': 'rt@test.com',
        'display_name': 'RT',
        'avatar_url': 'https://img.com/rt.png',
      };

      final user = User.fromJson(original);
      final result = user.toJson();

      expect(result['id'], original['id']);
      expect(result['username'], original['username']);
      expect(result['email'], original['email']);
      expect(result['display_name'], original['display_name']);
      expect(result['avatar_url'], original['avatar_url']);
    });

    test('copyWith deve substituir campos especificados', () {
      final user = User(
        id: 'u1',
        username: 'test',
        email: 'test@test.com',
        displayName: 'Original',
        avatarUrl: 'https://old.png',
      );

      final updated = user.copyWith(
        displayName: 'Updated Name',
        avatarUrl: 'https://new.png',
      );

      expect(updated.id, 'u1');
      expect(updated.username, 'test');
      expect(updated.email, 'test@test.com');
      expect(updated.displayName, 'Updated Name');
      expect(updated.avatarUrl, 'https://new.png');
    });

    test('copyWith sem argumentos deve manter tudo igual', () {
      final user = User(
        id: 'u1',
        username: 'test',
        email: 'test@test.com',
        displayName: 'DN',
        avatarUrl: 'https://av.png',
      );

      final copy = user.copyWith();

      expect(copy.id, user.id);
      expect(copy.username, user.username);
      expect(copy.email, user.email);
      expect(copy.displayName, user.displayName);
      expect(copy.avatarUrl, user.avatarUrl);
    });
  });
}
