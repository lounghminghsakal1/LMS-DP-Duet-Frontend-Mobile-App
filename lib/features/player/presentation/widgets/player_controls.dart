import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../session/domain/sync_engine.dart';
import '../../../session/domain/syncable_player.dart';

/// Rebuilds [builder] whenever the player changes and at least 4×/second while playing.
class PlayerTicker extends StatefulWidget {
  const PlayerTicker({super.key, required this.player, required this.builder});

  final SyncablePlayer player;
  final WidgetBuilder builder;

  @override
  State<PlayerTicker> createState() => _PlayerTickerState();
}

class _PlayerTickerState extends State<PlayerTicker> {
  StreamSubscription<void>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && widget.player.isPlaying) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Play/pause, ±10 s, seek bar, speed. Every action goes through the session so
/// both phones do the same thing.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.engine,
    required this.enabled,
    required this.pendingPlay,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSeekBy,
    required this.onRate,
    this.trailing = const [],
    this.onLight = true,
  });

  final SyncablePlayer player;
  final SyncEngine engine;
  final bool enabled;
  final bool pendingPlay;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  final ValueChanged<int> onSeekBy;
  final ValueChanged<double> onRate;
  final List<Widget> trailing;

  /// Over video (white icons on a dark scrim).
  final bool onLight;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    return PlayerTicker(
      player: widget.player,
      builder: (context) {
        final player = widget.player;
        final durationMs = player.duration?.inMilliseconds ?? 0;
        final positionMs = player.position.inMilliseconds.clamp(0, durationMs > 0 ? durationMs : 1 << 31);
        final playing = widget.engine.targetPlaying;
        final sliderValue = (_dragMs ?? positionMs.toDouble()).clamp(0, durationMs > 0 ? durationMs : 1).toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundIcon(
                  icon: Icons.replay_10_rounded,
                  onTap: widget.enabled ? () => widget.onSeekBy(-10000) : null,
                ),
                const SizedBox(width: 22),
                _PlayButton(
                  playing: playing,
                  pending: widget.pendingPlay,
                  onTap: widget.enabled ? widget.onTogglePlay : null,
                ),
                const SizedBox(width: 22),
                _RoundIcon(
                  icon: Icons.forward_10_rounded,
                  onTap: widget.enabled ? () => widget.onSeekBy(10000) : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: durationMs > 0 ? durationMs.toDouble() : 1,
                value: sliderValue,
                onChanged: widget.enabled && durationMs > 0 ? (v) => setState(() => _dragMs = v) : null,
                onChangeEnd: widget.enabled && durationMs > 0
                    ? (v) {
                        setState(() => _dragMs = null);
                        widget.onSeek(v.round());
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Text(
                    formatPosition(sliderValue.round()),
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  const Spacer(),
                  _SpeedButton(
                    rate: widget.engine.target?.rate ?? 1,
                    onRate: widget.enabled ? widget.onRate : null,
                  ),
                  ...widget.trailing,
                  const SizedBox(width: 6),
                  Text(
                    durationMs > 0 ? formatPosition(durationMs) : '--:--',
                    style: const TextStyle(fontSize: 12, color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.pending, required this.onTap});

  final bool playing;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: DuetColors.accentGradient,
            boxShadow: [BoxShadow(color: DuetColors.pink.withValues(alpha: 0.45), blurRadius: 20)],
          ),
          child: pending
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 30,
      color: Colors.white,
      disabledColor: Colors.white38,
      icon: Icon(icon),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.rate, required this.onRate});

  final double rate;
  final ValueChanged<double>? onRate;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String _label(double r) => '${r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()}×';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      enabled: onRate != null,
      tooltip: 'Speed (for both)',
      onSelected: onRate,
      color: DuetColors.surfaceHigh,
      itemBuilder: (context) => [
        for (final r in _rates)
          PopupMenuItem(
            value: r,
            child: Text(_label(r), style: TextStyle(fontWeight: r == rate ? FontWeight.w800 : FontWeight.w400)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          _label(rate),
          style: TextStyle(
            color: rate == 1 ? Colors.white70 : DuetColors.pink,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Spinning record for songs.
class SpinningDisc extends StatefulWidget {
  const SpinningDisc({super.key, required this.spinning, this.size = 200});

  final bool spinning;
  final double size;

  @override
  State<SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<SpinningDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(SpinningDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [Color(0xFF1B1530), Color(0xFF2A2048), Color(0xFF1B1530), Color(0xFF2A2048), Color(0xFF1B1530)],
          ),
          boxShadow: [BoxShadow(color: DuetColors.violet.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final f in const [0.92, 0.8, 0.68, 0.56])
              Container(
                width: size * f,
                height: size * f,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
            Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: DuetColors.accentGradient),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}
