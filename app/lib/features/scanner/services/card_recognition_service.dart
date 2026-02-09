import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/card_recognition_result.dart';

/// Serviço AVANÇADO de reconhecimento de cartas MTG usando ML Kit
/// Múltiplas estratégias de OCR para máxima precisão em TODAS as eras (1993-2026)
///
/// Estratégias implementadas:
/// 1. Processamento da imagem original
/// 2. Crop da região do nome (topo da carta)
/// 3. Alto contraste + sharpening
/// 4. Binarização adaptativa
/// 5. Múltiplas regiões (para layouts não-padrão)
/// 6. Análise por linhas e blocos
class CardRecognitionService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  // ══════════════════════════════════════════════════════════════════════════
  // BANCO DE PALAVRAS PARA FILTRAGEM
  // ══════════════════════════════════════════════════════════════════════════

  /// Palavras que NUNCA são nomes de cartas (filtro negativo)
  static const _nonNameKeywords = <String>{
    // Tipos de carta
    'creature', 'instant', 'sorcery', 'enchantment', 'artifact', 'land',
    'planeswalker', 'legendary', 'tribal', 'snow', 'basic', 'token',
    'world', 'ongoing', 'conspiracy', 'phenomenon', 'plane', 'scheme',
    'vanguard', 'battle', 'kindred',
    // Subtipos muito comuns
    'human', 'wizard', 'soldier', 'elf', 'goblin', 'zombie', 'vampire',
    'dragon', 'angel', 'demon', 'beast', 'elemental', 'spirit', 'knight',
    'merfolk', 'rogue', 'warrior', 'cleric', 'shaman', 'druid', 'ally',
    'bird', 'cat', 'dog', 'wolf', 'bear', 'snake', 'rat', 'spider',
    // Habilidades de palavra-chave (mais completas)
    'flying', 'trample', 'haste', 'vigilance', 'lifelink', 'deathtouch',
    'first strike', 'double strike', 'hexproof', 'indestructible',
    'flash', 'reach', 'menace', 'defender', 'protection', 'shroud',
    'ward', 'prowess', 'cycling', 'kicker', 'flashback', 'equip',
    'intimidate', 'fear', 'shadow', 'flanking', 'banding', 'morph',
    'storm', 'affinity', 'convoke', 'dredge', 'cascade', 'infect',
    'undying', 'persist', 'evolve', 'extort', 'bestow', 'dash',
    'exploit', 'emerge', 'crew', 'fabricate', 'improvise', 'ascend',
    'escape', 'mutate', 'foretell', 'learn', 'disturb', 'decayed',
    'training', 'casualty', 'connive', 'blitz', 'enlist', 'read ahead',
    'toxic', 'for mirrodin', 'backup', 'bargain', 'craft', 'descend',
    // Texto de regras comum
    'tap', 'untap', 'add', 'mana', 'target', 'damage', 'life', 'draw',
    'discard', 'sacrifice', 'destroy', 'exile', 'return', 'counter',
    'copy', 'cast', 'pay', 'controller', 'opponent', 'player', 'owner',
    'permanent', 'spell', 'ability', 'graveyard', 'library', 'hand',
    'battlefield', 'combat', 'attack', 'block', 'tokens', 'enters',
    'leaves', 'dies', 'whenever', 'choose', 'reveal', 'search', 'shuffle',
    'scry', 'surveil', 'mill', 'loot', 'rummage', 'fight', 'proliferate',
    // Texto de edição/colecionador
    'illustrated', 'artist', 'illus', 'wotc', 'wizards', 'reserved',
    'collector', 'number', 'rarity', 'mythic', 'rare', 'uncommon', 'common',
    'foil', 'promo', 'set', 'edition',
  };

  /// Padrões de nomes MTG válidos (validação positiva)
  static final _validNamePatterns = <RegExp>[
    // Nome simples: "Lightning Bolt", "Sol Ring"
    RegExp(r'^[A-Z][a-z]+(\s+[A-Z][a-z]+){0,5}$'),
    // Nome com apóstrofe: "Jace's Ingenuity", "Urza's Tower"
    RegExp(r"^[A-Z][a-z]+'s?\s+[A-Z]"),
    // Nome com hífen: "Will-o'-the-Wisp"
    RegExp(r'^[A-Z][a-z]+-'),
    // Nome com vírgula (títulos): "Emrakul, the Aeons Torn"
    RegExp(r'^[A-Z][a-z]+,\s+'),
    // Nome com "of/the/and": "Wrath of God"
    RegExp(r'^(The\s+)?[A-Z][a-z]+\s+(of|the|and)\s+', caseSensitive: false),
    // Split cards: "Fire // Ice"
    RegExp(r'^[A-Z][a-z]+\s*//\s*[A-Z]'),
  ];

  static const _setCodeStopwords = <String>{
    'THE',
    'AND',
    'FOR',
    'YOU',
    'WITH',
    'FROM',
    'THIS',
    'THAT',
    'NOT',
    'YES',
    'CAN',
    'MAY',
    'ALL',
    'ANY',
    'ONE',
    'TWO',
    'THREE',
    'FOUR',
    'FIVE',
    'SIX',
    'SEVEN',
    'EIGHT',
    'NINE',
    'TEN',
  };

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTODO PRINCIPAL - MÚLTIPLAS ESTRATÉGIAS
  // ══════════════════════════════════════════════════════════════════════════

  /// Reconhece carta usando MÚLTIPLAS estratégias para máxima precisão
  Future<CardRecognitionResult> recognizeCard(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      return CardRecognitionResult.failed('Erro ao decodificar imagem');
    }

    CardRecognitionResult bestResult = CardRecognitionResult.failed(
      'Nenhum resultado',
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ESTRATÉGIA 1: Imagem original (mais rápido, funciona bem em 70% casos)
    // ═══════════════════════════════════════════════════════════════════════
    var result = await _processImage(imageFile, originalImage, 'original');
    if (result.success && result.confidence >= 80) {
      return result; // Alta confiança, retorna direto
    }
    if (result.success && result.confidence > bestResult.confidence) {
      bestResult = result;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ESTRATÉGIA 2: Região do nome apenas (crop topo)
    // ═══════════════════════════════════════════════════════════════════════
    result = await _processNameRegion(originalImage);
    if (result.success && result.confidence >= 85) {
      return result;
    }
    if (result.success && result.confidence > bestResult.confidence) {
      bestResult = result;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ESTRATÉGIA 3: Alto contraste + sharpening
    // ═══════════════════════════════════════════════════════════════════════
    result = await _processWithHighContrast(originalImage);
    if (result.success && result.confidence >= 85) {
      return result;
    }
    if (result.success && result.confidence > bestResult.confidence) {
      bestResult = result;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ESTRATÉGIA 4: Binarização adaptativa (cartas desgastadas/foil)
    // ═══════════════════════════════════════════════════════════════════════
    if (bestResult.confidence < 70) {
      result = await _processWithBinarization(originalImage);
      if (result.success && result.confidence > bestResult.confidence) {
        bestResult = result;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ESTRATÉGIA 5: Múltiplas regiões (layouts não-padrão/showcase)
    // ═══════════════════════════════════════════════════════════════════════
    if (bestResult.confidence < 60) {
      result = await _processMultipleRegions(originalImage);
      if (result.success && result.confidence > bestResult.confidence) {
        bestResult = result;
      }
    }

    return bestResult;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // IMPLEMENTAÇÃO DAS ESTRATÉGIAS
  // ══════════════════════════════════════════════════════════════════════════

  /// Processa a imagem original
  Future<CardRecognitionResult> _processImage(
    File imageFile,
    img.Image image,
    String strategy,
  ) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.blocks.isEmpty) {
        return CardRecognitionResult.failed('Sem texto ($strategy)');
      }

      return _analyzeRecognizedText(
        recognizedText,
        image.width.toDouble(),
        image.height.toDouble(),
        strategy,
      );
    } catch (e) {
      return CardRecognitionResult.failed('Erro ($strategy): $e');
    }
  }

  /// Processa apenas a região do nome (topo da carta)
  Future<CardRecognitionResult> _processNameRegion(img.Image original) async {
    // Calcula região do nome (primeiros ~12% da altura, excluindo mana cost à direita)
    final nameHeight = (original.height * 0.12).round().clamp(40, 250);
    final nameWidth =
        (original.width * 0.70).round(); // Exclui área de mana cost

    var cropped = img.copyCrop(
      original,
      x: (original.width * 0.05).round(),
      y: (original.height * 0.02).round(),
      width: nameWidth,
      height: nameHeight,
    );

    // Pré-processamento otimizado para texto
    cropped = img.grayscale(cropped);
    cropped = img.adjustColor(cropped, contrast: 1.6, brightness: 1.1);
    cropped = _sharpen(cropped);

    return await _processTemporaryImage(cropped, 'name_region');
  }

  /// Processa com alto contraste
  Future<CardRecognitionResult> _processWithHighContrast(
    img.Image original,
  ) async {
    var processed = img.grayscale(original);
    processed = img.adjustColor(processed, contrast: 1.8, brightness: 1.15);
    processed = _sharpen(processed);

    return await _processTemporaryImage(processed, 'high_contrast');
  }

  /// Processa com binarização adaptativa
  Future<CardRecognitionResult> _processWithBinarization(
    img.Image original,
  ) async {
    var processed = img.grayscale(original);
    processed = _adaptiveThreshold(processed, blockSize: 25, constant: 12);

    return await _processTemporaryImage(processed, 'binarized');
  }

  /// Processa múltiplas regiões da carta
  Future<CardRecognitionResult> _processMultipleRegions(
    img.Image original,
  ) async {
    // Regiões para diferentes layouts de carta
    final regions = <_Region>[
      _Region(0.02, 0.02, 0.70, 0.15, 'top_name'), // Nome padrão
      _Region(0.02, 0.05, 0.95, 0.18, 'top_full'), // Topo completo
      _Region(0.10, 0.78, 0.90, 0.95, 'bottom'), // Showcase/borderless
      _Region(0.05, 0.40, 0.95, 0.55, 'middle'), // DFC verso
    ];

    CardRecognitionResult bestResult = CardRecognitionResult.failed(
      'Nenhuma região',
    );

    for (final region in regions) {
      final x = (original.width * region.left).round();
      final y = (original.height * region.top).round();
      final w = ((region.right - region.left) * original.width).round();
      final h = ((region.bottom - region.top) * original.height).round();

      if (w < 50 || h < 20) continue;

      var cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);
      cropped = img.grayscale(cropped);
      cropped = img.adjustColor(cropped, contrast: 1.5);

      final result = await _processTemporaryImage(cropped, region.name);
      if (result.success && result.confidence > bestResult.confidence) {
        bestResult = result;
      }
    }

    return bestResult;
  }

  /// Processa uma imagem temporária
  Future<CardRecognitionResult> _processTemporaryImage(
    img.Image image,
    String strategy,
  ) async {
    File? tempFile;
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${tempDir.path}/mtg_ocr_$timestamp.jpg');
      await tempFile.writeAsBytes(
        Uint8List.fromList(img.encodeJpg(image, quality: 95)),
      );

      final inputImage = InputImage.fromFile(tempFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.blocks.isEmpty) {
        return CardRecognitionResult.failed('Sem texto ($strategy)');
      }

      return _analyzeRecognizedText(
        recognizedText,
        image.width.toDouble(),
        image.height.toDouble(),
        strategy,
      );
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANÁLISE DE TEXTO RECONHECIDO
  // ══════════════════════════════════════════════════════════════════════════

  /// Analisa texto e extrai candidatos a nome de carta
  CardRecognitionResult _analyzeRecognizedText(
    RecognizedText recognizedText,
    double imageWidth,
    double imageHeight,
    String strategy,
  ) {
    final candidates = <CardNameCandidate>[];

    // Processa blocos e linhas
    for (final block in recognizedText.blocks) {
      // Avalia cada linha individualmente
      for (final line in block.lines) {
        final candidate = _evaluateCandidate(
          line.text,
          line.boundingBox,
          imageWidth,
          imageHeight,
        );
        if (candidate != null) candidates.add(candidate);
      }

      // Avalia bloco completo (pode pegar nome com quebra de linha)
      final blockCandidate = _evaluateCandidate(
        block.text,
        block.boundingBox,
        imageWidth,
        imageHeight,
      );
      if (blockCandidate != null) candidates.add(blockCandidate);
    }

    if (candidates.isEmpty) {
      return CardRecognitionResult.failed('Nenhum nome válido ($strategy)');
    }

    // Remove duplicatas e ordena
    final unique = _deduplicate(candidates);
    unique.sort((a, b) => b.score.compareTo(a.score));

    // Calcula confiança
    final confidence = _calculateConfidence(unique);
    final setCodeCandidates = _extractSetCodeCandidates(recognizedText.text);

    return CardRecognitionResult.success(
      primaryName: unique.first.text,
      alternatives:
          unique
              .skip(1)
              .take(5)
              .map((c) => c.text)
              .where((t) => t != unique.first.text)
              .toList(),
      setCodeCandidates: setCodeCandidates,
      confidence: confidence,
      allCandidates: unique,
    );
  }

  List<String> _extractSetCodeCandidates(String rawText) {
    final text = rawText.replaceAll('\n', ' ');
    final matches = RegExp(r'\b[A-Za-z0-9]{2,6}\b').allMatches(text);

    final seen = <String>{};
    final candidates = <String>[];

    for (final m in matches) {
      final token = m.group(0);
      if (token == null) continue;

      final upper = token.toUpperCase();
      if (_setCodeStopwords.contains(upper)) continue;

      // Set codes normalmente têm 3-5 chars ou incluem dígitos (ex: 2XM, M21).
      final hasDigit = upper.contains(RegExp(r'\d'));
      final len = upper.length;
      final looksLikeSetCode = (len >= 3 && len <= 5) || (hasDigit && len <= 6);
      if (!looksLikeSetCode) continue;

      // Evita pegar só números (collector numbers etc).
      if (RegExp(r'^\d+$').hasMatch(upper)) continue;

      // Evita tokens muito "palavra comum" do OCR que já filtramos como não-nome.
      if (_nonNameKeywords.contains(upper.toLowerCase())) continue;

      if (seen.add(upper)) {
        candidates.add(upper);
        if (candidates.length >= 10) break;
      }
    }

    return candidates;
  }

  /// Avalia se um texto é candidato a nome de carta
  CardNameCandidate? _evaluateCandidate(
    String rawText,
    Rect box,
    double imgWidth,
    double imgHeight,
  ) {
    final firstLine = rawText.split('\n').first.trim();
    if (firstLine.length < 2 || firstLine.length > 55) return null;

    final cleaned = _cleanText(firstLine);
    if (cleaned.isEmpty || cleaned.length < 2) return null;

    final score = _calculateScore(cleaned, firstLine, box, imgWidth, imgHeight);
    if (score <= 0) return null;

    return CardNameCandidate(
      text: cleaned,
      rawText: firstLine,
      score: score,
      boundingBox: box,
    );
  }

  /// Calcula score de probabilidade de ser nome de carta
  double _calculateScore(
    String cleaned,
    String original,
    Rect box,
    double imgWidth,
    double imgHeight,
  ) {
    double score = 0.0;
    final lower = cleaned.toLowerCase();

    // ═══════════════════════════════════════════════════════════════════════
    // FILTROS NEGATIVOS (eliminam candidatos ruins)
    // ═══════════════════════════════════════════════════════════════════════

    // Apenas números/símbolos
    if (RegExp(r'^[\d\s\W]+$').hasMatch(cleaned)) return 0;

    // Palavra-chave de regras
    if (_nonNameKeywords.contains(lower)) return 0;
    for (final kw in _nonNameKeywords) {
      if (lower.startsWith('$kw ') || lower.endsWith(' $kw')) {
        score -= 20; // Penalidade mas não elimina
      }
    }

    // Power/Toughness
    if (RegExp(r'^\d+\s*/\s*\d+$').hasMatch(cleaned)) return 0;

    // Custo de mana
    if (RegExp(
      r'^[\dWUBRGCX\{\}\s]+$',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return 0;
    }

    // Texto de regras longo
    if (cleaned.contains(':') && cleaned.length > 25) return 0;

    // Linha de tipo
    if (_isTypeLine(lower)) return 0;

    // ═══════════════════════════════════════════════════════════════════════
    // SCORES POR POSIÇÃO
    // ═══════════════════════════════════════════════════════════════════════

    final relTop = box.top / imgHeight;
    final relLeft = box.left / imgWidth;
    final relWidth = box.width / imgWidth;

    // Topo (0-18%): nome padrão
    if (relTop < 0.18) {
      score += 55;
      if (relTop < 0.10) score += 15;
      if (relLeft < 0.15) score += 12;
      if (relWidth > 0.30 && relWidth < 0.80) score += 8;
    }
    // Inferior (75-95%): showcase/borderless
    else if (relTop > 0.75 && relTop < 0.95) {
      score += 40;
      if (relLeft > 0.10 && relLeft < 0.45) score += 10;
    }
    // Meio-topo (18-35%): alguns layouts
    else if (relTop > 0.18 && relTop < 0.35) {
      score += 20;
    }

    // Penalidade: muito à direita no topo (provavelmente mana)
    if (relLeft > 0.65 && relTop < 0.20) {
      score -= 35;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCORES POR CARACTERÍSTICAS DO TEXTO
    // ═══════════════════════════════════════════════════════════════════════

    // Começa com maiúscula
    if (cleaned.isNotEmpty && _isUpperCase(cleaned[0])) {
      score += 15;
    }

    // Padrão de nome MTG válido
    for (final pattern in _validNamePatterns) {
      if (pattern.hasMatch(cleaned)) {
        score += 25;
        break;
      }
    }

    // Múltiplas palavras capitalizadas
    final words = cleaned.split(RegExp(r'\s+'));
    final capCount =
        words.where((w) => w.isNotEmpty && _isUpperCase(w[0])).length;
    if (capCount >= 2 && capCount <= 6) {
      score += capCount * 7;
    }

    // Comprimento típico (3-35 chars)
    if (cleaned.length >= 3 && cleaned.length <= 35) {
      score += 10;
    } else if (cleaned.length > 40) {
      score -= 20;
    }

    // Apóstrofe (comum: "Jace's", "Urza's")
    if (cleaned.contains("'")) score += 15;

    // Hífen (comum: "Will-o'-the-Wisp")
    if (cleaned.contains("-")) score += 10;

    // Vírgula (títulos: "Emrakul, the Aeons Torn")
    if (cleaned.contains(",")) score += 18;

    // Palavras conectoras comuns
    if (lower.contains(' the ')) score += 8;
    if (lower.contains(' of ')) score += 8;

    // ═══════════════════════════════════════════════════════════════════════
    // PENALIDADES
    // ═══════════════════════════════════════════════════════════════════════

    // Caracteres estranhos (OCR ruim)
    final strange = RegExp(r"[^a-zA-Z\s'\-,]").allMatches(cleaned).length;
    score -= strange * 6;

    // Muitos números
    final digits = RegExp(r'\d').allMatches(cleaned).length;
    score -= digits * 10;

    return math.max(0, score);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ══════════════════════════════════════════════════════════════════════════

  /// Verifica se é linha de tipo
  bool _isTypeLine(String text) {
    final patterns = [
      RegExp(
        r'^(legendary\s+)?(artifact\s+)?(creature|artifact|enchantment|instant|sorcery|land|planeswalker|battle)',
        caseSensitive: false,
      ),
      RegExp(r'^\w+\s*[—–-]\s*\w+'),
      RegExp(r'^basic\s+(land|snow)', caseSensitive: false),
    ];
    return patterns.any((p) => p.hasMatch(text));
  }

  /// Limpa e normaliza texto
  String _cleanText(String text) {
    var result = text;

    // Remove símbolos de mana
    result = result.replaceAll(RegExp(r'\{[^}]+\}'), '');

    // Normaliza apóstrofes e hífens
    result = result.replaceAll(RegExp(r"['`']"), "'");
    result = result.replaceAll(RegExp(r'[—–]'), '-');

    // Remove caracteres inválidos
    result = result.replaceAll(RegExp(r"[^a-zA-Z\s'\-,]"), '');

    // Limpa espaços
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Corrige capitalização se necessário
    if (result == result.toLowerCase() || result == result.toUpperCase()) {
      result = _toTitleCase(result);
    }

    return result;
  }

  /// Converte para Title Case inteligente
  String _toTitleCase(String text) {
    const smallWords = {
      'a',
      'an',
      'the',
      'and',
      'but',
      'or',
      'for',
      'nor',
      'of',
      'to',
      'in',
      'on',
      'at',
      'by',
    };

    return text
        .split(' ')
        .asMap()
        .entries
        .map((e) {
          final word = e.value;
          if (word.isEmpty) return word;

          if (e.key == 0 || !smallWords.contains(word.toLowerCase())) {
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          }
          return word.toLowerCase();
        })
        .join(' ');
  }

  /// Verifica se caractere é maiúsculo
  bool _isUpperCase(String char) {
    return char == char.toUpperCase() && char != char.toLowerCase();
  }

  /// Remove duplicatas
  List<CardNameCandidate> _deduplicate(List<CardNameCandidate> candidates) {
    final seen = <String>{};
    final unique = <CardNameCandidate>[];

    for (final c in candidates) {
      final key = c.text.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(c);
      }
    }

    return unique;
  }

  /// Calcula confiança final
  double _calculateConfidence(List<CardNameCandidate> candidates) {
    if (candidates.isEmpty) return 0;

    const maxScore = 150.0;
    var conf = (candidates.first.score / maxScore) * 100;

    // Bônus por diferença clara entre primeiro e segundo
    if (candidates.length >= 2) {
      final diff = candidates[0].score - candidates[1].score;
      if (diff > 25) conf += 8;
      if (diff > 50) conf += 8;
    }

    // Bônus por poucos candidatos (menos ambiguidade)
    if (candidates.length <= 3) conf += 5;

    return conf.clamp(0, 100);
  }

  /// Aplica sharpening
  img.Image _sharpen(img.Image image) {
    return img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
    );
  }

  /// Threshold adaptativo
  img.Image _adaptiveThreshold(
    img.Image image, {
    int blockSize = 15,
    int constant = 10,
  }) {
    final result = img.Image.from(image);
    final half = blockSize ~/ 2;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        double sum = 0;
        int count = 0;

        for (int dy = -half; dy <= half; dy++) {
          for (int dx = -half; dx <= half; dx++) {
            final nx = (x + dx).clamp(0, image.width - 1);
            final ny = (y + dy).clamp(0, image.height - 1);
            sum += img.getLuminance(image.getPixel(nx, ny));
            count++;
          }
        }

        final threshold = (sum / count) - constant;
        final lum = img.getLuminance(image.getPixel(x, y));

        result.setPixel(
          x,
          y,
          lum < threshold
              ? img.ColorRgb8(0, 0, 0)
              : img.ColorRgb8(255, 255, 255),
        );
      }
    }

    return result;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

/// Região para processamento
class _Region {
  final double left, top, right, bottom;
  final String name;
  _Region(this.left, this.top, this.right, this.bottom, this.name);
}
