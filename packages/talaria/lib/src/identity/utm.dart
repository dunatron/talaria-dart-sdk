import '../tracing/url_sanitizer.dart';

/// First-touch UTM campaign fields, denormalized onto every analytics row.
class Utm {
  const Utm({
    this.source,
    this.medium,
    this.campaign,
    this.term,
    this.content,
  });

  final String? source;
  final String? medium;
  final String? campaign;
  final String? term;
  final String? content;

  bool get isEmpty =>
      source == null &&
      medium == null &&
      campaign == null &&
      term == null &&
      content == null;

  Map<String, String> toMap() {
    return {
      if (source != null) 'source': source!,
      if (medium != null) 'medium': medium!,
      if (campaign != null) 'campaign': campaign!,
      if (term != null) 'term': term!,
      if (content != null) 'content': content!,
    };
  }

  static Utm? fromMap(Map<String, Object?>? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final utm = Utm(
      source: _nonEmpty(raw['source']),
      medium: _nonEmpty(raw['medium']),
      campaign: _nonEmpty(raw['campaign']),
      term: _nonEmpty(raw['term']),
      content: _nonEmpty(raw['content']),
    );
    return utm.isEmpty ? null : utm;
  }

  static Utm? fromUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasQuery) {
      return null;
    }
    final params = uri.queryParameters;
    final utm = Utm(
      source: _nonEmpty(params['utm_source']),
      medium: _nonEmpty(params['utm_medium']),
      campaign: _nonEmpty(params['utm_campaign']),
      term: _nonEmpty(params['utm_term']),
      content: _nonEmpty(params['utm_content']),
    );
    return utm.isEmpty ? null : utm;
  }

  static String? sanitizeUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return url.trim();
    }
    return UrlSanitizer.sanitize(uri).toString();
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
