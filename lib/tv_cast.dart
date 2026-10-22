import 'dart:async';

import 'package:flutter/foundation.dart';

import 'one_stream.dart';
import 'prefs.dart';
import 'tv_remote.dart';

/// What happened to a request sent to the TV, in words for the title sheet.
typedef TvCastReply = ({bool ok, String message});

/// Phone → TV: "play / download this in One Stream on my TV", through the paired Android TV
/// remote (TvRemote). One Stream on the TV takes onestream://cast/play|download links and runs
/// its own source search; a source's hash / file / url only help it pick the same one.
abstract final class TvCast {
  /// The phone's prefs (the paired TV); set by the phone app at start.
  static Prefs? prefs;

  /// How long to wait for the TV to answer when the remote isn't connected yet.
  static Duration connectTimeout = const Duration(seconds: 4);

  /// How long the TV gets to say whether its screen is on, once connected.
  static Duration powerWait = const Duration(milliseconds: 1500);

  /// How long a TV that wasn't known to be on gets to wake (then one more try, [rewakeWait]).
  static Duration wakeWait = const Duration(seconds: 10);
  static Duration rewakeWait = const Duration(seconds: 6);

  /// After waking: a moment for the TV's home screen to be ready to take app links.
  static Duration settle = const Duration(seconds: 2);

  /// A TV is paired (the phone remote is set up).
  static bool get paired => prefs?.tvHost != null;

  /// The paired TV's name ("Kame TV").
  static String get tvName => prefs?.tvName ?? 'TV';

  /// The link for One Stream on the TV: `onestream://cast/play|download?type=…&tmdb=…`, plus
  /// season / episode (series) and the source's hash / file / url when known.
  static String link(String action, OneStreamTitle title, {int? season, int? episode, OneStreamSource? source}) {
    final url = source?.url;
    final params = <String, Object?>{
      'type': title.type,
      'tmdb': title.tmdb,
      'season': season,
      'episode': episode,
      'hash': source?.hash,
      'file': source?.hash == null ? null : source?.file,
      // A link only the phone can open (One Stream's own local server) means nothing on the TV.
      'url': url != null && !_local(url) ? url : null,
    };
    final query = [
      for (final e in params.entries)
        if (e.value != null) '${e.key}=${Uri.encodeQueryComponent('${e.value}')}',
    ].join('&');
    return 'onestream://cast/$action?$query';
  }

  static bool _local(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'localhost' || host.startsWith('127.') || host == '::1' || host == '[::1]';
  }

  /// Plays [title] (the episode, for a series) in One Stream on the TV.
  static Future<TvCastReply> castPlay(OneStreamTitle title, {int? season, int? episode, OneStreamSource? source}) =>
      _send(link('play', title, season: season, episode: episode, source: source), 'Playing on');

  /// Starts downloading [title] (the episode, for a series) in One Stream on the TV.
  static Future<TvCastReply> castDownload(OneStreamTitle title, {int? season, int? episode, OneStreamSource? source}) =>
      _send(link('download', title, season: season, episode: episode, source: source), 'Downloading on');

  /// Wake, then play. A TV in standby often says nothing about its screen, and a link sent to a
  /// sleeping TV is lost — so the wake key always goes first (it never turns a TV off). A TV not
  /// known to be on gets time to wake (and a second wake after a reconnect), then a moment to
  /// settle; waking can reset its network, so a failed send reconnects once and resends.
  static Future<TvCastReply> _send(String link, String doing) async {
    final host = prefs?.tvHost;
    final name = tvName;
    final failed = (ok: false, message: 'Couldn’t reach $name — is it on?');
    if (host == null) return (ok: false, message: 'Pair a TV first');
    final tv = TvRemote.instance;
    if (!await _connect(tv, host)) return failed;
    await _until(tv.power, (on) => on != null, powerWait);
    final wasOn = tv.power.value == true;
    await tv.key(TvKey.wakeup);
    if (!wasOn) {
      if (!await _until(tv.power, (on) => on == true, wakeWait)) {
        if (await _connect(tv, host, again: true)) {
          await tv.key(TvKey.wakeup);
          await _until(tv.power, (on) => on == true, rewakeWait);
        }
      }
      await Future<void>.delayed(settle);
    }
    if (await tv.appLink(link) != null) {
      if (!await _connect(tv, host, again: true) || await tv.appLink(link) != null) return failed;
    }
    return (ok: true, message: '$doing $name');
  }

  /// Connects the remote (or, with [again], connects afresh); true once the TV takes us as its remote.
  static Future<bool> _connect(TvRemote tv, String host, {bool again = false}) async {
    if (!again && tv.status.value == TvStatus.connected) return true;
    final err = await tv.connect(host).timeout(connectTimeout, onTimeout: () => 'timed out');
    if (err != null) return false;
    return _until(tv.status, (s) => s == TvStatus.connected, connectTimeout);
  }

  /// Waits until [test] holds for [value] (true), or [timeout] passes (false).
  static Future<bool> _until<T>(ValueListenable<T> value, bool Function(T) test, Duration timeout) {
    if (test(value.value)) return Future.value(true);
    final done = Completer<bool>();
    late final Timer timer;
    void check() {
      if (!done.isCompleted && test(value.value)) {
        timer.cancel();
        done.complete(true);
      }
    }

    timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete(false);
    });
    value.addListener(check);
    return done.future.whenComplete(() => value.removeListener(check));
  }
}
