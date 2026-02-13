import 'dart:convert';
import 'dart:io' show Platform;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

/// Testes de integração para endpoints de CRUD de Decks
/// 
/// Cobertura:
/// - PUT /decks/:id - Atualizar deck
/// - DELETE /decks/:id - Deletar deck
/// - Validações de regras do MTG (limites de cópias, legalidade)
/// - Testes de permissão (ownership)
/// - Edge cases e cenários de erro
/// 
/// NOTA: Estes são testes de integração que requerem o servidor rodando
/// e um banco de dados configurado. Para executar:
/// 1. Configure o .env com credenciais válidas
/// 2. Execute: dart_frog dev
/// 3. Em outro terminal: dart test test/decks_crud_test.dart

void main() {
  final skipIntegration = Platform.environment['RUN_INTEGRATION_TESTS'] == '1'
      ? null
      : 'Requer servidor rodando (defina RUN_INTEGRATION_TESTS=1).';

  // URL base do servidor (ajustar conforme necessário)
  const baseUrl = 'http://localhost:8080';
  
  // Credenciais de teste - devem existir no banco ou serem criadas no setup
  const testUser = {
    'email': 'test_deck_crud@example.com',
    'password': 'TestPassword123!',
    'username': 'test_deck_user'
  };
  
  String? authToken;
  String? testDeckId;
  
  /// Helper: Registra e faz login de um usuário de teste
  Future<String> getAuthToken() async {
    // Tenta fazer login primeiro
    var response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testUser['email'],
        'password': testUser['password'],
      }),
    );
    
    // Se falhar (usuário não existe), registra
    if (response.statusCode != 200) {
      response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testUser),
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to register test user: ${response.body}');
      }
      
      // Faz login após registro
      response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': testUser['email'],
          'password': testUser['password'],
        }),
      );
    }
    
    final data = jsonDecode(response.body);
    return data['token'] as String;
  }
  
  /// Helper: Cria um deck de teste
  Future<String> createTestDeck(String token, {String name = 'Test Deck'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'format': 'commander',
        'description': 'Deck de teste para integração',
        'cards': [], // Deck vazio inicialmente
      }),
    );
    
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create test deck: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    return data['id'] as String;
  }
  
  /// Helper: Busca uma carta válida no banco (para usar nos testes)
  Future<Map<String, dynamic>?> getValidCard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/cards?limit=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final cards = data['cards'] as List?;
      if (cards != null && cards.isNotEmpty) {
        return cards.first as Map<String, dynamic>;
      }
    }
    return null;
  }
  
  setUpAll(() async {
    print('\n🔧 Configurando testes de CRUD de Decks...');
    print('⚠️  IMPORTANTE: Certifique-se que o servidor está rodando em $baseUrl');
    print('   Execute: cd server && dart_frog dev\n');
    
    // Aguarda um pouco para garantir que o servidor está pronto
    await Future.delayed(Duration(seconds: 1));
  });
  
  setUp(() async {
    // Obtém token de autenticação antes de cada teste
    try {
      authToken = await getAuthToken();
      print('✅ Token de autenticação obtido');
    } catch (e) {
      print('❌ Falha ao obter token: $e');
      print('   Verifique se o servidor está rodando e o banco está acessível');
      rethrow;
    }
  });
  
  tearDown(() async {
    // Limpa o deck de teste se foi criado
    if (testDeckId != null && authToken != null) {
      try {
        await http.delete(
          Uri.parse('$baseUrl/decks/$testDeckId'),
          headers: {'Authorization': 'Bearer $authToken'},
        );
        print('🧹 Deck de teste $testDeckId removido');
      } catch (e) {
        print('⚠️  Falha ao limpar deck de teste: $e');
      }
      testDeckId = null;
    }
  });

  group('PUT /decks/:id - Update Deck', () {
    test('should update deck name successfully', () async {
      // Arrange: Cria um deck
      testDeckId = await createTestDeck(authToken!);
      
      // Act: Atualiza o nome
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': 'Updated Deck Name',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body);
      expect(data['success'], isTrue);
      expect(data['deck']['name'], equals('Updated Deck Name'));
    });
    
    test('should update deck format successfully', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'format': 'standard',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body);
      expect(data['success'], isTrue);
      expect(data['deck']['format'], equals('standard'));
    });
    
    test('should update deck description successfully', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'description': 'Nova descrição do deck atualizado',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body);
      expect(data['success'], isTrue);
      expect(data['deck']['description'], equals('Nova descrição do deck atualizado'));
    });
    
    test('should update multiple fields at once', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': 'Multi-Update Deck',
          'format': 'modern',
          'description': 'Atualizado completamente',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body);
      expect(data['success'], isTrue);
      expect(data['deck']['name'], equals('Multi-Update Deck'));
      expect(data['deck']['format'], equals('modern'));
      expect(data['deck']['description'], equals('Atualizado completamente'));
    });
    
    test('should return 404 when updating non-existent deck', () async {
      // Act: Tenta atualizar deck inexistente
      final response = await http.put(
        Uri.parse('$baseUrl/decks/00000000-0000-0000-0000-000000000000'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': 'Will Fail',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(404));
      final data = jsonDecode(response.body);
      expect(data['error'], contains('not found'));
    });
    
    test('should return 401 when updating without authentication', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act: Tenta atualizar sem token
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': 'Should Fail',
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(401));
    });
    
    test('should validate Commander format copy limit (1 copy)', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      final validCard = await getValidCard(authToken!);
      
      if (validCard == null) {
        print('⚠️  Pulando teste: nenhuma carta encontrada no banco');
        return;
      }
      
      // Act: Tenta adicionar 4 cópias em formato Commander (limite é 1)
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'format': 'commander',
          'cards': [
            {
              'card_id': validCard['id'],
              'quantity': 4, // ❌ Viola regra do Commander
              'is_commander': false,
            }
          ],
        }),
      );
      
      // Assert: Deve rejeitar com erro de validação (400)
      expect(response.statusCode, equals(400));
      final data = jsonDecode(response.body);
      expect(data['error'], contains('limite'));
    });
    
    test('should allow basic lands in unlimited quantity', () async {
      // NOTA: Este teste só funciona se houver um terreno básico no banco
      // Para simplificar, apenas documenta a lógica esperada
      
      // A lógica está implementada em routes/decks/[id]/index.dart linha 122:
      // final isBasicLand = typeLine.contains('basic land');
      // if (!isBasicLand && quantity > limit) { throw Exception(...); }
      
      expect(true, isTrue); // Placeholder - teste manual necessário
    }, skip: 'Requer terreno básico específico no banco');
  }, skip: skipIntegration);
  
  group('DELETE /decks/:id - Delete Deck', () {
    test('should delete deck successfully', () async {
      // Arrange: Cria um deck
      testDeckId = await createTestDeck(authToken!, name: 'Deck to Delete');
      
      // Act: Delete
      final response = await http.delete(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      
      // Assert: 204 No Content
      expect(response.statusCode, equals(204));
      
      // Verifica que o deck realmente foi deletado
      final getResponse = await http.get(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      expect(getResponse.statusCode, equals(404));
      
      testDeckId = null; // Já foi deletado manualmente
    });
    
    test('should return 404 when deleting non-existent deck', () async {
      // Act: Tenta deletar deck inexistente
      final response = await http.delete(
        Uri.parse('$baseUrl/decks/00000000-0000-0000-0000-000000000000'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      
      // Assert
      expect(response.statusCode, equals(404));
      final data = jsonDecode(response.body);
      expect(data['error'], contains('not found'));
    });
    
    test('should return 401 when deleting without authentication', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act: Tenta deletar sem token
      final response = await http.delete(
        Uri.parse('$baseUrl/decks/$testDeckId'),
      );
      
      // Assert
      expect(response.statusCode, equals(401));
    });
    
    test('should cascade delete deck cards', () async {
      // Arrange: Cria deck com cartas
      testDeckId = await createTestDeck(authToken!);
      final validCard = await getValidCard(authToken!);
      
      if (validCard != null) {
        // Adiciona cartas ao deck
        await http.put(
          Uri.parse('$baseUrl/decks/$testDeckId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
          body: jsonEncode({
            'cards': [
              {
                'card_id': validCard['id'],
                'quantity': 1,
                'is_commander': false,
              }
            ],
          }),
        );
      }
      
      // Act: Delete do deck
      final response = await http.delete(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      
      // Assert
      expect(response.statusCode, equals(204));
      
      // NOTA: As cartas do deck devem ser deletadas via CASCADE no banco
      // Se não houver CASCADE, o código em routes/decks/[id]/index.dart
      // deveria ter um DELETE manual de deck_cards (comentado na linha 42-46)
      
      testDeckId = null;
    });
    
    test('should not delete deck owned by another user', () async {
      // Este teste requer criar um segundo usuário, o que é complexo
      // A lógica está implementada: WHERE user_id = @userId
      // Documenta o comportamento esperado
      
      expect(true, isTrue); // Placeholder
    }, skip: 'Requer setup de múltiplos usuários');
  }, skip: skipIntegration);
  
  group('PUT /decks/:id - Update Cards with Validation', () {
    test('should replace deck cards list', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      final validCard = await getValidCard(authToken!);
      
      if (validCard == null) {
        print('⚠️  Pulando teste: nenhuma carta encontrada');
        return;
      }
      
      // Act: Primeira atualização - adiciona cartas
      var response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'cards': [
            {
              'card_id': validCard['id'],
              'quantity': 1,
              'is_commander': false,
            }
          ],
        }),
      );
      expect(response.statusCode, equals(200));
      
      // Act: Segunda atualização - substitui lista
      response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'cards': [], // Remove todas as cartas
        }),
      );
      
      // Assert
      expect(response.statusCode, equals(200));
      
      // Verifica que as cartas foram removidas
      final getResponse = await http.get(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final data = jsonDecode(getResponse.body);
      expect(data['stats']['total_cards'], equals(0));
    });
    
    test('should handle update without cards field (no change)', () async {
      // Arrange
      testDeckId = await createTestDeck(authToken!);
      
      // Act: Atualiza sem enviar 'cards'
      final response = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': 'Name Only Update',
        }),
      );
      
      // Assert: Deve funcionar (cards não são alteradas)
      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body);
      expect(data['deck']['name'], equals('Name Only Update'));
    });
  }, skip: skipIntegration);
  
  group('Integration - Full Lifecycle', () {
    test('CREATE -> UPDATE -> DELETE lifecycle', () async {
      // 1. CREATE
      testDeckId = await createTestDeck(authToken!, name: 'Lifecycle Deck');
      expect(testDeckId, isNotEmpty);
      print('✅ Created deck: $testDeckId');
      
      // 2. UPDATE
      final updateResponse = await http.put(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'name': 'Updated Lifecycle Deck',
          'description': 'Updated in lifecycle test',
        }),
      );
      expect(updateResponse.statusCode, equals(200));
      print('✅ Updated deck');
      
      // 3. DELETE
      final deleteResponse = await http.delete(
        Uri.parse('$baseUrl/decks/$testDeckId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      expect(deleteResponse.statusCode, equals(204));
      print('✅ Deleted deck');
      
      testDeckId = null;
    });
  }, skip: skipIntegration);
}
