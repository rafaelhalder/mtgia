/// User Model
class User {
  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String? avatarUrl;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
    };
  }

  User copyWith({
    String? displayName,
    String? avatarUrl,
  }) {
    return User(
      id: id,
      username: username,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
