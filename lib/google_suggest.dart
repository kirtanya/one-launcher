import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Search → Google's suggestions for what's typed (with "Search Google" on in Search in): the
/// same list the Google search box drops down, from Google's public autocomplete. No key; what
/// you type goes to Google as you type (that's how they're made), so they follow that setting.
/// Unofficial, so it may change: any failure just shows none.
class GoogleSuggest {
  GoogleSuggest._();

  static const max = 5;
  static final _cache = <String, List<String>>{};

  /// Up to [max] suggestions for [query] (not the query itself); empty when offline / on error.
  static Future<List<String>> fetch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final kept = _cache[q];
    if (kept != null) return kept;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri.https('suggestqueries.google.com', '/complete/search', {'client': 'firefox', 'ie': 'utf-8', 'oe': 'utf-8', 'q': query.trim()});
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      // ["query", ["suggestion", …], …]
      final list = [
        for (final s in (body is List && body.length > 1 && body[1] is List) ? body[1] as List : const [])
          if (s is String && s.trim().toLowerCase() != q) s.trim(),
      ].take(max).toList();
      if (_cache.length > 200) _cache.remove(_cache.keys.first);
      return _cache[q] = list;
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }
}

/// Google's suggestions for [query], fetched a moment after typing pauses (so not every letter
/// asks), keeping the last ones on screen until the new ones arrive. Builds nothing until it
/// has some.
class GoogleSuggestions extends StatefulWidget {
  const GoogleSuggestions({super.key, required this.query, required this.builder});
  final String query;
  final Widget Function(BuildContext context, List<String> suggestions) builder;

  @override
  State<GoogleSuggestions> createState() => _GoogleSuggestionsState();
}

class _GoogleSuggestionsState extends State<GoogleSuggestions> {
  List<String> _list = const [];
  Timer? _wait;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _ask(widget.query, now: true);
  }

  @override
  void didUpdateWidget(GoogleSuggestions old) {
    super.didUpdateWidget(old);
    if (old.query.trim() != widget.query.trim()) _ask(widget.query);
  }

  void _ask(String q, {bool now = false}) {
    _wait?.cancel();
    _wait = Timer(now ? Duration.zero : const Duration(milliseconds: 220), () async {
      final id = ++_asked;
      final list = await GoogleSuggest.fetch(q);
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
