import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/card_recognition_result.dart';

/// Serviço de reconhecimento de cartas MTG usando ML Kit
/// Suporta cartas de todas as eras (1993-2026)
class CardRecognitionService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  // Palavras-chave que NÃO são nomes de cartas
  static const _nonNameKeywords = {
    // Tipos de carta
    'creature', 'instant', 'sorcery', 'enchantment', 'artifact', 'land',
    'planeswalker', 'legendary', 'tribal', 'snow', 'basic', 'token',
    'world', 'ongoing', 'conspiracy', 'phenomenon', 'plane', 'scheme',
    'vanguard', 'battle', 'kindred',
    // Subtipos comuns
    'human', 'wizard', 'soldier', 'elf', 'goblin', 'zombie', 'vampire',
    'dragon', 'angel', 'demon', 'beast', 'elemental', 'spirit', 'knight',
    // Habilidades
    'flying', 'trample', 'haste', 'vigilance', 'lifelink', 'deathtouch',
    'first strike', 'double strike', 'hexproof', 'indestructible',
    'flash', 'reach', 'menace', 'defender', 'protection', 'shroud',
    'intimidate', 'fear', 'shadow', 'horsemanship', 'flanking',
    'banding', 'rampage', 'cumulative upkeep', 'phasing', 'buyback',
    'flashback', 'madness', 'morph', 'storm', 'affinity', 'convoke',
    'dredge', 'transmute', 'bloodthirst', 'haunt', 'replicate',
    'forecast', 'graft', 'recover', 'ripple', 'split second',
    'suspend', 'vanishing', 'absorb', 'aura swap', 'delve', 'fortify',
    'frenzy', 'gravestorm', 'poisonous', 'transfigure', 'champion',
    'changeling', 'evoke', 'hideaway', 'prowl', 'reinforce', 'clash',
    'retrace', 'devour', 'exalted', 'unearth', 'cascade', 'annihilator',
    'level up', 'rebound', 'totem armor', 'infect', 'battle cry',
    'living weapon', 'undying', 'miracle', 'soulbond', 'overload',
    'scavenge', 'unleash', 'cipher', 'evolve', 'extort', 'fuse',
    'bestow', 'tribute', 'dethrone', 'hidden agenda', 'outlast',
    'prowess', 'dash', 'exploit', 'renown', 'awaken',
    'devoid', 'ingest', 'myriad', 'surge', 'skulk', 'emerge',
    'escalate', 'melee', 'crew', 'fabricate', 'partner', 'undaunted',
    'improvise', 'aftermath', 'embalm', 'eternalize', 'afflict',
    'ascend', 'assist', 'jump-start', 'mentor', 'afterlife', 'riot',
    'spectacle', 'escape', 'companion', 'mutate', 'cycling',
    'landcycling', 'basic landcycling', 'islandcycling', 'mountaincycling',
    'forestcycling', 'swampcycling', 'plainscycling',
    // Outros textos
    'tap', 'untap', 'add', 'mana', 'target', 'damage', 'life', 'draw',
    'discard', 'sacrifice', 'destroy', 'exile', 'return', 'counter',
    'copy', 'cast', 'pay', 'cost', 'converted', 'controller',
    'owner', 'opponent', 'player', 'permanent', 'spell', 'ability',
    'graveyard', 'library', 'hand', 'battlefield', 'stack', 'command',
    'zone', 'phase', 'step', 'turn', 'combat', 'attack', 'block',
    'declare', 'assign', 'deal', 'prevent', 'regenerate', 'bury',
    // Texto de edição/colecionador
    'illustrated', 'artist', 'wotc', 'wizards', 'illus', 'tm', 'reserved',
  };

  /// Extrai nome de qualquer carta MTG (1993-2026)
  Future<CardRecognitionResult> recognizeCard(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    if (recognizedText.blocks.isEmpty) {
      return CardRecognitionResult.failed('Nenhum texto detectado na imagem');
    }

    // Obtém dimensões da imagem para cálculos de região
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return CardRecognitionResult.failed('Erro ao processar imagem');
    }

    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    // Estratégia multi-região
    final candidates = <CardNameCandidate>[];

    for (final block in recognizedText.blocks) {
      final rect = block.boundingBox;
      final text = block.text.trim();

      // Calcula posição relativa (0.0 a 1.0)
      final relativeTop = rect.top / imageHeight;
      final relativeLeft = rect.left / imageWidth;
      final relativeWidth = rect.width / imageWidth;
      final relativeHeight = rect.height / imageHeight;

      // Calcula score baseado em múltiplos fatores
      final score = _calculateNameScore(
        text: text,
        relativeTop: relativeTop,
        relativeLeft: relativeLeft,
        relativeWidth: relativeWidth,
        relativeHeight: relativeHeight,
      );

      if (score > 0) {
        candidates.add(CardNameCandidate(
          text: _cleanCardName(text),
          rawText: text,
          score: score,
          boundingBox: rect,
        ));
      }
    }

    if (candidates.isEmpty) {
      return CardRecognitionResult.failed(
        'Não foi possível identificar o nome da carta',
      );
    }

    // Ordena por score (maior primeiro)
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // Normaliza confidence para 0-100
    final maxScore = 150.0; // Score máximo teórico
    final confidence = math.min(100.0, (candidates.first.score / maxScore) * 100);

    return CardRecognitionResult.success(
      primaryName: candidates.first.text,
      alternatives: candidates
          .skip(1)
          .take(3)
          .map((c) => c.text)
          .where((t) => t.isNotEmpty && t != candidates.first.text)
          .toList(),
      confidence: confidence,
      allCandidates: candidates,
    );
  }

  /// Calcula score de probabilidade de ser o nome da carta
  double _calculateNameScore({
    required String text,
    required double relativeTop,
    required double relativeLeft,
    required double relativeWidth,
    required double relativeHeight,
  }) {
    double score = 0.0;
    final lowerText = text.toLowerCase();
    final firstLine = text.split('\n').first.trim();

    // ══════════════════════════════════════════════════════════════════
    // FILTROS NEGATIVOS (descarta candidatos ruins)
    // ══════════════════════════════════════════════════════════════════

    // Descarta textos muito curtos ou muito longos
    if (firstLine.length < 3 || firstLine.length > 50) return 0;

    // Descarta se contém apenas números (mana cost, power/toughness)
    if (RegExp(r'^[\d\/\+\-\s\{\}]+$').hasMatch(firstLine)) return 0;

    // Descarta símbolos de mana isolados
    if (RegExp(r'^[\{\}WUBRGCXP\d\s]+$').hasMatch(firstLine)) return 0;

    // Descarta palavras-chave que não são nomes
    final lowerFirstLine = firstLine.toLowerCase();
    for (final keyword in _nonNameKeywords) {
      if (lowerFirstLine == keyword) {
        return 0;
      }
    }

    // Descarta texto de tipo de carta sozinho
    if (_isTypeLine(lowerText)) return 0;

    // Descarta se parece com power/toughness
    if (RegExp(r'^\d+\s*/\s*\d+$').hasMatch(firstLine)) return 0;

    // ══════════════════════════════════════════════════════════════════
    // SCORES POSITIVOS POR REGIÃO
    // ══════════════════════════════════════════════════════════════════

    // REGIÃO 1: Topo da carta (frame moderno e antigo - nome no topo)
    // Cartas normais: nome fica nos primeiros 15% da altura
    if (relativeTop < 0.15) {
      score += 50;

      // Bônus se estiver à esquerda (onde nome costuma ficar)
      if (relativeLeft < 0.20) score += 20;
      
      // Bônus por largura típica do nome
      if (relativeWidth > 0.35 && relativeWidth < 0.85) score += 15;
    }

    // REGIÃO 2: Logo abaixo da borda superior (8% a 20%)
    // Para layouts antigos com nome menor ou cartas com borda grossa
    if (relativeTop >= 0.08 && relativeTop < 0.20) {
      score += 40;
    }

    // REGIÃO 3: Parte inferior (Showcase/Borderless com nome embaixo)
    if (relativeTop > 0.75 && relativeTop < 0.95) {
      // Nome embaixo geralmente é grande e centralizado
      if (relativeWidth > 0.4) score += 45;
      if (relativeLeft > 0.1 && relativeLeft < 0.4) score += 10;
    }

    // REGIÃO 4: Metade da carta (para cartas DFC - verso)
    if (relativeTop > 0.45 && relativeTop < 0.60) {
      score += 20;
    }

    // Se não está em nenhuma região típica, score baixo
    if (score == 0 && relativeTop > 0.20 && relativeTop < 0.75) {
      // Pode ser nome em posição incomum, dá score baixo
      score += 5;
    }

    // ══════════════════════════════════════════════════════════════════
    // SCORES POR CARACTERÍSTICAS DO TEXTO
    // ══════════════════════════════════════════════════════════════════

    // Bônus por começar com maiúscula (nomes de cartas sempre começam assim)
    if (firstLine.isNotEmpty && 
        firstLine[0] == firstLine[0].toUpperCase() &&
        firstLine[0] != firstLine[0].toLowerCase()) {
      score += 15;
    }

    // Bônus por ter múltiplas palavras capitalizadas (ex: "Serra Angel")
    final words = firstLine.split(RegExp(r'\s+'));
    final capitalizedWords = words.where((w) =>
        w.isNotEmpty &&
        w[0] == w[0].toUpperCase() &&
        w[0] != w[0].toLowerCase()).length;
    
    if (capitalizedWords >= 2 && capitalizedWords <= 6) {
      score += 8 * capitalizedWords;
    }

    // Bônus por conter apóstrofe ou hífen (comum em nomes MTG)
    // Ex: "Jace's Ingenuity", "Spell-Queller", "Sol'kanar the Swamp King"
    if (firstLine.contains("'") || firstLine.contains("'")) {
      score += 12;
    }
    if (firstLine.contains('-')) {
      score += 8;
    }

    // Bônus por conter vírgula (split cards, nomes com títulos)
    // Ex: "Fire // Ice", "Borborygmos Enraged"
    if (firstLine.contains(',')) {
      score += 5;
    }

    // Bônus por tamanho de fonte relativo (nome é geralmente maior)
    if (relativeHeight > 0.015 && relativeHeight < 0.08) {
      score += 15;
    }

    // Penalidade por caracteres estranhos (OCR ruim)
    final strangeChars = RegExp(r"[^a-zA-Z\s'\-,]").allMatches(firstLine).length;
    score -= strangeChars * 3;

    // Penalidade se parece com texto de regras (contém ":" com "{")
    if (lowerText.contains(':') && 
        (lowerText.contains('{') || lowerText.contains('}'))) {
      score -= 25;
    }

    // Penalidade se é muito longo (provavelmente texto de regras)
    if (firstLine.length > 35) {
      score -= 15;
    }

    // Penalidade se contém números no meio do texto
    if (RegExp(r'[a-zA-Z]\d[a-zA-Z]').hasMatch(firstLine)) {
      score -= 10;
    }

    return math.max(0, score);
  }

  /// Verifica se é linha de tipo
  bool _isTypeLine(String text) {
    final typePatterns = [
      // "Creature — Human Wizard"
      RegExp(
        r'^(legendary\s+)?(artifact\s+)?(creature|artifact|enchantment|instant|sorcery|land|planeswalker|battle)',
        caseSensitive: false,
      ),
      // "Human Wizard" (subtipo sozinho após tipo)
      RegExp(r'^\w+\s*[—–-]\s*\w+', caseSensitive: false),
      // "Basic Land — Island"
      RegExp(r'^basic\s+(land|snow)', caseSensitive: false),
    ];
    return typePatterns.any((p) => p.hasMatch(text));
  }

  /// Limpa o nome extraído
  String _cleanCardName(String text) {
    var name = text.split('\n').first.trim();

    // Remove símbolos de mana que podem ter sido incluídos
    name = name.replaceAll(RegExp(r'\{[WUBRGCXP\d/]+\}'), '');

    // Remove caracteres inválidos mas mantém apóstrofe, hífen e vírgula
    name = name.replaceAll(RegExp(r"[^a-zA-Z\s'\-,]"), '');

    // Normaliza apóstrofes
    name = name.replaceAll("'", "'");

    // Remove espaços extras
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
