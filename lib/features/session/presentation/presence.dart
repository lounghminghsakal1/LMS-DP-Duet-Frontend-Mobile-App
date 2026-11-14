import '../../../core/utils/format.dart';
import '../domain/room_state.dart';

/// "online", "last seen 5m ago" or "offline".
String presenceText(RoomMember? partner, {DateTime? fallbackLastSeen}) {
  if (partner?.online == true) return 'online';
  final seen = partner?.lastSeenAt ?? fallbackLastSeen;
  return seen == null ? 'offline' : 'last seen ${formatRelative(seen)}';
}
