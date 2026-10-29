import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a notification sits in the launcher's notification centre, most important first.
enum NotifTier {
  now('Now'), // incoming / ongoing calls, alarms going off
  people('People'), // messages and conversations
  updates('Updates'), // everything else that asks for attention
  ongoing('Ongoing'), // music, downloads, navigation, running services
  quiet('Quiet'); // silent and low-importance

  const NotifTier(this.label);
  final String label;
}

/// One notification on the phone, as the launcher shows it (from NotificationFeed.kt).
class OneNotification {
  OneNotification._(Map m)
    : key = m['key'] as String,
      package = m['package'] as String,
      app = (m['app'] as String?) ?? '',
      work = m['work'] == true,
      title = (m['title'] as String?) ?? '',
      text = (m['text'] as String?) ?? '',
      bigText = m['bigText'] as String?,
      subText = m['subText'] as String?,
      lines = [for (final l in (m['lines'] as List?) ?? const []) l.toString()],
      messages = [
        for (final x in (m['messages'] as List?) ?? const [])
          if (x is Map) (sender: x['sender'] as String?, text: (x['text'] as String?) ?? '', time: DateTime.fromMillisecondsSinceEpoch((x['time'] as num?)?.toInt() ?? 0)),
      ],
      conversation = m['conversation'] as String?,
      time = DateTime.fromMillisecondsSinceEpoch((m['time'] as num?)?.toInt() ?? 0),
      category = m['category'] as String?,
      template = (m['template'] as String?) ?? '',
      ongoing = m['ongoing'] == true,
      clearable = m['clearable'] == true,
      summary = m['summary'] == true,
      group = m['group'] as String?,
      importance = (m['importance'] as num?)?.toInt() ?? 3,
      silent = m['silent'] == true,
      isConversation = m['conversationRank'] == true,
      color = (m['color'] as num?)?.toInt() ?? 0,
      progress = (m['progress'] as num?)?.toInt(),
      indeterminate = m['indeterminate'] == true,
      picture = m['picture'] as Uint8List?,
      largeIcon = m['largeIcon'] as Uint8List?,
      actions = [
        for (final a in (m['actions'] as List?) ?? const [])
          if (a is Map) (index: (a['index'] as num).toInt(), title: (a['title'] as String?) ?? '', reply: a['reply'] == true),
      ],
      canOpen = m['canOpen'] == true;

  final String key, package, app, title, text, template;
  final bool work, ongoing, clearable, summary, silent, isConversation, indeterminate, canOpen;
  final String? bigText, subText, conversation, category, group;
  final List<String> lines;
  final List<({String? sender, String text, DateTime time})> messages;
  final DateTime time;
  final int importance, color;
  final int? progress;
  final Uint8List? picture, largeIcon;
  final List<({int index, String title, bool reply})> actions;

  bool get isCall => category == 'call' || template == 'CallStyle';
  bool get isMessage => category == 'msg' || template == 'MessagingStyle' || isConversation || messages.isNotEmpty;
  bool get isMedia => category == 'transport' || template == 'MediaStyle' || template == 'DecoratedMediaCustomViewStyle';

  /// The text to show when opened up: the long text, inbox lines or the conversation.
  String get fullText => bigText?.isNotEmpty == true ? bigText! : (lines.isNotEmpty ? lines.join('\n') : text);

  /// The centre's priority rules: what deserves the top, what can wait.
  NotifTier get tier {
    if (isCall) return NotifTier.now;
    if ((category == 'alarm' || category == 'reminder' || category == 'event') && importance >= 4) return NotifTier.now;
    // What's running (music, downloads, navigation) is Ongoing even when the app posts it quietly.
    if (ongoing || isMedia || progress != null || category == 'progress' || category == 'navigation' || category == 'service' || category == 'transport') {
      return NotifTier.ongoing;
    }
    if (silent || importance <= 2) return NotifTier.quiet;
    if (isMessage) return NotifTier.people;
    return NotifTier.updates;
  }
}

/// The phone's notifications for the launcher's own notification centre: kept up to date as they
/// come and go, sorted by [NotifTier] then newest first, with the actions to answer them.
/// Needs Notification access (the same switch as Start's live tiles and badges).
class NotificationCenter extends ChangeNotifier {
  NotificationCenter._() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
  }
  static final instance = NotificationCenter._();

  static const _ch = MethodChannel('one_launcher/notifications');

  bool access = true;
  bool loaded = false;
  List<OneNotification> items = const [];

  /// The notifications by tier (empty tiers left out), each newest first. A group's summary is
  /// left out while its notifications are there.
  Map<NotifTier, List<OneNotification>> get byTier {
    final groups = <String>{for (final n in items) if (!n.summary && n.group != null) n.group!};
    final shown = items.where((n) => !(n.summary && groups.contains(n.group)) && (n.title.isNotEmpty || n.text.isNotEmpty || n.isMedia)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return {
      for (final t in NotifTier.values)
        if (shown.any((n) => n.tier == t)) t: shown.where((n) => n.tier == t).toList(),
    };
  }

  Future<void> refresh() async {
    try {
      access = await _ch.invokeMethod<bool>('hasAccess') ?? false;
      final raw = await _ch.invokeMethod<List>('list') ?? const [];
      items = [for (final m in raw) if (m is Map) OneNotification._(m)];
    } catch (_) {
      // Not on Android (the web preview): nothing to show.
    }
    loaded = true;
    notifyListeners();
  }

  Future<bool> open(OneNotification n) async => await _ch.invokeMethod<bool>('open', {'key': n.key}) ?? false;
  Future<bool> act(OneNotification n, int index, {String? reply}) async => await _ch.invokeMethod<bool>('action', {'key': n.key, 'index': index, 'reply': reply}) ?? false;
  Future<void> dismiss(OneNotification n) async {
    items = [for (final x in items) if (x.key != n.key) x]; // gone at once (the phone confirms)
    notifyListeners();
    await _ch.invokeMethod('dismiss', {'key': n.key});
  }

  Future<void> snooze(OneNotification n, Duration d) async {
    items = [for (final x in items) if (x.key != n.key) x];
    notifyListeners();
    await _ch.invokeMethod('snooze', {'key': n.key, 'ms': d.inMilliseconds});
  }

  Future<void> dismissAll() => _ch.invokeMethod('dismissAll');
}
