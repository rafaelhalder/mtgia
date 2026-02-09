import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../decks/models/deck_card_item.dart';
import '../models/card_recognition_result.dart';

/// Preview do resultado do escaneamento
class ScannedCardPreview extends StatelessWidget {
  final CardRecognitionResult result;
  final List<DeckCardItem> foundCards;
  final Function(DeckCardItem) onCardSelected;
  final Function(String) onAlternativeSelected;
  final VoidCallback onRetry;

  const ScannedCardPreview({
    super.key,
    required this.result,
    required this.foundCards,
    required this.onCardSelected,
    required this.onAlternativeSelected,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: foundCards.isNotEmpty ? Colors.green[800] : Colors.orange[800],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  foundCards.isNotEmpty ? Icons.check_circle : Icons.search,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        foundCards.isNotEmpty ? 'Carta Encontrada!' : 'Buscando...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (result.primaryName != null)
                        Text(
                          'Detectado: "${result.primaryName}"',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                // Confiança
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${result.confidence.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista de cartas encontradas
          if (foundCards.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: foundCards.length > 5 ? 5 : foundCards.length,
                itemBuilder: (context, index) {
                  final card = foundCards[index];
                  return _CardListItem(
                    card: card,
                    isFirst: index == 0,
                    onTap: () => onCardSelected(card),
                  );
                },
              ),
            ),

          // Alternativas detectadas
          if (result.alternatives.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Não é essa carta? Tente:',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: result.alternatives.map((alt) {
                      return ActionChip(
                        label: Text(alt),
                        onPressed: () => onAlternativeSelected(alt),
                        backgroundColor: Colors.grey[800],
                        labelStyle: const TextStyle(color: Colors.white),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // Botão de retry
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Escanear Novamente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardListItem extends StatelessWidget {
  final DeckCardItem card;
  final bool isFirst;
  final VoidCallback onTap;

  const _CardListItem({
    required this.card,
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 40,
          height: 56,
          child: card.imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: card.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.image_not_supported, size: 20),
                  ),
                )
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.style, size: 20),
                ),
        ),
      ),
      title: Text(
        card.name,
        style: TextStyle(
          color: Colors.white,
          fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '${card.typeLine} • ${card.setCode.toUpperCase()}',
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isFirst
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Melhor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : const Icon(Icons.add_circle_outline, color: Colors.white54),
      onTap: onTap,
    );
  }
}

/// Widget para quando não encontra a carta
class CardNotFoundWidget extends StatelessWidget {
  final String? detectedName;
  final String? errorMessage;
  final VoidCallback onRetry;
  final Function(String) onManualSearch;

  const CardNotFoundWidget({
    super.key,
    this.detectedName,
    this.errorMessage,
    required this.onRetry,
    required this.onManualSearch,
  });

  @override
  Widget build(BuildContext context) {
    final searchController = TextEditingController(text: detectedName);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[900]!.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            errorMessage ?? 'Carta não encontrada',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (detectedName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Detectado: "$detectedName"',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),

          // Campo para busca manual
          TextField(
            controller: searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Digite o nome correto',
              hintStyle: TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => onManualSearch(searchController.text),
              ),
            ),
            onSubmitted: onManualSearch,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tentar Novamente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
