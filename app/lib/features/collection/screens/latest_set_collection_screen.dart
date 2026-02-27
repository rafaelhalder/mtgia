import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

class LatestSetCollectionScreen extends StatefulWidget {
  const LatestSetCollectionScreen({super.key});

  @override
  State<LatestSetCollectionScreen> createState() =>
      _LatestSetCollectionScreenState();
}

class _LatestSetCollectionScreenState extends State<LatestSetCollectionScreen> {
  final ApiClient _apiClient = ApiClient();
  final ScrollController _scrollController = ScrollController();

  String? _setCode;
  String? _setName;
  String? _releaseDate;

  final List<Map<String, dynamic>> _cards = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLatestSetAndCards();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLatestSetAndCards() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _cards.clear();
      _page = 1;
      _hasMore = true;
    });

    try {
      final setResponse = await _apiClient.get('/sets?limit=1&page=1');
      if (setResponse.statusCode != 200) {
        throw Exception('Falha ao buscar última edição (${setResponse.statusCode})');
      }

      final setData = setResponse.data as Map<String, dynamic>;
      final sets = (setData['data'] as List?)?.whereType<Map>().toList() ?? const [];
      if (sets.isEmpty) {
        throw Exception('Nenhuma edição encontrada no banco');
      }

      final latestSet = sets.first.cast<String, dynamic>();
      _setCode = (latestSet['code'] as String?)?.toUpperCase();
      _setName = latestSet['name']?.toString();
      _releaseDate = latestSet['release_date']?.toString();

      await _fetchCardsPage(page: 1, append: false);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCardsPage({required int page, required bool append}) async {
    final setCode = _setCode;
    if (setCode == null || setCode.isEmpty) return;

    const limit = 100;
    final response = await _apiClient.get(
      '/cards?set=${Uri.encodeQueryComponent(setCode)}&limit=$limit&page=$page&dedupe=true',
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao buscar cartas da edição (${response.statusCode})');
    }

    final body = response.data as Map<String, dynamic>;
    final incoming =
        (body['data'] as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ??
            const <Map<String, dynamic>>[];

    setState(() {
      if (!append) {
        _cards
          ..clear()
          ..addAll(incoming);
      } else {
        _cards.addAll(incoming);
      }

      _page = page;
      _hasMore = incoming.length == limit;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      await _fetchCardsPage(page: _page + 1, append: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mais cartas: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Última Edição'),
        backgroundColor: AppTheme.surfaceSlate2,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
              const SizedBox(height: 12),
              Text(
                'Falha ao carregar coleção mais recente.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadLatestSetAndCards,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppTheme.surfaceSlate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_setName ?? 'Edição'} (${_setCode ?? '-'})',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppTheme.fontLg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lançamento: ${_releaseDate ?? '-'} • Cartas carregadas: ${_cards.length}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            itemCount: _cards.length + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(
              color: AppTheme.outlineMuted,
              height: 1,
            ),
            itemBuilder: (context, index) {
              if (index >= _cards.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final card = _cards[index];
              final imageUrl = card['image_url']?.toString();

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 44,
                    height: 60,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? Container(
                            color: AppTheme.surfaceSlate,
                            child: const Icon(Icons.image_not_supported,
                                color: AppTheme.textSecondary, size: 18),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.surfaceSlate,
                              child: const Icon(Icons.broken_image,
                                  color: AppTheme.textSecondary, size: 18),
                            ),
                          ),
                  ),
                ),
                title: Text(
                  card['name']?.toString() ?? '-',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${card['type_line'] ?? '-'} • ${card['rarity'] ?? '-'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }
}
