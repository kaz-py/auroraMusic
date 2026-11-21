import 'dart:io';

/// The single egress route for the YouTube stream path: InnerTube `player`,
/// `sw.js_data` and googlevideo all go through [client], so they leave by the
/// same proxy (googlevideo URLs are bound to the IP that resolved them).
///
/// Honours `https_proxy`/`http_proxy`/`no_proxy` (and upper case) like
/// dart:io, plus an http(s) `all_proxy` when the specific ones are unset.
/// SOCKS is not supported by dart:io: such a setting is reported by
/// [describe] and [warning] instead of being silently ignored. Loopback is
/// always direct (the local [AudioProxy] must never be proxied).
class UpstreamNetwork {
  UpstreamNetwork._();

  /// Process environment; tools and tests may replace it.
  static Map<String, String> environment = Platform.environment;

  /// Diagnostic sink (one line per event). `main.dart` wires `debugPrint`;
  /// the default drops lines so `dart run` tools and tests stay quiet.
  static void Function(String line) log = _drop;

  static void _drop(String _) {}

  static const _loopback = ['127.0.0.1', 'localhost', '::1'];

  static String? _get(String name) {
    final value =
        environment[name.toLowerCase()] ?? environment[name.toUpperCase()];
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  static bool _isHttpScheme(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        !lower.contains('://');
  }

  /// The environment dart:io sees, with `all_proxy` mapped and loopback
  /// added to `no_proxy`.
  static Map<String, String> effectiveEnvironment() {
    final https = _get('https_proxy');
    final http = _get('http_proxy');
    final all = _get('all_proxy');
    final mappedAll = all != null && _isHttpScheme(all) ? all : null;
    final noProxy = [
      ?_get('no_proxy'),
      ..._loopback,
    ].where((s) => s.isNotEmpty).join(',');
    String? usable(String? v) => v != null && _isHttpScheme(v) ? v : null;
    return {
      'https_proxy': ?usable(https ?? mappedAll),
      'http_proxy': ?usable(http ?? mappedAll),
      'no_proxy': noProxy,
    };
  }

  /// dart:io `findProxy` result for [uri] (`DIRECT` or `PROXY host:port`).
  static String findProxy(Uri uri) {
    if (_loopback.contains(uri.host)) return 'DIRECT';
    return HttpClient.findProxyFromEnvironment(
      uri,
      environment: effectiveEnvironment(),
    );
  }

  /// A client on the shared route. Callers own it and must close it.
  static HttpClient client({Duration? connectionTimeout}) {
    final c = HttpClient()..findProxy = findProxy;
    if (connectionTimeout != null) c.connectionTimeout = connectionTimeout;
    return c;
  }

  /// Human summary of the route for https traffic, without credentials.
  static String describe() {
    final route = findProxy(Uri.parse('https://music.youtube.com/'));
    final base = route == 'DIRECT'
        ? 'direct'
        : redact(route.replaceFirst('PROXY ', 'proxy '));
    final w = warning();
    return w == null ? base : '$base ($w)';
  }

  /// Set when a configured proxy cannot be honoured (SOCKS), so the stream
  /// path would bypass it: callers surface this instead of failing silently.
  static String? warning() {
    for (final name in ['https_proxy', 'http_proxy', 'all_proxy']) {
      final value = _get(name);
      if (value != null && !_isHttpScheme(value)) {
        final scheme = value.split('://').first;
        return '$name uses $scheme://, which Aurora cannot route: '
            'connecting directly';
      }
    }
    return null;
  }

  /// `user:pass@` removed from a proxy URL or route before it is logged.
  static String redact(String value) =>
      value.replaceAll(RegExp(r'[^\s/@]+@'), '***@');
}
