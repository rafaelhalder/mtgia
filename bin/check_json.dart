import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final jsonFile = File('AtomicCards.json');
  final jsonString = await jsonFile.readAsString();
  final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
  final allCardsData = (jsonMap['data'] as Map<String, dynamic>).values.toList();

  if (allCardsData.isNotEmpty) {
    final firstList = allCardsData.first as List<dynamic>;
    final firstCard = firstList.first as Map<String, dynamic>;
    print('JSON First Card Name: ${firstCard['name']}');
    print('JSON First Card Oracle ID: ${firstCard['scryfallOracleId']}');
    print('JSON First Card ID: ${firstCard['scryfallId']}'); // Just in case
  }
}
