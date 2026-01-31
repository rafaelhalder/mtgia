import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/decks/models/deck.dart';

void main() {
  group('Deck Model', () {
    test('fromJson deve parsear corretamente um deck completo', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'name': 'Meu Deck de Commander',
        'format': 'commander',
        'description': 'Deck de teste',
        'archetype': 'aggro',
        'bracket': 2,
        'synergy_score': 85,
        'strengths': 'Rápido',
        'weaknesses': 'Fraco contra controle',
        'is_public': true,
        'created_at': '2025-01-30T10:00:00Z',
        'card_count': 100,
      };

      final deck = Deck.fromJson(json);

      expect(deck.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(deck.name, 'Meu Deck de Commander');
      expect(deck.format, 'commander');
      expect(deck.description, 'Deck de teste');
      expect(deck.archetype, 'aggro');
      expect(deck.bracket, 2);
      expect(deck.synergyScore, 85);
      expect(deck.isPublic, true);
      expect(deck.cardCount, 100);
    });

    test('fromJson deve lidar com campos opcionais nulos', () {
      final json = {
        'id': '123',
        'name': 'Deck Simples',
        'format': 'standard',
        'is_public': false,
        'created_at': '2025-01-30T10:00:00Z',
      };

      final deck = Deck.fromJson(json);

      expect(deck.id, '123');
      expect(deck.name, 'Deck Simples');
      expect(deck.format, 'standard');
      expect(deck.description, isNull);
      expect(deck.archetype, isNull);
      expect(deck.bracket, isNull);
      expect(deck.synergyScore, isNull);
      expect(deck.isPublic, false);
      expect(deck.cardCount, 0);
    });

    test('toJson deve serializar corretamente', () {
      final deck = Deck(
        id: '456',
        name: 'Test Deck',
        format: 'modern',
        description: 'Test',
        isPublic: true,
        createdAt: DateTime.parse('2025-01-30T10:00:00Z'),
        cardCount: 60,
      );

      final json = deck.toJson();

      expect(json['id'], '456');
      expect(json['name'], 'Test Deck');
      expect(json['format'], 'modern');
      expect(json['description'], 'Test');
      expect(json['is_public'], true);
    });
  });
}
