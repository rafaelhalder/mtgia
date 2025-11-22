import 'dart:io';
import '../lib/database.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  print('Iniciando importação das regras do Magic...');
  final db = Database();
  await db.connect();
  final conn = db.connection;

  final file = File('magicrules.txt');
  if (!await file.exists()) {
    print('Erro: Arquivo magicrules.txt não encontrado.');
    return;
  }

  final lines = await file.readAsLines();
  
  String currentCategory = 'General';
  String? currentRuleNumber;
  StringBuffer currentRuleText = StringBuffer();
  
  // Buffer para batch insert
  final batchSize = 500;
  var valueBuffer = <String>[];
  var totalInserted = 0;

  // Regex para identificar padrões
  final majorSectionRegex = RegExp(r'^(\d)\.\s+(.*)'); // "1. Game Concepts"
  final subSectionRegex = RegExp(r'^(\d{3})\.\s+(.*)'); // "100. General"
  final ruleRegex = RegExp(r'^(\d{3}\.\d+[a-z]?)\.?\s+(.*)'); // "100.1. Text..." ou "100.1a Text..."

  print('Processando ${lines.length} linhas...');

  for (var i = 0; i < lines.length; i++) {
    String line = lines[i].trim();
    if (line.isEmpty) continue;

    // 1. Verifica se é uma Seção Principal (Ex: 1. Game Concepts)
    final majorMatch = majorSectionRegex.firstMatch(line);
    if (majorMatch != null) {
      // Se tínhamos uma regra sendo processada, salva ela antes de mudar de categoria
      if (currentRuleNumber != null) {
        _addToBuffer(valueBuffer, currentRuleNumber, currentRuleText.toString(), currentCategory);
        currentRuleNumber = null;
        currentRuleText.clear();
      }
      currentCategory = majorMatch.group(2) ?? 'General';
      continue;
    }

    // 2. Verifica se é uma Sub-Seção (Ex: 100. General)
    final subMatch = subSectionRegex.firstMatch(line);
    if (subMatch != null) {
       if (currentRuleNumber != null) {
        _addToBuffer(valueBuffer, currentRuleNumber, currentRuleText.toString(), currentCategory);
        currentRuleNumber = null;
        currentRuleText.clear();
      }
      // Opcional: Concatenar ou substituir. Vamos substituir para ser mais específico.
      currentCategory = subMatch.group(2) ?? currentCategory;
      continue;
    }

    // 3. Verifica se é uma Regra (Ex: 100.1. Text...)
    final ruleMatch = ruleRegex.firstMatch(line);
    if (ruleMatch != null) {
      // Salva a regra anterior se existir
      if (currentRuleNumber != null) {
        _addToBuffer(valueBuffer, currentRuleNumber, currentRuleText.toString(), currentCategory);
      }
      
      // Inicia nova regra
      currentRuleNumber = ruleMatch.group(1); // "100.1" ou "100.1a"
      currentRuleText.clear();
      currentRuleText.write(ruleMatch.group(2)); // O texto da regra
    } else {
      // 4. Continuação de texto da regra anterior
      if (currentRuleNumber != null) {
        currentRuleText.write('\n$line');
      }
    }

    // Flush do batch se necessário
    if (valueBuffer.length >= batchSize) {
      await _flushBatch(conn, valueBuffer);
      totalInserted += valueBuffer.length;
      valueBuffer.clear();
      stdout.write('\rRegras inseridas: $totalInserted...');
    }
  }

  // Salva a última regra pendente
  if (currentRuleNumber != null) {
    _addToBuffer(valueBuffer, currentRuleNumber, currentRuleText.toString(), currentCategory);
  }

  // Flush final
  if (valueBuffer.isNotEmpty) {
    await _flushBatch(conn, valueBuffer);
    totalInserted += valueBuffer.length;
  }

  print('\n\nImportação concluída! Total de regras: $totalInserted');
  await db.close();
}

void _addToBuffer(List<String> buffer, String? title, String description, String category) {
  if (title == null) return;
  
  // Sanitização para SQL
  final safeTitle = title.replaceAll("'", "''");
  final safeDesc = description.replaceAll("'", "''");
  final safeCat = category.replaceAll("'", "''");
  
  buffer.add("('$safeTitle', '$safeDesc', '$safeCat')");
}

Future<void> _flushBatch(Connection conn, List<String> values) async {
  if (values.isEmpty) return;
  final valuesStr = values.join(',');
  final sql = 'INSERT INTO rules (title, description, category) VALUES $valuesStr';
  await conn.execute(Sql.named(sql));
}
