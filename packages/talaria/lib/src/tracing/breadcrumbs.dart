import 'dart:async';
import 'dart:collection';

import '../context/runtime_context.dart';
import 'span_scope.dart';

/// Default ring-buffer capacity (locked APM contract).
const int kMaxBreadcrumbs = 50;

/// Query crumbs cannot grow past this, and cannot evict other crumbs.
const int kMaxQueryBreadcrumbs = 15;

/// Non-query crumbs. Together with [kMaxQueryBreadcrumbs] this fills the buffer.
const int kMaxOtherBreadcrumbs = 35;

/// Client-side breadcrumb attached to error events (`BreadcrumbDto`).
class Breadcrumb {
  Breadcrumb({
    required this.type,
    this.category,
    this.message,
    this.level,
    this.data,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  final DateTime timestamp;
  final String type;
  final String? category;
  final String? message;
  final String? level;
  final Map<String, String>? data;

  Map<String, Object?> toWire() {
    final wire = <String, Object?>{
      '__className__': 'BreadcrumbDto',
      'timestamp': RuntimeContext.isoTimestamp(timestamp),
      'type': type,
    };
    if (category != null && category!.isNotEmpty) {
      wire['category'] = category;
    }
    if (message != null && message!.isNotEmpty) {
      wire['message'] = message;
    }
    if (level != null && level!.isNotEmpty) {
      wire['level'] = level;
    }
    if (data != null && data!.isNotEmpty) {
      wire['data'] = data;
    }
    return wire;
  }
}

/// Zone / session scoped breadcrumb buffers for concurrent Serverpod requests.
class BreadcrumbScope {
  BreadcrumbScope._();

  static const Object zoneKey = #talariaBreadcrumbBuffer;
  static final Map<String, BreadcrumbBuffer> _sessions = {};

  static BreadcrumbBuffer? zoneBuffer() {
    final fromZone = Zone.current[zoneKey];
    if (fromZone is BreadcrumbBuffer) {
      return fromZone;
    }
    return null;
  }

  static void bindSession(String sessionId, BreadcrumbBuffer buffer) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return;
    }
    _sessions[id] = buffer;
  }

  static void unbindSession(String sessionId) {
    _sessions.remove(sessionId.trim());
  }

  static BreadcrumbBuffer? forSession(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return null;
    }
    return _sessions[id];
  }

  static BreadcrumbBuffer? current({String? sessionId}) {
    final fromZone = zoneBuffer();
    if (fromZone != null) {
      return fromZone;
    }
    if (sessionId != null) {
      return forSession(sessionId);
    }
    final bound = SpanScope.currentSessionId;
    if (bound != null) {
      return forSession(bound);
    }
    return null;
  }

  static T runWith<T>(T Function() body, {BreadcrumbBuffer? buffer}) {
    return Zone.current.fork(zoneValues: {
      zoneKey: buffer ?? BreadcrumbBuffer(),
    }).run(body);
  }

  static Future<T> runWithAsync<T>(
    Future<T> Function() body, {
    BreadcrumbBuffer? buffer,
  }) {
    return Zone.current.fork(zoneValues: {
      zoneKey: buffer ?? BreadcrumbBuffer(),
    }).run(body);
  }

  static void clearSessions() {
    _sessions.clear();
  }
}

/// Fixed-capacity ring buffer. Oldest entries drop first.
class BreadcrumbBuffer {
  BreadcrumbBuffer({this.capacity = kMaxBreadcrumbs});

  final int capacity;
  final ListQueue<Breadcrumb> _items = ListQueue<Breadcrumb>();

  void add(Breadcrumb breadcrumb) {
    final isQuery = breadcrumb.type == 'query';
    final cap = isQuery ? _queryCap : _otherCap;
    var kept = 0;
    for (final existing in _items) {
      final existingQuery = existing.type == 'query';
      if (isQuery == existingQuery) kept++;
    }
    while (kept >= cap && _items.isNotEmpty) {
      final oldest = _items.first;
      final oldestQuery = oldest.type == 'query';
      if (oldestQuery == isQuery) {
        _items.removeFirst();
        kept--;
      } else {
        // The oldest is the other tier. Walk forward to drop the oldest of this tier.
        final next = _items.toList();
        final index = next.indexWhere((item) => (item.type == 'query') == isQuery);
        if (index < 0) break;
        next.removeAt(index);
        _items
          ..clear()
          ..addAll(next);
        kept--;
      }
    }
    _items.addLast(breadcrumb);
  }

  int get _queryCap =>
      capacity >= kMaxBreadcrumbs ? kMaxQueryBreadcrumbs : (capacity < kMaxQueryBreadcrumbs ? capacity : kMaxQueryBreadcrumbs);

  int get _otherCap {
    final query = _queryCap;
    final room = capacity - query;
    if (room < 0) return 0;
    return room < kMaxOtherBreadcrumbs ? room : kMaxOtherBreadcrumbs;
  }

  List<Breadcrumb> snapshot() => List<Breadcrumb>.unmodifiable(_items);

  void clear() => _items.clear();

  int get length => _items.length;
}
