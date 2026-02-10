import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Widget centralizado para exibir imagens de cartas MTG com cache local.
///
/// Usa [CachedNetworkImage] internamente para:
/// - Cache em disco (não re-baixa a cada build/scroll)
/// - Placeholder animado enquanto carrega
/// - Fallback de erro (ícone) se a imagem falhar
/// - Fade-in suave ao carregar
///
/// Uso:
/// ```dart
/// CachedCardImage(
///   imageUrl: card.imageUrl,
///   width: 60,
///   height: 84,
/// )
/// ```
class CachedCardImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const CachedCardImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _placeholder();
    }

    final image = CachedNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => _loadingWidget(),
      errorWidget: (_, __, ___) => _errorWidget(),
      // Cache por 30 dias (default do flutter_cache_manager)
      // As imagens do Scryfall raramente mudam, então cache longo é seguro.
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }

  /// Placeholder estático quando não há URL (sem imagem para carregar)
  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: const Center(
        child: Icon(
          Icons.style, // ícone de carta MTG genérico
          color: AppTheme.outlineMuted,
          size: 28,
        ),
      ),
    );
  }

  /// Spinner de loading enquanto a imagem está baixando
  Widget _loadingWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Center(
        child: SizedBox(
          width: (width ?? 60) * 0.3,
          height: (width ?? 60) * 0.3,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.manaViolet,
          ),
        ),
      ),
    );
  }

  Widget _errorWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: const Icon(
        Icons.image_not_supported,
        color: AppTheme.outlineMuted,
      ),
    );
  }
}
