import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanned_card_preview.dart';
import '../../cards/providers/card_provider.dart';
import '../../decks/providers/deck_provider.dart';
import '../../decks/models/deck_card_item.dart';

/// Tela de scanner de cartas MTG usando câmera
class CardScannerScreen extends StatefulWidget {
  final String deckId;

  const CardScannerScreen({super.key, required this.deckId});

  @override
  State<CardScannerScreen> createState() => _CardScannerScreenState();
}

class _CardScannerScreenState extends State<CardScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late ScannerProvider _scannerProvider;
  bool _isInitialized = false;
  bool _hasPermission = false;
  String? _permissionError;

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

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    // Verifica permissão
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _hasPermission = false;
        _permissionError = status.isPermanentlyDenied
            ? 'Permissão negada permanentemente. Abra as configurações do app.'
            : 'Permissão de câmera necessária para escanear cartas.';
      });
      return;
    }

    setState(() {
      _hasPermission = true;
      _permissionError = null;
    });

    // Obtém câmeras disponíveis
    final cameras = await availableCameras();
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

    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      
      // Configura foco automático
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Ignora se não suportado
      }

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _permissionError = 'Erro ao inicializar câmera: $e';
      });
    }
  }

  Future<void> _captureAndProcess() async {
    if (_cameraController == null || 
        !_cameraController!.value.isInitialized ||
        _scannerProvider.state == ScannerState.processing ||
        _scannerProvider.state == ScannerState.searching) {
      return;
    }

    try {
      // Captura a imagem
      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      // Processa com o provider
      await _scannerProvider.processImage(file);

      // Limpa arquivo temporário
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao capturar: $e')),
      );
    }
  }

  void _addCardToDeck(DeckCardItem card) async {
    final deckProvider = context.read<DeckProvider>();
    
    // Adiciona a carta ao deck
    final success = await deckProvider.addCardToDeck(
      widget.deckId,
      card,
      1,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${card.name} adicionada ao deck!'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Ver Deck',
            textColor: Colors.white,
            onPressed: () => context.go('/decks/${widget.deckId}'),
          ),
        ),
      );

      // Reseta para escanear outra carta
      _scannerProvider.reset();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deckProvider.errorMessage ?? 'Erro ao adicionar carta'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScannerProvider(context.read<CardProvider>()),
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
                    color: scannerProvider.useFoilMode
                        ? Colors.amber
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
            Text(
              'Iniciando câmera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    final isProcessing = scannerProvider.state == ScannerState.processing ||
        scannerProvider.state == ScannerState.searching;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview da câmera
        CameraPreview(_cameraController!),

        // Overlay com guia
        ScannerOverlay(isProcessing: isProcessing),

        // Dicas (apenas no estado idle)
        if (scannerProvider.state == ScannerState.idle)
          const Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: ScannerTips(),
          ),

        // Modo foil ativo
        if (scannerProvider.useFoilMode)
          Positioned(
            top: 100,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: 16, color: Colors.black),
                  SizedBox(width: 4),
                  Text(
                    'Modo Foil',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
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

        // Resultado - carta encontrada
        if (scannerProvider.state == ScannerState.found &&
            scannerProvider.lastResult != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ScannedCardPreview(
              result: scannerProvider.lastResult!,
              foundCards: scannerProvider.foundCards,
              onCardSelected: _addCardToDeck,
              onAlternativeSelected: scannerProvider.searchAlternative,
              onRetry: scannerProvider.reset,
            ),
          ),

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
              onRetry: scannerProvider.reset,
              onManualSearch: scannerProvider.searchAlternative,
            ),
          ),

        // Botão de captura
        if (scannerProvider.state == ScannerState.idle)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureAndProcess,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 40,
                      color: Colors.black87,
                    ),
                  ),
                ),
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                if (await Permission.camera.isPermanentlyDenied) {
                  openAppSettings();
                } else {
                  _initializeCamera();
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Abrir Configurações'),
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
