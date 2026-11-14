import '../../auth/domain/app_user.dart';

class PairInvite {
  const PairInvite({required this.id, required this.toEmail, required this.createdAt, this.from});

  final String id;
  final String toEmail;
  final DateTime createdAt;

  /// Who sent it (only for incoming invites).
  final AppUser? from;

  factory PairInvite.fromJson(Map<String, dynamic> json) => PairInvite(
        id: json['id'] as String,
        toEmail: json['toEmail'] as String,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        from: json['from'] == null ? null : AppUser.fromJson(json['from'] as Map<String, dynamic>),
      );
}

/// Everything the home screen needs: me, my partner, pending invites.
class Overview {
  const Overview({required this.user, this.partner, this.incoming = const [], this.outgoing});

  final AppUser user;
  final AppUser? partner;
  final List<PairInvite> incoming;
  final PairInvite? outgoing;

  bool get isPaired => partner != null;

  factory Overview.fromJson(Map<String, dynamic> json) {
    final invites = (json['invites'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Overview(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      partner: json['partner'] == null ? null : AppUser.fromJson(json['partner'] as Map<String, dynamic>),
      incoming: [
        for (final i in (invites['incoming'] as List? ?? const [])) PairInvite.fromJson(i as Map<String, dynamic>),
      ],
      outgoing: invites['outgoing'] == null ? null : PairInvite.fromJson(invites['outgoing'] as Map<String, dynamic>),
    );
  }
}
