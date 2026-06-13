import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'models.dart';

/// Thrown for any non-2xx response; carries the Worker's `{ error }` message.
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class _CacheEntry {
  final dynamic value;
  final DateTime expires;
  _CacheEntry(this.value, this.expires);
  bool get fresh => DateTime.now().isBefore(expires);
}

/// Online-first REST client with the in-memory response cache from DESIGN.md
/// (Offline & Caching). The cache is a Map keyed by request URL; any write
/// clears the whole thing — at personal scale, simpler beats clever
/// invalidation, and you never see stale data you just wrote.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  final Map<String, _CacheEntry> _cache = {};

  // TTLs from the design's caching table.
  static const _detailTtl = Duration(minutes: 7);
  static const _listTtl = Duration(seconds: 90);
  static const _timelineTtl = Duration(minutes: 2);

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${Config.apiToken}',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(Config.apiBaseUrl);
    final clean = <String, String>{};
    query?.forEach((k, v) {
      if (v.isNotEmpty) clean[k] = v;
    });
    return base.replace(
      path: '${base.path}$path',
      queryParameters: clean.isEmpty ? null : clean,
    );
  }

  /// Headers a widget needs to load an auth-gated media file directly
  /// (Image.network streams `GET /api/media/:id/file` with the bearer token).
  Map<String, String> get mediaHeaders => _authHeaders;

  String mediaFileUrl(String mediaId) =>
      _uri('/api/media/$mediaId/file').toString();

  void clearCache() => _cache.clear();

  Future<dynamic> _cachedGet(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && hit.fresh) return hit.value;
    final value = await _get(uri);
    _cache[key] = _CacheEntry(value, DateTime.now().add(ttl));
    return value;
  }

  Future<dynamic> _get(Uri uri) async {
    final res = await _http.get(uri, headers: _authHeaders);
    return _decode(res);
  }

  Future<dynamic> _send(String method, Uri uri, [Object? body]) async {
    // Any write makes every cached read potentially stale — drop it all.
    clearCache();
    final req = http.Request(method, uri);
    req.headers.addAll(_authHeaders);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req));
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (res.statusCode == 204 || res.body.isEmpty) {
      if (ok) return null;
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode})');
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(res.body);
    } catch (_) {
      if (ok) return null;
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode})');
    }
    if (!ok) {
      final msg = parsed is Map && parsed['error'] is String
          ? parsed['error'] as String
          : 'Request failed (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return parsed;
  }

  // ——— Entities ———

  Future<EntityPage> listEntities({
    String? type,
    String? status,
    String? tag,
    String? search,
    String? parentId,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = _uri('/api/entities', {
      'type': ?type,
      'status': ?status,
      'tag': ?tag,
      'search': ?search,
      'parent_id': ?parentId,
      'limit': '$limit',
      'offset': '$offset',
    });
    final j = await _cachedGet(uri, _listTtl) as Map<String, dynamic>;
    return EntityPage(
      items: (j['items'] as List)
          .map((e) => Entity.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      total: j['total'] as int? ?? 0,
      limit: j['limit'] as int? ?? limit,
      offset: j['offset'] as int? ?? offset,
    );
  }

  Future<EntityDetail> getEntity(String idOrSlug) async {
    final uri = _uri('/api/entities/$idOrSlug');
    final j = await _cachedGet(uri, _detailTtl) as Map<String, dynamic>;
    return EntityDetail.fromJson(j);
  }

  Future<List<EntityRef>> backlinks(String idOrSlug) async {
    final uri = _uri('/api/entities/$idOrSlug/backlinks');
    final list = await _cachedGet(uri, _detailTtl) as List;
    return list
        .map((e) => EntityRef.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Children for nesting (chapters under a story, sub-locations, sub-factions).
  Future<List<Entity>> children(String parentId) async {
    final page = await listEntities(parentId: parentId, limit: 200);
    return page.items;
  }

  Future<Entity> createEntity(Map<String, dynamic> body) async {
    final j = await _send('POST', _uri('/api/entities'), body)
        as Map<String, dynamic>;
    return Entity.fromJson(j);
  }

  Future<Entity> updateEntity(String id, Map<String, dynamic> body) async {
    final j = await _send('PUT', _uri('/api/entities/$id'), body)
        as Map<String, dynamic>;
    return Entity.fromJson(j);
  }

  Future<void> deleteEntity(String id) async {
    await _send('DELETE', _uri('/api/entities/$id'));
  }

  // ——— Relationships ———

  Future<Relationship> createRelationship(Map<String, dynamic> body) async {
    final j = await _send('POST', _uri('/api/relationships'), body)
        as Map<String, dynamic>;
    return Relationship.fromJson(j);
  }

  Future<void> deleteRelationship(String id) async {
    await _send('DELETE', _uri('/api/relationships/$id'));
  }

  // ——— Search & timeline ———

  Future<EntityPage> search(String q, {String? type}) async {
    // Search results are never cached (always fresh — DESIGN.md).
    final uri = _uri('/api/search', {'q': q, 'type': ?type});
    final j = await _get(uri) as Map<String, dynamic>;
    return EntityPage(
      items: (j['items'] as List)
          .map((e) => Entity.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      total: j['total'] as int? ?? 0,
      limit: j['limit'] as int? ?? 50,
      offset: j['offset'] as int? ?? 0,
    );
  }

  Future<TimelineResult> timeline({String? era, String? status}) async {
    final uri = _uri('/api/timeline', {
      'era': ?era,
      'status': ?status,
    });
    final j = await _cachedGet(uri, _timelineTtl) as Map<String, dynamic>;
    return TimelineResult(
      items: (j['items'] as List)
          .map((e) => Entity.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      eras: (j['eras'] as List)
          .map((e) => EraRef.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  // ——— AI chat (Phase 4) ———

  /// Opens the streaming chat connection. Bypasses the cache entirely (it is a
  /// POST, and the conversation is ephemeral). Returns the raw streamed
  /// response so the caller can parse SSE frames; the caller MUST drain or
  /// cancel it. A write inside the loop (Apply) goes through the normal REST
  /// methods above, which clear the cache as usual.
  Future<http.StreamedResponse> chatStream(
    Map<String, dynamic> body, {
    http.Client? client,
  }) async {
    final req = http.Request('POST', _uri('/api/ai/chat'));
    req.headers.addAll(_authHeaders);
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);
    return (client ?? _http).send(req);
  }
}
