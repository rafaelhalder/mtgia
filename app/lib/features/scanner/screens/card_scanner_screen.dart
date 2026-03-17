import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/scanner_provider.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanned_card_preview.dart';
import '../../decks/providers/deck_provider.dart';
import '../../decks/models/deck_card_item.dart';

/// Tela de scanner de cartas MTG usando câmera
class CardScannerScreen extends StatefulWidget {
  final String deckId;
  final String? mode;

  /// Callback para modo binder — ao escanear e confirmar carta,
  /// chama essa função ao invés de adicionar ao deck.
  final void Function(Map<String, dynamic> card)? onCardScannedForBinder;

  const CardScannerScreen({
    super.key,
    required this.deckId,
    this.mode,
    this.onCardScannedForBinder,
  });

  bool get isBinderMode => mode == 'binder';

  @override
  State<CardScannerScreen> createState() => _CardScannerScreenState();
}

class _CardScannerScreenState extends State<CardScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  late ScannerProvider _scannerProvider;
  bool _isInitialized = false;
  bool _hasPermission = false;
  String? _permissionError;
  bool _isInitializingCamera = false;
  bool _isStreaming = false;
  DateTime _lastFrameProcessed = DateTime.now();
  static const _frameThrottleMs = 800; // intervalo mínimo entre processamentos

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopLiveStream();
      final controller = _cameraController;
      _cameraController = null;
      _isInitialized = false;
      controller?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;

    // Verifica permissão
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _hasPermission = false;
          _isInitialized = false;
          _permissionError =
              status.isPermanentlyDenied
                  ? 'Permissão negada permanentemente. Abra as configurações do app.'
                  : 'Permissão de câmera necessária para escanear cartas.';
        });
        return;
      }

      setState(() {
        _hasPermission = true;
        _permissionError = null;
        _isInitialized = false;
      });

      // Obtém câmeras disponíveis
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _permissionError = 'Nenhuma câmera encontrada no dispositivo.';
        });
        return;
      }

      // Usa câmera traseira
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final previous = _cameraController;
      _cameraController = null;
      await previous?.dispose();

      _cameraDescription = camera;

      final controller = CameraController(
        camera,
        ResolutionPreset.high, // high = boa qualidade OCR sem ser pesado demais
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();

      // Configura foco automático contínuo
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

      // Aplica zoom leve para aproximar o nome da carta
      try {
        final maxZoom = await controller.getMaxZoomLevel();
        final minZoom = await controller.getMinZoomLevel();
        // Zoom 1.5x ou o máximo disponível — ideal para ler nome de carta
        final targetZoom = (minZoom + 0.5).clamp(minZoom, maxZoom.clamp(minZoom, 2.5));
        await controller.setZoomLevel(targetZoom);
        debugPrint('[📸 Camera] Zoom: $targetZoom (min=$minZoom, max=$maxZoom)');
      } catch (_) {}

      // Ativa exposição automática para condições de luz variadas
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });

      // Inicia stream contínuo para scan automático
      _startLiveStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitialized = false;
        _permissionError = 'Erro ao inicializar câmera: $e';
      });
    } finally {
      _isInitializingCamera = false;
    }
  }

  void _startLiveStream() {
    if (_isStreaming || _cameraController == null) return;
    try {
      _cameraController!.startImageStream(_onCameraFrame);
      _isStreaming = true;
      debugPrint('[📸 Live] Stream iniciado');
    } catch (e) {
      debugPrint('[📸 Live] Erro ao iniciar stream: $e');
    }
  }

  void _stopLiveStream() {
    if (!_isStreaming || _cameraController == null) return;
    try {
      _cameraController!.stopImageStream();
      _isStreaming = false;
      debugPrint('[📸 Live] Stream parado');
    } catch (e) {
      debugPrint('[📸 Live] Erro ao parar stream: $e');
    }
  }

  void _onCameraFrame(CameraImage image) {
    // Throttle: não processar mais rápido que o intervalo
    final now = DateTime.now();
    if (now.difference(_lastFrameProcessed).inMilliseconds < _frameThrottleMs) {
      return;
    }
    _lastFrameProcessed = now;

    if (_cameraDescription == null) return;
    if (_scannerProvider.state != ScannerState.idle) return;

    // Calcula a região do guia em coordenadas da câmera.
    // O overlay visual usa:
    //   cardWidth = screenWidth * 0.65
    //   cardHeight = cardWidth * (88/63)  — proporção carta MTG
    //   centralizado com offset de -30 pixels para cima
    //
    // O CameraImage tem dimensões invertidas (width/height) em relação à
    // orientação do celular (portrait). No Android/iOS, a câmera retorna
    // landscape internamente, mas o ML Kit aplica a rotação do sensor.
    // O textBlock.boundingBox retornado pelo ML Kit já está em coordenadas
    // rotacionadas (portrait), ou seja: X = largura real, Y = altura real.
    //
    // Para mapear o guia da tela para as coordenadas do ML Kit, usamos
    // a proporção relativa (%) da tela → da imagem da câmera.
    final guideRect = _calculateCameraGuideRect(image);

    // Processar em background (não bloqueia UI)
    _scannerProvider
        .processLiveFrame(
          image,
          _cameraDescription!,
          cardGuideRect: guideRect,
        )
        .then((detected) {
      if (detected && mounted) {
        // Vibração de feedback ao detectar
        HapticFeedback.mediumImpact();
        // Para o stream enquanto mostra resultado
        _stopLiveStream();
      }
    });
  }

  /// Calcula o retângulo do guia de carta em coordenadas da câmera/ML Kit.
  ///
  /// O ML Kit no iOS retorna bounding boxes em coordenadas da imagem
  /// com a rotação aplicada (portrait). No Android, similar após rotação.
  /// Precisamos mapear a proporção do guia visual na tela para proporção
  /// equivalente nas coordenadas de imagem.
  Rect? _calculateCameraGuideRect(CameraImage image) {
    if (!mounted) return null;

    final screenSize = MediaQuery.of(context).size;
    if (screenSize.isEmpty) return null;

    // O guia na tela (mesma math do ScannerOverlay)
    final screenGuideWidth = screenSize.width * 0.65;
    final screenGuideHeight = screenGuideWidth * (88.0 / 63.0);
    final screenGuideLeft = (screenSize.width - screenGuideWidth) / 2;
    final screenGuideTop = (screenSize.height - screenGuideHeight) / 2 - 30;

    // Proporções relativas na tela (0.0 a 1.0)
    final relLeft = screenGuideLeft / screenSize.width;
    final relTop = screenGuideTop / screenSize.height;
    final relWidth = screenGuideWidth / screenSize.width;
    final relHeight = screenGuideHeight / screenSize.height;

    // O camera preview usa FittedBox(fit: BoxFit.cover) que escala e croppa.
    // Precisamos considerar o aspect ratio da câmera vs tela.
    final previewSize = _cameraController?.value.previewSize;
    if (previewSize == null) return null;

    // CameraController.previewSize retorna em landscape (width > height)
    // mas o ML Kit bounding boxes são em portrait (após rotação)
    final camW = previewSize.height; // largura em portrait
    final camH = previewSize.width;  // altura em portrait

    final screenAspect = screenSize.width / screenSize.height;
    final cameraAspect = camW / camH;

    double scaleX, scaleY, offsetX, offsetY;

    if (cameraAspect > screenAspect) {
      // Câmera é mais larga → croppa horizontalmente
      scaleY = camH / screenSize.height;
      scaleX = scaleY; // uniform scale
      final visibleCamWidth = screenSize.width * scaleX;
      offsetX = (camW - visibleCamWidth) / 2; // crop horizontal
      offsetY = 0;
    } else {
      // Câmera é mais alta → croppa verticalmente
      scaleX = camW / screenSize.width;
      scaleY = scaleX; // uniform scale
      final visibleCamHeight = screenSize.height * scaleY;
      offsetX = 0;
      offsetY = (camH - visibleCamHeight) / 2; // crop vertical
    }

    // Converte coordenadas de tela para câmera
    final camGuideLeft = relLeft * screenSize.width * scaleX + offsetX;
    final camGuideTop = relTop * screenSize.height * scaleY + offsetY;
    final camGuideWidth = relWidth * screenSize.width * scaleX;
    final camGuideHeight = relHeight * screenSize.height * scaleY;

    return Rect.fromLTWH(
      camGuideLeft,
      camGuideTop,
      camGuideWidth,
      camGuideHeight,
    );
  }

  /// Captura manual como fallback (processamento completo com múltiplas estratégias)
  Future<void> _captureAndProcess() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _scannerProvider.state == ScannerState.processing ||
        _scannerProvider.state == ScannerState.searching) {
      return;
    }

    // Para o stream durante captura manual
    _stopLiveStream();

    try {
      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      await _scannerProvider.processImage(file);

      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao capturar: $e')));
      // Retoma stream se falhou
      _startLiveStream();
    }
  }

  void _addCardToDeck(DeckCardItem card) async {
    // Modo binder: retorna a carta via callback
    if (widget.isBinderMode) {
      final cardData = {
        'id': card.id,
        'name': card.name,
        'image_url': card.imageUrl,
        'set_code': card.setCode,
        'mana_cost': card.manaCost,
        'rarity': card.rarity,
      };
      Navigator.pop(context);
      widget.onCardScannedForBinder?.call(cardData);
      return;
    }

    final deckProvider = context.read<DeckProvider>();

    // Adiciona a carta ao deck
    final success = await deckProvider.addCardToDeck(widget.deckId, card, 1);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${card.name} adicionada ao deck!'),
          backgroundColor: AppTheme.primarySoft.withValues(alpha: 0.9),
          action: SnackBarAction(
            label: 'Ver Deck',
            textColor: Colors.white,
            onPressed: () => context.go('/decks/${widget.deckId}'),
          ),
        ),
      );

      // Reseta para escanear outra carta
      _scannerProvider.reset();
      // Retoma stream automático
      _startLiveStream();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deckProvider.errorMessage ?? 'Erro ao adicionar carta'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScannerProvider(),
      child: Consumer<ScannerProvider>(
        builder: (context, scannerProvider, _) {
          _scannerProvider = scannerProvider;
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              ),
              title: const Text('Escanear Carta'),
              actions: [
                // Toggle modo foil
                IconButton(
                  icon: Icon(
                    scannerProvider.useFoilMode
                        ? Icons.auto_fix_high
                        : Icons.auto_fix_off,
                    color:
                        scannerProvider.useFoilMode
                            ? AppTheme.mythicGold
                            : Colors.white,
                  ),
                  tooltip: 'Modo Foil',
                  onPressed: scannerProvider.toggleFoilMode,
                ),
              ],
            ),
            extendBodyBehindAppBar: true,
            body: _buildBody(scannerProvider),
          );
        },
      ),
    );
  }

  Widget _buildBody(ScannerProvider scannerProvider) {
    // Erro de permissão
    if (!_hasPermission || _permissionError != null) {
      return _buildPermissionError();
    }

    // Câmera não inicializada
    if (!_isInitialized || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Iniciando câmera...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    final isProcessing =
        scannerProvider.state == ScannerState.processing ||
        scannerProvider.state == ScannerState.searching;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview da câmera — preenche a tela inteira
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _cameraController!.value.previewSize?.height ?? 1,
              height: _cameraController!.value.previewSize?.width ?? 1,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),

        // Overlay com guia
        ScannerOverlay(isProcessing: isProcessing),

        // Feedback de detecção ao vivo
        if (scannerProvider.state == ScannerState.idle &&
            scannerProvider.liveDetectedName != null)
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Detectando: ${scannerProvider.liveDetectedName}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Dica compacta (apenas idle e sem detecção ao vivo)
        if (scannerProvider.state == ScannerState.idle &&
            scannerProvider.liveDetectedName == null)
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                ),
                child: const Text(
                  'Aponte para a carta — detecção automática',
                  style: TextStyle(color: Colors.white70, fontSize: AppTheme.fontMd),
                ),
              ),
            ),
          ),

        // Badge modo foil
        if (scannerProvider.useFoilMode)
          Positioned(
            top: MediaQuery.of(context).padding.top + 50,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.mythicGold.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: 14, color: Colors.black),
                  SizedBox(width: 4),
                  Text(
                    'Foil',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSm,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Indicador de processamento
        if (isProcessing)
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    scannerProvider.state == ScannerState.processing
                        ? 'Analisando imagem...'
                        : 'Buscando carta...',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

        // Resultado - carta encontrada (ManaBox-style full screen)
        if (scannerProvider.state == ScannerState.found &&
            scannerProvider.lastResult != null) ...[
          // Dark overlay covering the camera
          Positioned.fill(
            child: Container(color: AppTheme.backgroundAbyss),
          ),
          // Card preview anchored to bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ScannedCardPreview(
              result: scannerProvider.lastResult!,
              foundCards: scannerProvider.foundCards,
              onCardSelected: (card) {
                _addCardToDeck(card);
              },
              onAlternativeSelected: scannerProvider.searchAlternative,
              onRetry: () {
                scannerProvider.reset();
                _startLiveStream();
              },
            ),
          ),
        ],

        // Resultado - carta não encontrada
        if (scannerProvider.state == ScannerState.notFound ||
            scannerProvider.state == ScannerState.error)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: CardNotFoundWidget(
              detectedName: scannerProvider.lastResult?.primaryName,
              errorMessage: scannerProvider.errorMessage,
              onRetry: () {
                scannerProvider.reset();
                _startLiveStream();
              },
              onManualSearch: scannerProvider.searchAlternative,
            ),
          ),

        // Botão de captura manual (fallback)
        if (scannerProvider.state == ScannerState.idle)
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _captureAndProcess,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 28,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Captura manual',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: AppTheme.fontXs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: Colors.white54,
            ),
            const SizedBox(height: 24),
            Text(
              _permissionError ?? 'Permissão necessária',
              style: const TextStyle(color: Colors.white, fontSize: AppTheme.fontLg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final status = await Permission.camera.status;
                debugPrint('[📸 Scanner] status da permissão: $status');

                if (status.isPermanentlyDenied) {
                  // Já negou definitivamente → só nas Configurações do sistema
                  final opened = await openAppSettings();
                  debugPrint('[📸 Scanner] openAppSettings() → $opened');
                } else {
                  // denied / restricted → pedir de novo (mostra popup do sistema)
                  debugPrint('[📸 Scanner] solicitando permissão novamente...');
                  await _initializeCamera();
                }
              },
              icon: Icon(
                _permissionError?.contains('permanentemente') == true
                    ? Icons.settings
                    : Icons.camera_alt,
              ),
              label: Text(
                _permissionError?.contains('permanentemente') == true
                    ? 'Abrir Configurações'
                    : 'Permitir Câmera',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
