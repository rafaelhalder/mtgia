import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/card_resolution_support.dart';

/// POST /cards/resolve/batch
///
/// Resolve múltiplos nomes de cartas em uma única chamada.
///
/// Body:
/// {
///   "names": ["Sol Ring", "Command Tower", "Arcane Signet"]
/// }
///
/// Response 200:
/// {
///   "data": [
///     {"input_name": "Sol Ring", "card_id": "...", "matched_name": "Sol Ring"}
///   ],
///   "unresolved": ["Unknown Card"],
///   "total_input": 3,
///   "total_resolved": 2
/// }
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final pool = context.read<Pool>();

  final rawBody = await context.request.body();
  if (rawBody.trim().isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Body vazio. Envie {"names": ["Card Name"]}'},
    );
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(rawBody) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'JSON inválido'},
    );
  }

  final namesRaw = body['names'];
  if (namesRaw is! List) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Campo "names" deve ser uma lista de strings'},
    );
  }

  final names = namesRaw
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  if (names.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Campo "names" não pode ser vazio'},
    );
  }

  // Evita payloads enormes e protege o banco.
  if (names.length > 200) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Máximo de 200 nomes por requisição'},
    );
  }

  try {
    final result = await pool.execute(
      Sql.named('''
        WITH input_names AS (
          SELECT DISTINCT TRIM(n) AS input_name
          FROM unnest(@names::text[]) AS n
          WHERE TRIM(n) <> ''
        )
        SELECT
          i.input_name,
          c.card_id,
          c.candidate_name
        FROM input_names i
        LEFT JOIN LATERAL (
          SELECT card_id, candidate_name
          FROM (
            SELECT DISTINCT ON (c.name)
              c.id::text AS card_id,
              c.name AS candidate_name,
              CASE
                WHEN LOWER(c.name) = LOWER(i.input_name) THEN 0
                WHEN LOWER(c.name) LIKE LOWER(i.input_name) || '%' THEN 1
                ELSE 2
              END AS rank
            FROM cards c
            WHERE c.name ILIKE '%' || i.input_name || '%'
            ORDER BY c.name, rank ASC, c.id ASC
          ) ranked
          ORDER BY rank ASC, candidate_name ASC
          LIMIT 5
        ) c ON TRUE
        ORDER BY i.input_name ASC
      '''),
      parameters: {
        'names': TypedValue(Type.textArray, names),
      },
    );

    final resolved = <Map<String, dynamic>>[];
    final unresolved = <String>[];
    final ambiguous = <Map<String, dynamic>>[];
    final candidateNamesByInput = <String, List<String>>{};
    final representativeCardIdByInput = <String, Map<String, String>>{};

    for (final row in result) {
      final map = row.toColumnMap();
      final inputName = (map['input_name'] as String?)?.trim();
      if (inputName == null || inputName.isEmpty) continue;
      final candidateName = (map['candidate_name'] as String?)?.trim();
      final cardId = (map['card_id'] as String?)?.trim();

      if (candidateName == null || candidateName.isEmpty) {
        candidateNamesByInput.putIfAbsent(inputName, () => <String>[]);
      } else {
        candidateNamesByInput.putIfAbsent(inputName, () => <String>[]).add(
              candidateName,
            );
        if (cardId != null && cardId.isNotEmpty) {
          representativeCardIdByInput.putIfAbsent(
              inputName, () => <String, String>{})[candidateName] = cardId;
        }
      }
    }

    for (final inputName in names.toSet()) {
      final decision = resolveCardCandidateNames(
        inputName,
        candidateNamesByInput[inputName] ?? const <String>[],
      );

      if (decision.isResolved) {
        final matchedName = decision.matchedName!;
        final cardId =
            representativeCardIdByInput[inputName]?[matchedName]?.trim();
        if (cardId == null || cardId.isEmpty) {
          unresolved.add(inputName);
          continue;
        }

        resolved.add({
          'input_name': inputName,
          'card_id': cardId,
          'matched_name': matchedName,
          'strategy': decision.strategy,
        });
        continue;
      }

      if (decision.isAmbiguous) {
        ambiguous.add({
          'input_name': inputName,
          'candidates': decision.candidateNames,
        });
        continue;
      }

      unresolved.add(inputName);
    }

    unresolved.sort();
    ambiguous.sort((a, b) {
      final left = a['input_name']?.toString() ?? '';
      final right = b['input_name']?.toString() ?? '';
      return left.compareTo(right);
    });

    return Response.json(
      body: {
        'data': resolved,
        'unresolved': unresolved,
        'ambiguous': ambiguous,
        'total_input': names.length,
        'total_resolved': resolved.length,
        'total_ambiguous': ambiguous.length,
      },
    );
  } catch (e) {
    print('[ERROR] Erro no resolve batch: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao resolver cartas em lote'},
    );
  }
}
