/// User Model
class User {
  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String? locationState;
  final String? locationCity;
  final String? tradeNotes;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.locationState,
    this.locationCity,
    this.tradeNotes,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      locationState: json['location_state'] as String?,
      locationCity: json['location_city'] as String?,
      tradeNotes: json['trade_notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'location_state': locationState,
      'location_city': locationCity,
      'trade_notes': tradeNotes,
    };
  }

  /// Retorna label de localização formatada (ex: "São Paulo, SP")
  String? get locationLabel {
    if (locationCity != null && locationState != null) {
      return '$locationCity, $locationState';
    }
    if (locationState != null) return locationState;
    return null;
  }

  User copyWith({
    String? displayName,
    String? avatarUrl,
    String? locationState,
    String? locationCity,
    String? tradeNotes,
  }) {
    return User(
      id: id,
      username: username,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      locationState: locationState ?? this.locationState,
      locationCity: locationCity ?? this.locationCity,
      tradeNotes: tradeNotes ?? this.tradeNotes,
    );
  }
}
