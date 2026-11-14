import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Emoji reactions that float up over the player on both phones.
class ReactionOverlay extends StatefulWidget {
  const ReactionOverlay({super.key});

  @override
  State<ReactionOverlay> createState() => ReactionOverlayState();
}

class ReactionOverlayState extends State<ReactionOverlay> with TickerProviderStateMixin {
  final _particles = <_Particle>[];
  final _random = math.Random();

  /// [mine] reactions float on the right, the partner's on the left.
  void add(String emoji, {bool mine = false}) {
    final count = emoji == '❤️' || emoji == '🥰' ? 3 : 1;
    for (var i = 0; i < count; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 2200 + _random.nextInt(900)),
      );
      final particle = _Particle(
        emoji: emoji,
        controller: controller,
        startX: mine ? 0.62 + _random.nextDouble() * 0.3 : 0.08 + _random.nextDouble() * 0.3,
        sway: (_random.nextDouble() - 0.5) * 0.18,
        size: 30 + _random.nextDouble() * 16,
        delay: i * 140,
      );
      setState(() => _particles.add(particle));
      Future<void>.delayed(Duration(milliseconds: particle.delay), () {
        if (!mounted) return;
        controller.forward().whenComplete(() {
          if (!mounted) return;
          setState(() => _particles.remove(particle));
          controller.dispose();
        });
      });
    }
  }

  @override
  void dispose() {
    for (final p in _particles) {
      p.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (final p in _particles)
              AnimatedBuilder(
                animation: p.controller,
                builder: (context, child) {
                  final t = Curves.easeOut.transform(p.controller.value);
                  final x = (p.startX + math.sin(t * math.pi * 2) * p.sway) * constraints.maxWidth;
                  final y = constraints.maxHeight * (0.92 - t * 0.75);
                  final opacity = p.controller.value < 0.75 ? 1.0 : (1 - p.controller.value) / 0.25;
                  final scale = 0.6 + math.min(1, p.controller.value * 5) * 0.4;
                  return Positioned(
                    left: x,
                    top: y,
                    child: Opacity(
                      opacity: opacity.clamp(0, 1).toDouble(),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: Text(p.emoji, style: TextStyle(fontSize: p.size)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.emoji,
    required this.controller,
    required this.startX,
    required this.sway,
    required this.size,
    required this.delay,
  });

  final String emoji;
  final AnimationController controller;
  final double startX;
  final double sway;
  final double size;
  final int delay;
}

const kReactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👏', '🥰'];

class ReactionBar extends StatelessWidget {
  const ReactionBar({super.key, required this.onReact, this.dense = false});

  final ValueChanged<String> onReact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final emoji in kReactionEmojis)
          InkResponse(
            radius: 22,
            onTap: () => onReact(emoji),
            child: Padding(
              padding: EdgeInsets.all(dense ? 4 : 6),
              child: Text(emoji, style: TextStyle(fontSize: dense ? 20 : 24)),
            ),
          ),
      ],
    );
  }
}
