import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  print('--- Analisando APP (Flutter) ---');
  analyzeProject(
    projectRoot: '../app',
    packageName: 'manaloom',
    entryPoints: ['lib/main.dart'],
  );

  print('\n--- Analisando SERVER (Dart Frog) ---');
  // Para o server, consideramos todos os arquivos em routes/ como entry points,
  // além de bin/server.dart (se existisse, mas aqui o foco é lib/)
  // Na verdade, em Dart Frog, o que está em lib/ só é usado se importado por routes/ ou outros arquivos de lib/.
  // Então vamos coletar todos os arquivos de routes/ como entry points.
  
  final serverRoutes = Directory('../server/routes')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => path.relative(f.path, from: '../server').replaceAll('\\', '/'))
      .toList();

  analyzeProject(
    projectRoot: '../server',
    packageName: 'server',
    entryPoints: serverRoutes,
  );
}

void analyzeProject({
  required String projectRoot,
  required String packageName,
  required List<String> entryPoints,
}) {
  final libDir = Directory(path.join(projectRoot, 'lib'));
  if (!libDir.existsSync()) {
    print('Pasta lib não encontrada em $projectRoot');
    return;
  }

  // 1. Listar todos os arquivos Dart em lib/
  final allFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => path.relative(f.path, from: projectRoot).replaceAll('\\', '/'))
      .toSet();

  // 2. Construir grafo de dependências
  final usedFiles = <String>{};
  final queue = <String>[...entryPoints];
  final processed = <String>{};

  while (queue.isNotEmpty) {
    final currentRelPath = queue.removeLast();
    if (processed.contains(currentRelPath)) continue;
    processed.add(currentRelPath);

    // Se o arquivo está em lib/, marcamos como usado
    if (currentRelPath.startsWith('lib/')) {
      usedFiles.add(currentRelPath);
    }

    final file = File(path.join(projectRoot, currentRelPath));
    if (!file.existsSync()) continue;

    try {
      final content = file.readAsStringSync();
      final imports = _parseImports(content);

      for (final import in imports) {
        String? resolvedPath;

        if (import.startsWith('package:$packageName/')) {
          // Import de pacote absoluto: package:manaloom/features/... -> lib/features/...
          resolvedPath = import.replaceFirst('package:$packageName/', 'lib/');
        } else if (!import.startsWith('package:') && !import.startsWith('dart:')) {
          // Import relativo: ../utils.dart
          final currentDir = path.dirname(currentRelPath);
          final absolutePath = path.normalize(path.join(currentDir, import)).replaceAll('\\', '/');
          resolvedPath = absolutePath;
        }

        if (resolvedPath != null && !processed.contains(resolvedPath)) {
          // Só adiciona à fila se o arquivo existir
          if (File(path.join(projectRoot, resolvedPath)).existsSync()) {
            queue.add(resolvedPath);
          }
        }
      }
    } catch (e) {
      print('Erro ao ler $currentRelPath: $e');
    }
  }

  // 3. Calcular diferença
  final unusedFiles = allFiles.difference(usedFiles);

  if (unusedFiles.isEmpty) {
    print('✅ Nenhum arquivo não utilizado encontrado em lib/.');
  } else {
    print('⚠️ Arquivos potencialmente não utilizados em lib/:');
    for (final file in unusedFiles) {
      print(' - $file');
    }
  }
}

final _importRegex = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
final _partRegex = RegExp(r'''^\s*part\s+['"]([^'"]+)['"]''', multiLine: true);

List<String> _parseImports(String content) {
  final imports = <String>[];
  
  for (final match in _importRegex.allMatches(content)) {
    imports.add(match.group(1)!);
  }
  
  // Também precisamos seguir 'part' directives, pois são parte do mesmo arquivo lógico
  for (final match in _partRegex.allMatches(content)) {
    imports.add(match.group(1)!);
  }
  
  return imports;
}
