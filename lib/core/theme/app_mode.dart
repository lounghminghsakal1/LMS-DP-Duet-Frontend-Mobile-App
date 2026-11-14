import 'package:flutter/material.dart';

/// The look & feel the two of you share. Either person can switch it; it
/// changes on both phones. General is the default.
enum AppMode {
  general,
  love,
  friends;

  static AppMode parse(String? value) => AppMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => AppMode.general,
      );
}

/// One quick-tap button (sends a "nudge" that buzzes the other phone).
class QuickTap {
  const QuickTap(this.kind, this.emoji, this.label);

  final String kind;
  final String emoji;
  final String label;
}

/// Everything that is worded or decorated differently per mode.
class ModeCopy {
  const ModeCopy(this.mode);

  final AppMode mode;

  String get label => switch (mode) {
        AppMode.general => 'General',
        AppMode.love => 'Love',
        AppMode.friends => 'Friends',
      };

  String get emoji => switch (mode) {
        AppMode.general => '🎬',
        AppMode.love => '💞',
        AppMode.friends => '🤜🤛',
      };

  /// Shown in the theme picker.
  String get description => switch (mode) {
        AppMode.general => 'Clean and simple. Works for anyone.',
        AppMode.love => 'Hearts, hugs and kisses for the two of you.',
        AppMode.friends => 'High fives, LOLs and good vibes for best friends.',
      };

  IconData get logoIcon => switch (mode) {
        AppMode.general => Icons.play_circle_fill_rounded,
        AppMode.love => Icons.favorite_rounded,
        AppMode.friends => Icons.celebration_rounded,
      };

  IconData get discIcon => switch (mode) {
        AppMode.general => Icons.music_note_rounded,
        AppMode.love => Icons.favorite_rounded,
        AppMode.friends => Icons.headphones_rounded,
      };

  /// The burst shown when a quick tap arrives.
  IconData get burstIcon => switch (mode) {
        AppMode.general => Icons.auto_awesome_rounded,
        AppMode.love => Icons.favorite_rounded,
        AppMode.friends => Icons.celebration_rounded,
      };

  String get burstEmoji => switch (mode) {
        AppMode.general => '✨',
        AppMode.love => '💗',
        AppMode.friends => '🎉',
      };

  List<QuickTap> get taps => switch (mode) {
        AppMode.general => const [
            QuickTap('wave', '👋', 'Wave'),
            QuickTap('thumbs_up', '👍', 'Thumbs up'),
            QuickTap('ping', '🔔', 'Ping'),
            QuickTap('come_watch', '🍿', 'Come watch'),
          ],
        AppMode.love => const [
            QuickTap('hug', '🤗', 'Hug'),
            QuickTap('kiss', '💋', 'Kiss'),
            QuickTap('miss_you', '🥺', 'Miss you'),
            QuickTap('come_watch', '🍿', 'Come watch'),
          ],
        AppMode.friends => const [
            QuickTap('high_five', '✋', 'High five'),
            QuickTap('fist_bump', '👊', 'Fist bump'),
            QuickTap('lol', '😂', 'LOL'),
            QuickTap('come_watch', '🍿', 'Come watch'),
          ],
      };

  String tapsTitle(String name) => switch (mode) {
        AppMode.general => 'Quick taps for $name',
        AppMode.love => 'Love taps for $name',
        AppMode.friends => 'Send $name a vibe',
      };

  List<String> get reactions => switch (mode) {
        AppMode.general => const ['👍', '😂', '😮', '😢', '🔥', '👏', '❤️'],
        AppMode.love => const ['❤️', '😂', '😮', '😢', '🔥', '👏', '🥰'],
        AppMode.friends => const ['😂', '🔥', '💀', '👏', '😮', '🤯', '🙌'],
      };

  String togetherLine(String span) => switch (mode) {
        AppMode.general => '$span watched together 🍿',
        AppMode.love => '$span spent together on Duet 💞',
        AppMode.friends => '$span of hangouts so far 🤙',
      };

  String get togetherEmpty => switch (mode) {
        AppMode.general => 'Time you spend watching together shows up here 🍿',
        AppMode.love => 'Your time together will show up here 💞',
        AppMode.friends => 'Your hangout time will show up here 🤙',
      };

  String onlineLine(String name) => switch (mode) {
        AppMode.general => '$name is online now',
        AppMode.love => '$name is online now 💚',
        AppMode.friends => '$name is online 🙌',
      };

  String get startingTogether => switch (mode) {
        AppMode.general => '▶  Starting together…',
        AppMode.love => '💞  Starting together…',
        AppMode.friends => '🚀  Starting together…',
      };

  String get backTogether => switch (mode) {
        AppMode.general => '▶  Back together, resuming',
        AppMode.love => '💞  Back together, resuming',
        AppMode.friends => '🙌  Squad\'s back, resuming',
      };

  // Pairing (shown before a pair exists, so usually in General).
  String get pairEmoji => switch (mode) {
        AppMode.general => '🔗',
        AppMode.love => '💌',
        AppMode.friends => '🤝',
      };

  String get pairTitle => switch (mode) {
        AppMode.general => 'Pair up with someone',
        AppMode.love => 'Pair with your person',
        AppMode.friends => 'Pair with your friend',
      };

  String get inviteLabel => switch (mode) {
        AppMode.general => 'Their email',
        AppMode.love => 'Your person\'s email',
        AppMode.friends => 'Your friend\'s email',
      };

  String get pairedToast => switch (mode) {
        AppMode.general => 'You\'re paired! 🎉',
        AppMode.love => 'You\'re paired! 💞',
        AppMode.friends => 'You\'re paired! 🙌',
      };

  String get acceptLabel => switch (mode) {
        AppMode.general => 'Accept',
        AppMode.love => 'Accept 💞',
        AppMode.friends => 'Accept 🙌',
      };

  /// What a received quick tap says (by tap kind, whatever the mode).
  static (String emoji, String text) nudgeMessage(String kind, String name) => switch (kind) {
        'hug' => ('🤗', '$name sent you a hug'),
        'kiss' => ('💋', '$name sent you a kiss'),
        'miss_you' => ('🥺', '$name misses you'),
        'come_watch' => ('🍿', '$name says: come watch with me!'),
        'wave' => ('👋', '$name waved at you'),
        'thumbs_up' => ('👍', '$name sent you a thumbs up'),
        'ping' => ('🔔', '$name is pinging you'),
        'high_five' => ('✋', '$name sent you a high five'),
        'fist_bump' => ('👊', '$name sent you a fist bump'),
        'lol' => ('😂', '$name is laughing with you'),
        _ => ('✨', '$name is thinking of you'),
      };
}
