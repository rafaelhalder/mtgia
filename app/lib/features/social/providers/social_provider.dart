import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

/// Modelo de usuário público
class PublicUser {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final int followerCount;
  final int followingCount;
  final int publicDeckCount;
  final DateTime? createdAt;

  PublicUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.followerCount = 0,
    this.followingCount = 0,
    this.publicDeckCount = 0,
    this.createdAt,
  });

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      followerCount: json['follower_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
      publicDeckCount: json['public_deck_count'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  String get displayLabel => displayName ?? username;
}

/// Modelo de deck público (simplificado para listas em perfil)
class PublicDeckSummary {
  final String id;
  final String name;
  final String format;
  final String? description;
  final int? synergyScore;
  final int cardCount;
  final String? commanderName;
  final String? commanderImageUrl;
  final DateTime? createdAt;

  PublicDeckSummary({
    required this.id,
    required this.name,
    required this.format,
    this.description,
    this.synergyScore,
    this.cardCount = 0,
    this.commanderName,
    this.commanderImageUrl,
    this.createdAt,
  });

  factory PublicDeckSummary.fromJson(Map<String, dynamic> json) {
    return PublicDeckSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      format: json['format'] as String? ?? 'unknown',
      description: json['description'] as String?,
      synergyScore: json['synergy_score'] as int?,
      cardCount: json['card_count'] as int? ?? 0,
      commanderName: json['commander_name'] as String?,
      commanderImageUrl: json['commander_image_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

/// Provider para funcionalidades sociais (follow, busca de usuários, perfis)
class SocialProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  // --- Busca de usuários ---
  List<PublicUser> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  int _searchTotal = 0;

  List<PublicUser> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;
  int get searchTotal => _searchTotal;

  // --- Perfil visitado ---
  PublicUser? _visitedUser;
  List<PublicDeckSummary> _visitedUserDecks = [];
  bool _isLoadingProfile = false;
  String? _profileError;
  bool _isFollowingVisited = false;
  bool? _isOwnProfile;

  PublicUser? get visitedUser => _visitedUser;
  List<PublicDeckSummary> get visitedUserDecks => _visitedUserDecks;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;
  bool get isFollowingVisited => _isFollowingVisited;
  bool? get isOwnProfile => _isOwnProfile;

  // --- Followers / Following ---
  List<PublicUser> _followers = [];
  List<PublicUser> _following = [];
  bool _isLoadingFollowers = false;
  bool _isLoadingFollowing = false;
  int _followersTotal = 0;
  int _followingTotal = 0;
  int _followersPage = 1;
  int _followingPage = 1;
  bool _hasMoreFollowers = true;
  bool _hasMoreFollowing = true;
  String? _currentFollowersUserId;
  String? _currentFollowingUserId;

  List<PublicUser> get followers => _followers;
  List<PublicUser> get following => _following;
  bool get isLoadingFollowers => _isLoadingFollowers;
  bool get isLoadingFollowing => _isLoadingFollowing;
  int get followersTotal => _followersTotal;
  int get followingTotal => _followingTotal;
  bool get hasMoreFollowers => _hasMoreFollowers;
  bool get hasMoreFollowing => _hasMoreFollowing;

  // --- Feed de seguidos ---
  List<PublicDeckSummary> _followingFeed = [];
  bool _isLoadingFeed = false;
  bool _hasMoreFeed = true;
  int _feedPage = 1;
  int _feedTotal = 0;

  List<PublicDeckSummary> get followingFeed => _followingFeed;
  bool get isLoadingFeed => _isLoadingFeed;
  bool get hasMoreFeed => _hasMoreFeed;
  int get feedTotal => _feedTotal;

  SocialProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  // ======================================================================
  // Busca de Usuários
  // ======================================================================

  /// Busca usuários por username/display_name
  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _searchTotal = 0;
      _searchError = null;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final encoded = Uri.encodeComponent(query.trim());
      final response =
          await _apiClient.get('/community/users?q=$encoded&limit=30');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        _searchResults = list
            .map((u) => PublicUser.fromJson(u as Map<String, dynamic>))
            .toList();
        _searchTotal = data['total'] as int? ?? _searchResults.length;
      } else {
        _searchError = 'Falha ao buscar usuários';
      }
    } catch (e) {
      debugPrint('[SocialProvider] searchUsers error: $e');
      _searchError = 'Erro de conexão';
    }

    _isSearching = false;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    _searchTotal = 0;
    _searchError = null;
    notifyListeners();
  }

  // ======================================================================
  // Perfil Público
  // ======================================================================

  /// Carrega perfil público de um usuário
  Future<void> fetchUserProfile(String userId) async {
    _isLoadingProfile = true;
    _profileError = null;
    _visitedUser = null;
    _visitedUserDecks = [];
    _isFollowingVisited = false;
    _isOwnProfile = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/community/users/$userId');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final userMap = data['user'] as Map<String, dynamic>;
        _visitedUser = PublicUser.fromJson(userMap);
        _isFollowingVisited = userMap['is_following'] == true;
        _isOwnProfile = userMap['is_own_profile'] == true;

        final decksList = (data['public_decks'] as List?) ?? [];
        _visitedUserDecks = decksList
            .map((d) =>
                PublicDeckSummary.fromJson(d as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 404) {
        _profileError = 'Usuário não encontrado';
      } else {
        _profileError = 'Erro ao carregar perfil';
      }
    } catch (e) {
      debugPrint('[SocialProvider] fetchUserProfile error: $e');
      _profileError = 'Erro de conexão';
    }

    _isLoadingProfile = false;
    notifyListeners();
  }

  // ======================================================================
  // Follow / Unfollow
  // ======================================================================

  /// Seguir um usuário
  Future<bool> followUser(String targetId) async {
    try {
      final response =
          await _apiClient.post('/users/$targetId/follow', {});

      if (response.statusCode == 200) {
        _isFollowingVisited = true;
        // Atualizar contadores
        if (_visitedUser != null) {
          final data = response.data as Map<String, dynamic>?;
          final newFollowerCount =
              data?['follower_count'] as int? ?? _visitedUser!.followerCount;
          _visitedUser = PublicUser(
            id: _visitedUser!.id,
            username: _visitedUser!.username,
            displayName: _visitedUser!.displayName,
            avatarUrl: _visitedUser!.avatarUrl,
            followerCount: newFollowerCount,
            followingCount: _visitedUser!.followingCount,
            publicDeckCount: _visitedUser!.publicDeckCount,
            createdAt: _visitedUser!.createdAt,
          );
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SocialProvider] followUser error: $e');
      return false;
    }
  }

  /// Deixar de seguir
  Future<bool> unfollowUser(String targetId) async {
    try {
      final response = await _apiClient.delete('/users/$targetId/follow');

      if (response.statusCode == 200) {
        _isFollowingVisited = false;
        if (_visitedUser != null) {
          final data = response.data as Map<String, dynamic>?;
          final newFollowerCount =
              data?['follower_count'] as int? ?? _visitedUser!.followerCount;
          _visitedUser = PublicUser(
            id: _visitedUser!.id,
            username: _visitedUser!.username,
            displayName: _visitedUser!.displayName,
            avatarUrl: _visitedUser!.avatarUrl,
            followerCount: newFollowerCount,
            followingCount: _visitedUser!.followingCount,
            publicDeckCount: _visitedUser!.publicDeckCount,
            createdAt: _visitedUser!.createdAt,
          );
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SocialProvider] unfollowUser error: $e');
      return false;
    }
  }

  // ======================================================================
  // Followers / Following Lists
  // ======================================================================

  /// Lista seguidores de um usuário (com paginação incremental)
  Future<void> fetchFollowers(String userId, {bool reset = false}) async {
    if (reset || userId != _currentFollowersUserId) {
      _followers = [];
      _followersTotal = 0;
      _followersPage = 1;
      _hasMoreFollowers = true;
      _currentFollowersUserId = userId;
    }

    if (!_hasMoreFollowers || _isLoadingFollowers) return;

    _isLoadingFollowers = true;
    notifyListeners();

    try {
      final response = await _apiClient
          .get('/users/$userId/followers?page=$_followersPage&limit=30');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        final newUsers = list
            .map((u) => PublicUser.fromJson(u as Map<String, dynamic>))
            .toList();
        _followers.addAll(newUsers);
        _followersTotal = data['total'] as int? ?? _followers.length;
        _hasMoreFollowers = _followers.length < _followersTotal;
        _followersPage++;
      }
    } catch (e) {
      debugPrint('[SocialProvider] fetchFollowers error: $e');
    }

    _isLoadingFollowers = false;
    notifyListeners();
  }

  /// Lista usuários que o alvo segue (com paginação incremental)
  Future<void> fetchFollowing(String userId, {bool reset = false}) async {
    if (reset || userId != _currentFollowingUserId) {
      _following = [];
      _followingTotal = 0;
      _followingPage = 1;
      _hasMoreFollowing = true;
      _currentFollowingUserId = userId;
    }

    if (!_hasMoreFollowing || _isLoadingFollowing) return;

    _isLoadingFollowing = true;
    notifyListeners();

    try {
      final response = await _apiClient
          .get('/users/$userId/following?page=$_followingPage&limit=30');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        final newUsers = list
            .map((u) => PublicUser.fromJson(u as Map<String, dynamic>))
            .toList();
        _following.addAll(newUsers);
        _followingTotal = data['total'] as int? ?? _following.length;
        _hasMoreFollowing = _following.length < _followingTotal;
        _followingPage++;
      }
    } catch (e) {
      debugPrint('[SocialProvider] fetchFollowing error: $e');
    }

    _isLoadingFollowing = false;
    notifyListeners();
  }

  // ======================================================================
  // Feed de Seguidos
  // ======================================================================

  /// Busca decks públicos de usuários que o autenticado segue
  Future<void> fetchFollowingFeed({bool reset = false}) async {
    if (reset) {
      _feedPage = 1;
      _followingFeed = [];
      _hasMoreFeed = true;
      _feedTotal = 0;
    }

    if (!_hasMoreFeed || _isLoadingFeed) return;

    _isLoadingFeed = true;
    notifyListeners();

    try {
      final response = await _apiClient
          .get('/community/decks/following?page=$_feedPage&limit=20');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        final newDecks = list
            .map((d) =>
                PublicDeckSummary.fromJson(d as Map<String, dynamic>))
            .toList();
        _followingFeed.addAll(newDecks);
        _feedTotal = data['total'] as int? ?? 0;
        _hasMoreFeed = _followingFeed.length < _feedTotal;
        _feedPage++;
      }
    } catch (e) {
      debugPrint('[SocialProvider] fetchFollowingFeed error: $e');
    }

    _isLoadingFeed = false;
    notifyListeners();
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _searchResults = [];
    _isSearching = false;
    _searchError = null;
    _searchTotal = 0;
    _visitedUser = null;
    _visitedUserDecks = [];
    _isLoadingProfile = false;
    _profileError = null;
    _isFollowingVisited = false;
    _isOwnProfile = null;
    _followers = [];
    _following = [];
    _isLoadingFollowers = false;
    _isLoadingFollowing = false;
    _followersTotal = 0;
    _followingTotal = 0;
    _followersPage = 1;
    _followingPage = 1;
    _hasMoreFollowers = true;
    _hasMoreFollowing = true;
    _currentFollowersUserId = null;
    _currentFollowingUserId = null;
    _followingFeed = [];
    _isLoadingFeed = false;
    _hasMoreFeed = true;
    _feedPage = 1;
    _feedTotal = 0;
    notifyListeners();
  }
}
