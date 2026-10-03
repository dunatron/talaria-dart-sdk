import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:talaria/talaria.dart';

/// Patches [HttpClient] created after [TalariaServerpod.init].
///
/// `http.Client()` and `HttpClient()` then continue the active trace. Clients
/// created before init are unchanged. Ingest URLs and requests that already
/// carry `traceparent` are left alone. A call with no open span does not
/// start a root transaction.
void installServerpodOutboundHttp() {
  if (_installed) {
    return;
  }
  _installed = true;
  final previous = HttpOverrides.current;
  HttpOverrides.global = _TalariaHttpOverrides(previous);
}

bool _installed = false;

class _TalariaHttpOverrides extends HttpOverrides {
  _TalariaHttpOverrides(this._previous);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = _previous?.createHttpClient(context) ??
        super.createHttpClient(context);
    return _TracingIoClient(inner);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final previous = _previous;
    if (previous != null) {
      return previous.findProxyFromEnvironment(url, environment);
    }
    return super.findProxyFromEnvironment(url, environment);
  }
}

class _TracingIoClient implements HttpClient {
  _TracingIoClient(this._inner);

  final HttpClient _inner;

  Future<HttpClientRequest> _instrument(
    Future<HttpClientRequest> Function() open,
  ) async {
    final request = await open();
    final client = Talaria.getClient();
    if (client == null || !client.tracer.isEnabled) {
      return request;
    }
    final url = request.uri;
    if (TalariaHttpClient.isTalariaIngestUrl(url)) {
      return request;
    }
    if (request.headers.value(Traceparent.headerName) != null) {
      return request;
    }
    final parent = client.tracer.currentSpan;
    if (parent == null || !parent.isRecording) {
      return request;
    }
    final method = request.method.toUpperCase();
    final path = url.path.isEmpty ? '/' : url.path;
    final span = client.startSpan(
      '$method $path',
      kind: SpanKind.client,
      parent: parent,
      attributes: {
        'http.request.method': method,
        'url.path': path,
        if (url.host.isNotEmpty) 'server.address': url.host,
        if (url.scheme.isNotEmpty) 'url.scheme': url.scheme,
      },
    );
    if (!span.isRecording) {
      return request;
    }
    request.headers.set(
      Traceparent.headerName,
      span.toTraceparent().toHeader(),
    );
    return _TracingRequest(
      request,
      span: span,
      client: client,
      method: method,
      path: path,
    );
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    return _instrument(() => _inner.open(method, host, port, path));
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _instrument(() => _inner.openUrl(method, url));
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    return _instrument(() => _inner.get(host, port, path));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    return _instrument(() => _inner.getUrl(url));
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return _instrument(() => _inner.post(host, port, path));
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    return _instrument(() => _inner.postUrl(url));
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    return _instrument(() => _inner.put(host, port, path));
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    return _instrument(() => _inner.putUrl(url));
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    return _instrument(() => _inner.delete(host, port, path));
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    return _instrument(() => _inner.deleteUrl(url));
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    return _instrument(() => _inner.patch(host, port, path));
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    return _instrument(() => _inner.patchUrl(url));
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    return _instrument(() => _inner.head(host, port, path));
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    return _instrument(() => _inner.headUrl(url));
  }

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) {
    _inner.authenticate = f;
  }

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _inner.addCredentials(url, realm, credentials);
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) {
    _inner.connectionFactory = f;
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    _inner.findProxy = f;
  }

  @override
  set authenticateProxy(
    Future<bool> Function(
      String host,
      int port,
      String scheme,
      String? realm,
    )? f,
  ) {
    _inner.authenticateProxy = f;
  }

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _inner.addProxyCredentials(host, port, realm, credentials);
  }

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {
    _inner.badCertificateCallback = callback;
  }

  @override
  set keyLog(void Function(String line)? callback) {
    _inner.keyLog = callback;
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _TracingRequest implements HttpClientRequest {
  _TracingRequest(
    this._inner, {
    required this.span,
    required this.client,
    required String method,
    required this.path,
  }) : _method = method;

  final HttpClientRequest _inner;
  final Span span;
  final TalariaClient client;
  final String _method;
  final String path;
  var _finished = false;

  void _finishOk(int status) {
    if (_finished) return;
    _finished = true;
    span.setAttribute('http.response.status_code', status);
    if (status >= 500) {
      span.markError(message: 'HTTP $status');
    } else {
      span.setStatus(SpanStatus.ok);
    }
    span.finish();
    client.addBreadcrumb(Breadcrumb(
      type: 'http',
      category: 'http',
      message: '$_method $path',
      level: status >= 500 ? 'error' : 'info',
      data: {
        'http.request.method': _method,
        'url.path': path,
        'http.response.status_code': '$status',
      },
    ));
  }

  void _finishError(Object error) {
    if (_finished) return;
    _finished = true;
    span.setAttribute('error.type', error.runtimeType.toString());
    span.markError(message: error.toString());
    span.finish();
  }

  @override
  Future<HttpClientResponse> close() async {
    try {
      final response = await _inner.close();
      _finishOk(response.statusCode);
      return response;
    } catch (error) {
      _finishError(error);
      rethrow;
    }
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _finishError(exception ?? StateError('aborted'));
    _inner.abort(exception, stackTrace);
  }

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  bool get followRedirects => _inner.followRedirects;

  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;

  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  int get contentLength => _inner.contentLength;

  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get bufferOutput => _inner.bufferOutput;

  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  Future<HttpClientResponse> get done => _inner.done;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<void> flush() => _inner.flush();

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
}
