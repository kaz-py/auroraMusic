import 'lastfm_client.dart';

enum StatsRange {
  week('7day', '7 días'),
  month('1month', 'Mes'),
  quarter('3month', '3 meses'),
  year('12month', 'Año'),
  all('overall', 'Todo');

  const StatsRange(this.api, this.label);
  final String api, label;
}

class StatItem {
  const StatItem(this.name, this.count, {this.subtitle});
  final String name;
  final int count;
  final String? subtitle;

  Map<String, Object?> toJson() => {'n': name, 'c': count, 's': subtitle};
  static StatItem fromJson(Map j) =>
      StatItem(j['n'] as String, j['c'] as int, subtitle: j['s'] as String?);
}

/// Pista reciente del perfil; [at] es Unix UTC o `null` si suena ahora.
class RecentItem {
  const RecentItem(this.title, this.artist, {this.at});
  final String title, artist;
  final int? at;

  Map<String, Object?> toJson() => {'t': title, 'a': artist, 'at': at};
  static RecentItem fromJson(Map j) =>
      RecentItem(j['t'] as String, j['a'] as String, at: j['at'] as int?);
}

class ListenStats {
  const ListenStats({
    this.totalListens = 0,
    this.recordings = const [],
    this.artists = const [],
    this.recent = const [],
  });
  final int totalListens;
  final List<StatItem> recordings, artists;
  final List<RecentItem> recent;

  StatItem? get topTrack => recordings.isEmpty ? null : recordings.first;
  StatItem? get topArtist => artists.isEmpty ? null : artists.first;

  Map<String, Object?> toJson() => {
    't': totalListens,
    'r': [for (final i in recordings) i.toJson()],
    'a': [for (final i in artists) i.toJson()],
    'rc': [for (final i in recent) i.toJson()],
  };

  static ListenStats? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return ListenStats(
        totalListens: j['t'] as int,
        recordings: [
          for (final i in (j['r'] as List)) StatItem.fromJson(i as Map),
        ],
        artists: [
          for (final i in (j['a'] as List)) StatItem.fromJson(i as Map),
        ],
        recent: [
          for (final i in (j['rc'] as List)) RecentItem.fromJson(i as Map),
        ],
      );
    } on Object {
      return null;
    }
  }
}

/// Pista de otro artista (similares) lista para emparejar con YouTube.
class LfmTrack {
  const LfmTrack(this.artist, this.title);
  final String artist, title;
}

/// Parseo tolerante de las respuestas de Last.fm: forma inesperada => vacío.
/// Con format=json los números llegan como texto y una lista de un solo
/// elemento puede llegar como objeto.
class LfmParser {
  static List<Map> _list(Object? v) => v is List
      ? [
          for (final i in v)
            if (i is Map) i,
        ]
      : v is Map
      ? [v]
      : const [];

  static Object? _at(Object? j, String root, String key) =>
      j is Map && j[root] is Map ? (j[root] as Map)[key] : null;

  static int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

  static String? _name(Object? v) => v is String
      ? v
      : v is Map
      ? (v['name'] ?? v['#text']) as String?
      : null;

  static List<StatItem> topTracks(Object? j) => [
    for (final t in _list(_at(j, 'toptracks', 'track')))
      if (t['name'] is String)
        StatItem(
          t['name'] as String,
          _int(t['playcount']),
          subtitle: _name(t['artist']),
        ),
  ];

  static List<StatItem> topArtists(Object? j) => [
    for (final a in _list(_at(j, 'topartists', 'artist')))
      if (a['name'] is String)
        StatItem(a['name'] as String, _int(a['playcount'])),
  ];

  static List<RecentItem> recent(Object? j) => [
    for (final t in _list(_at(j, 'recenttracks', 'track')))
      if (t['name'] is String && _name(t['artist']) != null)
        RecentItem(
          t['name'] as String,
          _name(t['artist'])!,
          at: t['@attr'] is Map && (t['@attr'] as Map)['nowplaying'] == 'true'
              ? null
              : (t['date'] is Map ? _int((t['date'] as Map)['uts']) : null),
        ),
  ];

  static int playcount(Object? j) => _int(_at(j, 'user', 'playcount'));

  static List<LfmTrack> similarTracks(Object? j) => [
    for (final t in _list(_at(j, 'similartracks', 'track')))
      if (t['name'] is String && _name(t['artist']) != null)
        LfmTrack(_name(t['artist'])!, t['name'] as String),
  ];

  static List<String> similarArtists(Object? j) => [
    for (final a in _list(_at(j, 'similarartists', 'artist')))
      if (a['name'] is String) a['name'] as String,
  ];

  /// Etiquetas que no describen un género.
  static const _noiseTags = {
    'seen live',
    'favorites',
    'favourites',
    'favorite',
    'love',
    'awesome',
    'beautiful',
  };

  /// Hasta 5 etiquetas de género (minúsculas, `count >= 10`).
  static List<String> artistTopTags(Object? j) => [
    for (final t in _list(_at(j, 'toptags', 'tag')))
      if (t['name'] is String &&
          _int(t['count']) >= 10 &&
          !_noiseTags.contains((t['name'] as String).trim().toLowerCase()))
        (t['name'] as String).trim().toLowerCase(),
  ].take(5).toList();
}

extension LastfmReads on LastfmClient {
  Future<List<LfmTrack>> similarTracks(String artist, String title) async =>
      LfmParser.similarTracks(
        await request('track.getSimilar', {
          'artist': artist,
          'track': title,
          'autocorrect': '1',
          'limit': '20',
        }),
      );

  Future<List<String>> similarArtists(String artist) async =>
      LfmParser.similarArtists(
        await request('artist.getSimilar', {
          'artist': artist,
          'autocorrect': '1',
          'limit': '10',
        }),
      );

  Future<List<String>> artistTopTags(String artist) async =>
      LfmParser.artistTopTags(
        await request('artist.getTopTags', {
          'artist': artist,
          'autocorrect': '1',
        }),
      );

  /// Pistas más populares de [artist] (`artist.getTopTracks`).
  Future<List<LfmTrack>> artistTopTracks(
    String artist, {
    int limit = 2,
  }) async => [
    for (final t in LfmParser.topTracks(
      await request('artist.getTopTracks', {
        'artist': artist,
        'autocorrect': '1',
        'limit': '$limit',
      }),
    ))
      LfmTrack(artist, t.name),
  ];

  /// Estadísticas públicas del usuario. Si una parte falla se devuelve el
  /// resto; el límite de peticiones se propaga.
  Future<ListenStats> userStats(String user, StatsRange range) async {
    Future<Object?> get(
      String method, [
      Map<String, String> extra = const {},
    ]) async {
      try {
        return await request(method, {'user': user, ...extra});
      } on LastfmException catch (e) {
        if (e.rateLimited) rethrow;
        return null;
      }
    }

    final p = range.api;
    final info = await get('user.getInfo');
    final tracks = await get('user.getTopTracks', {'period': p, 'limit': '10'});
    final artists = await get('user.getTopArtists', {
      'period': p,
      'limit': '10',
    });
    final recent = await get('user.getRecentTracks', {'limit': '10'});
    return ListenStats(
      totalListens: LfmParser.playcount(info),
      recordings: LfmParser.topTracks(tracks),
      artists: LfmParser.topArtists(artists),
      recent: LfmParser.recent(recent),
    );
  }
}
