import 'package:duet/core/theme/app_mode.dart';
import 'package:duet/core/theme/app_theme.dart';
import 'package:duet/core/widgets/duet_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modes', () {
    test('general is the default and unknown values fall back to it', () {
      expect(AppMode.parse(null), AppMode.general);
      expect(AppMode.parse('party'), AppMode.general);
      expect(AppMode.parse('love'), AppMode.love);
    });

    test('each mode has its own taps, wording and reactions', () {
      const general = ModeCopy(AppMode.general);
      const love = ModeCopy(AppMode.love);
      const friends = ModeCopy(AppMode.friends);
      expect(general.taps.map((t) => t.kind), ['wave', 'thumbs_up', 'ping', 'come_watch']);
      expect(love.taps.map((t) => t.kind), ['hug', 'kiss', 'miss_you', 'come_watch']);
      expect(friends.taps.map((t) => t.kind), ['high_five', 'fist_bump', 'lol', 'come_watch']);
      expect(general.tapsTitle('Sam'), 'Quick taps for Sam');
      expect(love.tapsTitle('Sam'), 'Love taps for Sam');
      expect(friends.tapsTitle('Sam'), 'Send Sam a vibe');
      expect(general.togetherLine('2h'), isNot(contains('💞')), reason: 'general wording is neutral');
      expect(love.reactions, contains('🥰'));
      expect(friends.reactions, contains('💀'));
    });

    test('received taps read well for every kind', () {
      for (final mode in AppMode.values) {
        for (final tap in ModeCopy(mode).taps) {
          final (emoji, text) = ModeCopy.nudgeMessage(tap.kind, 'Sam');
          expect(emoji, tap.emoji);
          expect(text, startsWith('Sam'));
        }
      }
    });
  });

  group('palette', () {
    test('three distinct palettes', () {
      final accents = AppMode.values.map((m) => DuetPalette.of(m).accent).toSet();
      expect(accents.length, 3);
    });

    test('blends smoothly between modes and switches wording half-way', () {
      final start = DuetPalette.general;
      final end = DuetPalette.love;
      final early = start.lerp(end, 0.25);
      final late = start.lerp(end, 0.75);
      expect(early.mode, AppMode.general);
      expect(late.mode, AppMode.love);
      expect(start.lerp(end, 0.5).accent, Color.lerp(start.accent, end.accent, 0.5));
      expect(start.lerp(end, 1).accent, end.accent);
    });
  });

  testWidgets('the logo renders in every theme and style', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDuetTheme(DuetPalette.love),
        home: Wrap(
          children: [
            const DuetLogo(size: 64), // follows the theme → love
            for (final mode in AppMode.values)
              for (final style in LogoStyle.values) DuetLogo(size: 48, mode: mode, style: style),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<DuetLogoPainter>();
    expect(painters.first.mode, AppMode.love, reason: 'logo without a mode follows the theme');
    expect(painters.length, 1 + AppMode.values.length * LogoStyle.values.length);
  });

  testWidgets('changing the theme recolours and rewords the UI', (tester) async {
    var mode = AppMode.general;
    late StateSetter setMode;
    Color? accent;
    String? title;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setMode = setState;
          return MaterialApp(
            theme: buildDuetTheme(DuetPalette.of(mode)),
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: Builder(
              builder: (context) {
                accent = context.palette.accent;
                title = context.copy.tapsTitle('Sam');
                return Text(title!, textDirection: TextDirection.ltr);
              },
            ),
          );
        },
      ),
    );
    expect(accent, DuetPalette.general.accent);
    expect(find.text('Quick taps for Sam'), findsOneWidget);

    setMode(() => mode = AppMode.friends);
    await tester.pump(); // starts the theme animation
    await tester.pump(const Duration(milliseconds: 150));
    expect(accent, isNot(DuetPalette.general.accent), reason: 'animating');
    expect(accent, isNot(DuetPalette.friends.accent));
    await tester.pumpAndSettle();
    expect(accent, DuetPalette.friends.accent);
    expect(find.text('Send Sam a vibe'), findsOneWidget);
  });
}
