import 'dart:collection';

import '../context/runtime_context.dart';

/// Default ring-buffer capacity (locked APM contract).
const int kMaxBreadcrumbs = 50;

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

/// Fixed-capacity ring buffer. Oldest entries drop first.
class BreadcrumbBuffer {
  BreadcrumbBuffer({this.capacity = kMaxBreadcrumbs});

  final int capacity;
  final ListQueue<Breadcrumb> _items = ListQueue<Breadcrumb>();

  void add(Breadcrumb breadcrumb) {
    _items.addLast(breadcrumb);
    while (_items.length > capacity) {
      _items.removeFirst();
    }
  }

  List<Breadcrumb> snapshot() => List<Breadcrumb>.unmodifiable(_items);

  void clear() => _items.clear();

  int get length => _items.length;
}
