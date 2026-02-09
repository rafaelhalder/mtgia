import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Pré-processador de imagem para melhorar reconhecimento OCR
/// Especialmente útil para cartas antigas, desgastadas ou foil
class ImagePreprocessor {
  /// Pré-processa a imagem para melhorar OCR
  static Future<File> preprocess(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return inputFile;

    // 1. Redimensiona se muito grande (melhora performance)
    if (image.width > 1500 || image.height > 2000) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? 1500 : null,
        height: image.height >= image.width ? 2000 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    // 2. Converte para escala de cinza
    image = img.grayscale(image);

    // 3. Aumenta contraste (ajuda em cartas desbotadas)
    image = img.adjustColor(image, contrast: 1.4);

    // 4. Aumenta brilho levemente
    image = img.adjustColor(image, brightness: 1.05);

    // 5. Sharpen para melhorar bordas das letras
    image = img.convolution(image, filter: [
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ], div: 1);

    // Salva em arquivo temporário
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '${inputFile.parent.path}/processed_$timestamp.jpg';
    final processedFile = File(tempPath);
    await processedFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 92)),
    );

    return processedFile;
  }

  /// Pré-processamento mais agressivo para cartas foil/reflexivas
  static Future<File> preprocessFoil(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return inputFile;

    // 1. Redimensiona se necessário
    if (image.width > 1200 || image.height > 1600) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? 1200 : null,
        height: image.height >= image.width ? 1600 : null,
      );
    }

    // 2. Converte para escala de cinza
    image = img.grayscale(image);

    // 3. Aplica normalização de histograma (equalização)
    image = _normalizeHistogram(image);

    // 4. Aumenta contraste mais agressivamente
    image = img.adjustColor(image, contrast: 1.6);

    // 5. Aplica threshold adaptativo para binarização
    image = _adaptiveThreshold(image, blockSize: 21, c: 12);

    // 6. Remove ruído pequeno
    image = _removeNoise(image);

    // Salva
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '${inputFile.parent.path}/processed_foil_$timestamp.jpg';
    final processedFile = File(tempPath);
    await processedFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 95)),
    );

    return processedFile;
  }

  /// Corta apenas a região do nome (topo da carta)
  static Future<File> cropNameRegion(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return inputFile;

    // Assume que o nome está nos primeiros 18% da altura
    final nameHeight = (image.height * 0.18).round();
    
    // Corta a região do topo
    image = img.copyCrop(
      image,
      x: 0,
      y: 0,
      width: image.width,
      height: nameHeight,
    );

    // Aplica processamento na região cortada
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.5);

    // Salva
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '${inputFile.parent.path}/name_region_$timestamp.jpg';
    final processedFile = File(tempPath);
    await processedFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 95)),
    );

    return processedFile;
  }

  /// Normalização de histograma simples
  static img.Image _normalizeHistogram(img.Image image) {
    // Encontra min e max luminância
    int minLum = 255;
    int maxLum = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    if (maxLum <= minLum) return image;

    // Aplica stretching
    final result = img.Image.from(image);
    final range = maxLum - minLum;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel).round();
        final newLum = ((lum - minLum) * 255 / range).round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgb8(newLum, newLum, newLum));
      }
    }

    return result;
  }

  /// Threshold adaptativo
  static img.Image _adaptiveThreshold(
    img.Image image, {
    int blockSize = 15,
    int c = 10,
  }) {
    final result = img.Image.from(image);
    final halfBlock = blockSize ~/ 2;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Calcula média local
        double sum = 0;
        int count = 0;

        for (int dy = -halfBlock; dy <= halfBlock; dy++) {
          for (int dx = -halfBlock; dx <= halfBlock; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
              sum += img.getLuminance(image.getPixel(nx, ny));
              count++;
            }
          }
        }

        final threshold = (sum / count) - c;
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel);

        if (luminance < threshold) {
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        } else {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }

    return result;
  }

  /// Remove ruído pequeno (erosão + dilatação)
  static img.Image _removeNoise(img.Image image) {
    // Erosão simples
    var result = img.Image.from(image);
    
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        // Se qualquer vizinho é preto, mantém preto
        bool hasBlackNeighbor = false;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (img.getLuminance(image.getPixel(x + dx, y + dy)) < 128) {
              hasBlackNeighbor = true;
              break;
            }
          }
          if (hasBlackNeighbor) break;
        }
        
        if (!hasBlackNeighbor) {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }

    return result;
  }

  /// Limpa arquivos temporários processados
  static Future<void> cleanupTempFiles(Directory dir) async {
    try {
      final files = dir.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('processed_')) {
          await file.delete();
        }
      }
    } catch (_) {
      // Ignora erros de limpeza
    }
  }
}
