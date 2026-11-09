import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// One app found on the Play Store.
class PlayApp {
  const PlayApp({required this.id, required this.name, this.developer = '', this.icon, this.rating});
  final String id; // package name
  final String name, developer;
  final String? icon; // https URL of the square icon
  final double? rating;
}

/// Search → the Play Store's own results for what's typed (with "Play Store" on in Search in):
/// the apps its search page lists, read from that page (no key). What you type goes to Google
/// Play as you type, so they follow that setting. Unofficial, so it may change: any failure
/// just shows none.
class PlaySearch {
  PlaySearch._();

  static const max = 4;
  static final _cache = <String, List<PlayApp>>{};

  /// Up to [max] apps for [query], leaving out [skip] (the installed ones); empty when offline / on error.
  static Future<List<PlayApp>> fetch(String query, {Set<String> skip = const {}}) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    var found = _cache[q];
    if (found == null) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36';
      try {
        final uri = Uri.https('play.google.com', '/store/search', {'q': query.trim(), 'c': 'apps', 'hl': 'en'});
        final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) return const [];
        found = parse(await res.transform(utf8.decoder).join());
        if (_cache.length > 100) _cache.remove(_cache.keys.first);
        _cache[q] = found;
      } catch (_) {
        return const [];
      } finally {
        client.close(force: true);
      }
    }
    return [for (final a in found) if (!skip.contains(a.id)) a].take(max).toList();
  }

  static final _link = RegExp(r'href="/store/apps/details\?id=([A-Za-z0-9._]+)"');
  static final _icon = RegExp(r'<img src="(https://play-lh\.googleusercontent\.com/[^"=]+)=s\d+-rw"');
  static final _text = RegExp(r'>([^<>]+)<');
  static final _stars = RegExp(r'aria-label="Rated ([\d.]+) stars');

  /// The apps on a Play Store search page, in its order: each result's link, then its square
  /// icon, name and developer (the first texts after the icon) and rating.
  @visibleForTesting
  static List<PlayApp> parse(String html) {
    final out = <PlayApp>[];
    final seen = <String>{};
    final links = _link.allMatches(html).toList();
    for (final (i, m) in links.indexed) {
      final id = m.group(1)!;
      if (!seen.add(id)) continue;
      // This result's part of the page: up to the next other app's link.
      var end = html.length;
      for (final n in links.skip(i + 1)) {
        if (n.group(1) != id) {
          end = n.start;
          break;
        }
      }
      final part = html.substring(m.end, end.clamp(m.end, m.end + 6000));
      final icon = _icon.firstMatch(part);
      if (icon == null) continue;
      final texts = [
        for (final t in _text.allMatches(part.substring(icon.end)))
          if (t.group(1)!.trim().isNotEmpty) _unescape(t.group(1)!.trim()),
      ];
      if (texts.isEmpty) continue;
      out.add(
        PlayApp(
          id: id,
          name: texts[0],
          developer: texts.length > 1 ? texts[1] : '',
          icon: '${icon.group(1)}=s96-rw',
          rating: double.tryParse(_stars.firstMatch(part)?.group(1) ?? ''),
        ),
      );
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

/// The Play Store's apps for [query], fetched a moment after typing pauses, keeping the last
/// ones on screen until the new ones arrive. Builds nothing until it has some.
class PlayResults extends StatefulWidget {
  const PlayResults({super.key, required this.query, this.skip = const {}, required this.builder});
  final String query;
  final Set<String> skip; // installed apps: they show with the apps already
  final Widget Function(BuildContext context, List<PlayApp> apps) builder;

  @override
  State<PlayResults> createState() => _PlayResultsState();
}

class _PlayResultsState extends State<PlayResults> {
  List<PlayApp> _list = const [];
  Timer? _wait;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _ask(widget.query);
  }

  @override
  void didUpdateWidget(PlayResults old) {
    super.didUpdateWidget(old);
    if (old.query.trim() != widget.query.trim()) _ask(widget.query);
  }

  void _ask(String q) {
    _wait?.cancel();
    // A longer pause than Google's suggestions: each ask is a whole page.
    _wait = Timer(const Duration(milliseconds: 450), () async {
      final id = ++_asked;
      final list = await PlaySearch.fetch(q, skip: widget.skip);
      if (mounted && id == _asked) setState(() => _list = list); // a newer question wins
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _list.isEmpty ? const SizedBox.shrink() : widget.builder(context, _list);
}
