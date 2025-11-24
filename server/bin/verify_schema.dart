import 'package:postgres/postgres.dart';
import '../lib/database.dart';

void main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    print('Verificando schema do banco de dados...');

    // Definição do schema esperado (Tabela -> Lista de Colunas)
    final expectedSchema = {
      'users': [
        'id', 'username', 'email', 'password_hash', 'created_at'
      ],
      'cards': [
        'id', 'scryfall_id', 'name', 'mana_cost', 'type_line', 'oracle_text', 
        'colors', 'image_url', 'set_code', 'rarity', 'ai_description', 'price', 'created_at'
      ],
      'card_legalities': [
        'id', 'card_id', 'format', 'status'
      ],
      'rules': [
        'id', 'title', 'description', 'category', 'created_at'
      ],
      'decks': [
        'id', 'user_id', 'name', 'format', 'description', 'is_public', 
        'synergy_score', 'strengths', 'weaknesses', 'created_at', 'deleted_at'
      ],
      'deck_cards': [
        'id', 'deck_id', 'card_id', 'quantity', 'is_commander'
      ],
      'deck_matchups': [
        'id', 'deck_id', 'opponent_deck_id', 'win_rate', 'notes', 'updated_at'
      ],
      'battle_simulations': [
        'id', 'deck_a_id', 'deck_b_id', 'winner_deck_id', 'turns_played', 'game_log', 'created_at'
      ],
      'meta_decks': [
        'id', 'format', 'archetype', 'source_url', 'card_list', 'placement', 'created_at'
      ],
    };

    // Busca todas as colunas do banco
    final result = await conn.execute(Sql.named(
      "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public'"
    ));

    final currentSchema = <String, Set<String>>{};

    for (final row in result) {
      final tableName = row[0] as String;
      final columnName = row[1] as String;

      if (!currentSchema.containsKey(tableName)) {
        currentSchema[tableName] = {};
      }
      currentSchema[tableName]!.add(columnName);
    }

    bool hasErrors = false;

    // Comparação
    for (final table in expectedSchema.keys) {
      if (!currentSchema.containsKey(table)) {
        print('❌ Tabela faltando: $table');
        hasErrors = true;
        continue;
      }

      final expectedColumns = expectedSchema[table]!;
      final currentColumns = currentSchema[table]!;

      for (final col in expectedColumns) {
        if (!currentColumns.contains(col)) {
          print('❌ Coluna faltando na tabela $table: $col');
          hasErrors = true;
        }
      }
      
      // Opcional: Verificar colunas extras
      // for (final col in currentColumns) {
      //   if (!expectedColumns.contains(col)) {
      //     print('⚠️ Coluna extra na tabela $table: $col');
      //   }
      // }
    }

    if (!hasErrors) {
      print('✅ O banco de dados está sincronizado com o schema esperado!');
    } else {
      print('⚠️ Foram encontradas divergências no schema.');
    }

  } catch (e) {
    print('Erro ao verificar schema: $e');
  } finally {
    // await db.close(); // Database class doesn't expose close easily on instance but connection is a Pool
    // Assuming script termination closes it or we can just exit.
  }
}
