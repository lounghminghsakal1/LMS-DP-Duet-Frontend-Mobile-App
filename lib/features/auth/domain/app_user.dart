class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarEmoji,
    this.coupleId,
    this.online,
    this.lastSeenAt,
  });

  /// When they were last connected (partner only).
  final DateTime? lastSeenAt;

  final String id;
  final String email;
  final String displayName;
  final String avatarEmoji;
  final String? coupleId;

  /// Only filled for the partner in the overview response.
  final bool? online;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        avatarEmoji: (json['avatarEmoji'] as String?) ?? '💜',
        coupleId: json['coupleId'] as String?,
        online: json['online'] as bool?,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '')?.toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'avatarEmoji': avatarEmoji,
        'coupleId': coupleId,
      };

  AppUser copyWith({String? displayName, String? avatarEmoji, String? coupleId, bool clearCouple = false}) {
    return AppUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      coupleId: clearCouple ? null : (coupleId ?? this.coupleId),
      online: online,
    );
  }
}

/// Result of sign-in / sign-up / refresh.
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String,
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
