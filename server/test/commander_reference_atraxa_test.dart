import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final skipIntegration = Platform.environment['RUN_INTEGRATION_TESTS'] == '1'
      ? null
      : 'Requer servidor rodando (defina RUN_INTEGRATION_TESTS=1).';

  final baseUrl =
      Platform.environment['TEST_API_BASE_URL'] ?? 'http://localhost:8080';

  const testUser = {
    'email': 'test_error_contract@example.com',
    'password': 'TestPassword123!',
    'username': 'test_error_contract_user',
  };

  Map<String, dynamic> decodeJson(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Future<String> getAuthToken() async {
    var response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testUser['email'],
        'password': testUser['password'],
      }),
    );

    if (response.statusCode != 200) {
      final register = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testUser),
      );
      if (register.statusCode != 200 && register.statusCode != 201) {
        throw Exception('Falha ao registrar usuário de teste: ${register.body}');
      }

      response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': testUser['email'],
          'password': testUser['password'],
        }),
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Falha no login de teste: ${response.body}');
    }

    return decodeJson(response)['token'] as String;
  }

  group('Commander reference | Atraxa', () {
    test(
      'returns commander_profile fallback (edhrec/cache) when no MTGTop8 match',
      () async {
        final token = await getAuthToken();

        final uri = Uri.parse(
          '$baseUrl/ai/commander-reference?commander=${Uri.encodeQueryComponent("Atraxa, Praetors' Voice")}&limit=10',
        );
        final response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );

        expect(response.statusCode, equals(200), reason: response.body);
        final body = decodeJson(response);

        final profile = body['commander_profile'];
        expect(profile, isA<Map>(), reason: 'commander_profile ausente');

        final profileMap = (profile as Map).cast<String, dynamic>();
        final source = (profileMap['source'] as String?)?.toLowerCase();
        expect(source, equals('edhrec'));

        final refs = (body['reference_cards'] as List?) ?? const [];
        expect(refs.isNotEmpty, isTrue,
            reason: 'reference_cards vazio para fallback de Atraxa');

        final structure = profileMap['recommended_structure'];
        expect(structure, isA<Map>(), reason: 'recommended_structure ausente');
        final lands = ((structure as Map)['lands'] as num?)?.toInt();
        expect(lands, isNotNull);
        expect(lands! >= 28 && lands <= 42, isTrue,
            reason: 'lands recomendado fora de faixa razoável: $lands');

        final referenceBases = profileMap['reference_bases'];
        expect(referenceBases, isA<Map>(), reason: 'reference_bases ausente');
        final category = ((referenceBases as Map)['category'] as String?) ?? '';
        expect(category, equals('commander_only'));

        final averageTypeDistribution = profileMap['average_type_distribution'];
        expect(averageTypeDistribution, isA<Map>(),
          reason: 'average_type_distribution ausente');
        final avgLand = ((averageTypeDistribution as Map)['land'] as num?)?.toInt();
        expect(avgLand, isNotNull);

        final manaCurve = profileMap['mana_curve'];
        expect(manaCurve, isA<Map>(), reason: 'mana_curve ausente');
        expect((manaCurve as Map).isNotEmpty, isTrue);

        final averageDeckSeed = profileMap['average_deck_seed'];
        expect(averageDeckSeed, isA<List>(), reason: 'average_deck_seed ausente');
        final averageDeckSeedList = (averageDeckSeed as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
        expect(averageDeckSeedList.isNotEmpty, isTrue,
          reason: 'average_deck_seed vazio');
        expect(averageDeckSeedList.first['name'], isA<String>());
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
