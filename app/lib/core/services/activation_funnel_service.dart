import '../api/api_client.dart';

class ActivationFunnelService {
  ActivationFunnelService._();

  static final ActivationFunnelService instance = ActivationFunnelService._();
  final ApiClient _apiClient = ApiClient();

  Future<void> track(
    String eventName, {
    String? format,
    String? deckId,
    String source = 'app',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _apiClient.post('/users/me/activation-events', {
        'event_name': eventName,
        if (format != null) 'format': format,
        if (deckId != null) 'deck_id': deckId,
        'source': source,
        'metadata': metadata ?? <String, dynamic>{},
      });
    } catch (_) {
      // Telemetria não pode quebrar fluxo principal.
    }
  }
}
