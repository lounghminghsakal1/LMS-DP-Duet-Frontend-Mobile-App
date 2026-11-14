/// Estimates the offset between this phone's clock and the server's clock
/// (NTP style). Each ping gives one sample; the sample with the smallest round
/// trip is the most trustworthy, so we use that one.
class ClockSync {
  ClockSync({int Function()? localNow}) : _localNow = localNow ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _localNow;
  final List<({int rtt, int offset})> _samples = [];
  int _offsetMs = 0;
  int _rttMs = 0;

  int get offsetMs => _offsetMs;
  int get rttMs => _rttMs;
  bool get hasSamples => _samples.isNotEmpty;

  int localNow() => _localNow();

  /// Server clock "now", in epoch ms.
  int serverNow() => _localNow() + _offsetMs;

  /// [t0] when the ping was sent, [serverTime] stamped by the server, [t1] when the pong arrived.
  void addSample({required int t0, required int serverTime, required int t1}) {
    final rtt = t1 - t0;
    if (rtt < 0 || rtt > 10000) return;
    _samples.add((rtt: rtt, offset: serverTime - (t0 + rtt ~/ 2)));
    if (_samples.length > 12) _samples.removeAt(0);
    final best = _samples.reduce((a, b) => a.rtt <= b.rtt ? a : b);
    _offsetMs = best.offset;
    _rttMs = best.rtt;
  }

  /// A first rough guess (no round-trip info) used only until real samples arrive.
  void setProvisional(int serverTime) {
    if (_samples.isEmpty) _offsetMs = serverTime - _localNow();
  }

  void reset() {
    _samples.clear();
    _offsetMs = 0;
    _rttMs = 0;
  }
}
