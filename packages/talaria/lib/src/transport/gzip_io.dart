import 'dart:io' show gzip;

/// `dart:io` gzip (VM, Flutter mobile and desktop).
List<int>? gzipEncodeOrNull(List<int> bytes) => gzip.encode(bytes);
