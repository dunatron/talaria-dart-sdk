/// Rage / dead / error classification. Same windows as the browser heatmap.
const rageWindowMs = 1000;
const rageRadiusPx = 30.0;
const rageMinTaps = 3;
const deadWindowMs = 1000;
const errorWindowMs = 2000;
const tapFinalizeMs = errorWindowMs;

class TapSample {
  const TapSample({
    required this.path,
    required this.role,
    required this.relX,
    required this.relY,
    required this.xBp,
    required this.yBp,
    required this.contentX,
    required this.contentY,
    required this.clientX,
    required this.clientY,
    required this.deadEligible,
  });

  final String path;
  final String role;
  final int relX;
  final int relY;
  final int xBp;
  final int yBp;
  final int contentX;
  final int contentY;
  final double clientX;
  final double clientY;
  final bool deadEligible;
}

class ClassifiedTap {
  const ClassifiedTap({
    required this.sample,
    required this.occurredAt,
    required this.rage,
    required this.dead,
    required this.error,
  });

  final TapSample sample;
  final int occurredAt;
  final bool rage;
  final bool dead;
  final bool error;
}

class _PendingTap {
  _PendingTap(this.sample, this.at)
      : observeUntil = at + deadWindowMs;

  final TapSample sample;
  final int at;
  int observeUntil;
  bool rage = false;
  bool effect = false;
  bool error = false;
}

class ScreenTapClassifier {
  ScreenTapClassifier(this.onFinalized);

  final void Function(ClassifiedTap tap) onFinalized;
  final List<_PendingTap> _pending = [];

  int get pendingCount => _pending.length;

  void notePress(String path, int at) {
    for (final tap in _pending) {
      if (tap.sample.path != path && tap.observeUntil > at) {
        tap.observeUntil = at;
      }
    }
  }

  void add(TapSample sample, int at) {
    notePress(sample.path, at);
    final tap = _PendingTap(sample, at);
    _pending.add(tap);
    _markRage(tap);
  }

  void noteEffect(int at) {
    for (final tap in _pending) {
      if (at >= tap.at && at < tap.observeUntil) tap.effect = true;
    }
  }

  void noteError(int at) {
    for (final tap in _pending) {
      if (at >= tap.at && at - tap.at <= errorWindowMs) tap.error = true;
    }
  }

  void tick(int now) {
    final keep = <_PendingTap>[];
    for (final tap in _pending) {
      if (now - tap.at >= tapFinalizeMs) {
        _emit(tap, true);
      } else {
        keep.add(tap);
      }
    }
    _pending
      ..clear()
      ..addAll(keep);
  }

  void flushAll(int now) {
    for (final tap in _pending) {
      _emit(tap, now >= tap.observeUntil);
    }
    _pending.clear();
  }

  void _markRage(_PendingTap latest) {
    final recent = _pending.where((p) => latest.at - p.at <= rageWindowMs);
    for (final first in recent) {
      final burst = recent.where(
        (p) =>
            p.at >= first.at &&
            p.at - first.at <= rageWindowMs &&
            _distance(p.sample, first.sample) <= rageRadiusPx,
      );
      if (burst.length >= rageMinTaps && burst.contains(latest)) {
        for (final tap in burst) {
          tap.rage = true;
        }
        return;
      }
    }
  }

  void _emit(_PendingTap tap, bool deadWindowClosed) {
    onFinalized(
      ClassifiedTap(
        sample: tap.sample,
        occurredAt: tap.at,
        rage: tap.rage,
        dead: tap.sample.deadEligible && deadWindowClosed && !tap.effect,
        error: tap.error,
      ),
    );
  }

  static double _distance(TapSample a, TapSample b) {
    final dx = a.clientX - b.clientX;
    final dy = a.clientY - b.clientY;
    return _hypot(dx, dy);
  }

  static double _hypot(double x, double y) {
    final xx = x * x;
    final yy = y * y;
    return (xx + yy) == 0 ? 0 : _sqrt(xx + yy);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    var x = v;
    for (var i = 0; i < 8; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }
}

int toBasisPoints(double offset, double size) {
  if (!(size > 0)) return 5000;
  final raw = (offset / size * 10000).round();
  if (raw < 0) return 0;
  if (raw > 10000) return 10000;
  return raw;
}
