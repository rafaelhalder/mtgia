import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final host = env['DB_HOST']!;
  final port = int.parse(env['DB_PORT']!);
  final database = env['DB_NAME']!;
  final username = env['DB_USER']!;
  final password = env['DB_PASS']!;
  final jwtSecret = env['JWT_SECRET']!;

  final conn = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final deckId = 'd5e25e80-5c22-42b2-8eb8-59624b1f149a';
  
  // 1. Get User ID
  final result = await conn.execute(
    Sql.named('SELECT user_id FROM decks WHERE id = @id'),
    parameters: {'id': deckId},
  );

  if (result.isEmpty) {
    print('Deck not found in DB.');
    await conn.close();
    return;
  }

  final userId = result.first[0] as String;
  print('User ID: $userId');
  await conn.close();

  // 2. Generate Token
  final jwt = JWT({'id': userId});
  final token = jwt.sign(SecretKey(jwtSecret));
  print('Generated Token.');

  // 3. Call API
  final url = Uri.parse('http://localhost:8080/decks/$deckId');
  print('Calling GET $url ...');
  
  try {
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Status Code: ${response.statusCode}');
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      
      print('Keys: ${json.keys.toList()}');
      print('Stats: ${json['stats']}');
      print('Commander: ${json['commander']}');
      print('Main Board Keys: ${(json['main_board'] as Map).keys.toList()}');
      
      // final encoder = JsonEncoder.withIndent('  ');
      // print(encoder.convert(json));
    } else {
      print('Error: ${response.body}');
    }
  } catch (e) {
    print('Request failed: $e');
  }
}
