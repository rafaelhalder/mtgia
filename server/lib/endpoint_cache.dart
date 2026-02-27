class _CacheItem {
  const _CacheItem({required this.payload, required this.expiresAt});

  final Map<String, dynamic> payload;
  final DateTime expiresAt;
}

class EndpointCache {
  EndpointCache._();

  static final EndpointCache instance = EndpointCache._();

  final Map<String, _CacheItem> _store = {};

  Map<String, dynamic>? get(String key) {
    final item = _store[key];
    if (item == null) return null;
    if (DateTime.now().isAfter(item.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return item.payload;
  }

  void set(String key, Map<String, dynamic> payload, {Duration ttl = const Duration(seconds: 60)}) {
    _store[key] = _CacheItem(
      payload: payload,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void clearExpired() {
    final now = DateTime.now();
    _store.removeWhere((_, item) => now.isAfter(item.expiresAt));
  }
}
