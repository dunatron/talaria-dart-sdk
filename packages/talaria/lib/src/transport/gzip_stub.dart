/// No gzip codec on this platform (web): bodies go uncompressed.
List<int>? gzipEncodeOrNull(List<int> bytes) => null;
