import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps.dart';
import '../third/tactile/parts.dart';
import '../third/tactile/tactile.dart';
import '../ui/components.dart';
import '../ui/ds.dart';
import '../ui/motion.dart';
import '../widgets.dart';
import 'notification_center.dart';

/// The launcher's own notification centre (for now a tab in the bottom bar, while it's being
/// built): every notification in One's design, sorted by what matters — calls first, then
/// people, updates, what's running, and the quiet ones. Tap to open, use its buttons (reply in
/// place), swipe away, long-press to snooze.
///
/// [work]: the phone has a work profile. Its notifications reach this page only if the
/// organisation allows it (its device policy can keep notification readers out of the work
/// profile), so a card at the end opens the phone's own shade, where they always show.
Future<Object?> showNotificationCenter(BuildContext context, {bool work = false}) {
  NotificationCenter.instance.refresh();
  return showOneSheetWith(context, height: MediaQuery.sizeOf(context).height, fill: true, builder: (ctx) => _NotificationsPage(work: work));
}

class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage({required this.work});
  final bool work;

  @override
  Widget build(BuildContext context) {
    final c = NotificationCenter.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tiers = c.byTier;
        final count = tiers.values.fold(0, (a, l) => a + l.length);
        final clearable = c.items.any((n) => n.clearable);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SheetHeader(
                      title: 'Notifications',
                      subtitle: !c.loaded ? 'Loading…' : (count == 0 ? 'All caught up' : '$count on your phone'),
                    ),
                  ),
                  if (clearable)
                    TextButton(
                      onPressed: () async {
                        if (!await confirmReset(context, title: 'Clear all notifications?', body: 'Ongoing ones (music, calls, downloads) stay.', action: 'Clear all')) return;
                        HapticFeedback.mediumImpact();
                        c.dismissAll();
                      },
                      child: Text(DS.cased('Clear all'), style: DS.rowTitle.copyWith(fontSize: 14)),
                    ),
                ],
              ),
            ),
            if (c.loaded && !c.access)
              _NoAccess()
            else if (c.loaded && count == 0)
              Padding(
                padding: const EdgeInsets.all(DS.s32),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 48, color: DS.inkFaint),
                    const SizedBox(height: DS.s12),
                    Text('Nothing new', style: DS.rowSub),
                  ],
                ),
              ),
            for (final MapEntry(key: tier, value: list) in tiers.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s16, DS.s24, DS.s8),
                child: Text(
                  DS.metro ? tier.label.toLowerCase() : tier.label.toUpperCase(),
                  style: DS.eyebrow.copyWith(color: DS.inkMuted, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600),
                ),
              ),
              for (final n in list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, DS.s8),
                  child: n.isCall ? _CallCard(n: n) : _NotifCard(key: ValueKey(n.key), n: n),
                ),
            ],
            if (work && c.access && !c.items.any((n) => n.work && n.package != 'android')) const _WorkProfile(),
            const SizedBox(height: DS.s16),
          ],
        );
      },
    );
  }
}

/// The work profile's notifications aren't shared with this page (the organisation's policy):
/// say so, and open the phone's shade, which shows them.
class _WorkProfile extends StatelessWidget {
  const _WorkProfile();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, 0),
    child: Material(
      color: DS.cardMuted,
      borderRadius: BorderRadius.circular(DS.rMedia),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Apps.instance.openNotifications();
        },
        child: Padding(
          padding: const EdgeInsets.all(DS.s16),
          child: Row(
            children: [
              Icon(Icons.work_outline_rounded, color: DS.ink),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Work notifications', style: DS.rowTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Your organisation keeps them private to the work profile. Tap to see them in your phone’s notifications.', style: DS.rowSub),
                  ],
                ),
              ),
              const SizedBox(width: DS.s8),
              Icon(Icons.open_in_new_rounded, size: 18, color: DS.inkFaint),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NoAccess extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(DS.s16, DS.s16, DS.s16, 0),
    child: Material(
      color: DS.cardMuted,
      borderRadius: BorderRadius.circular(DS.rMedia),
      child: Padding(
        padding: const EdgeInsets.all(DS.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Allow notification access', style: DS.rowTitle),
            const SizedBox(height: DS.s4),
            Text('So One Launcher can show your notifications here. They stay on your phone.', style: DS.rowSub),
            const SizedBox(height: DS.s12),
            FilledButton(onPressed: Apps.instance.openNotificationAccess, child: Text(DS.cased('Open settings'))),
          ],
        ),
      ),
    ),
  );
}

/// "3m", "2h", "Yesterday"…
String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays}d';
}

/// The app's icon (the notification's own picture when it has one, like a contact's photo).
class _NotifIcon extends StatelessWidget {
  const _NotifIcon({required this.n, this.size = 40});
  final OneNotification n;
  final double size;

  static final _icons = <String, Future<Uint8List?>>{};

  @override
  Widget build(BuildContext context) {
    final own = n.largeIcon;
    if (own != null) {
      return ClipOval(child: Image.memory(own, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true));
    }
    return FutureBuilder<Uint8List?>(
      future: _icons.putIfAbsent(n.package, () => Apps.instance.icon(n.package)),
      builder: (context, s) => s.data == null
          ? CircleAvatar(
              radius: size / 2,
              backgroundColor: DS.hero,
              child: Text(n.app.isEmpty ? '•' : n.app[0], style: DS.rowTitle.copyWith(color: DS.heroInk)),
            )
          : Image.memory(s.data!, width: size, height: size, gaplessPlayback: true),
    );
  }
}

/// One notification: app · time, title, text (tap the arrow for all of it), its buttons; tap to
/// open, swipe away, long-press to snooze. A reply button opens a text box in place.
class _NotifCard extends StatefulWidget {
  const _NotifCard({super.key, required this.n});
  final OneNotification n;

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  bool _open = false;
  int? _replying; // the reply action's index while its box is open
  final _reply = TextEditingController();

  OneNotification get n => widget.n;
  NotificationCenter get c => NotificationCenter.instance;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _snooze() async {
    HapticFeedback.mediumImpact();
    final picked = await showOneSheetWith(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DS.s24, 0, DS.s24, DS.s8),
            child: SheetHeader(title: 'Snooze', subtitle: n.title.isEmpty ? n.app : n.title, yours: true),
          ),
          for (final (label, d) in const [('15 minutes', Duration(minutes: 15)), ('1 hour', Duration(hours: 1)), ('4 hours', Duration(hours: 4))])
            ListTile(
              leading: Icon(Icons.snooze_rounded, color: DS.ink),
              title: Text(label, style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, d),
            ),
        ],
      ),
    );
    if (picked is Duration) c.snooze(n, picked);
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    final i = _replying;
    if (text.isEmpty || i == null) return;
    HapticFeedback.selectionClick();
    final ok = await c.act(n, i, reply: text);
    if (!mounted) return;
    setState(() {
      _replying = null;
      _reply.clear();
    });
    if (!ok) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(DS.cased('Couldn’t send the reply'))));
  }

  @override
  Widget build(BuildContext context) {
    final more = n.fullText.length > n.text.length || n.messages.length > 1 || n.picture != null;
    final card = _plate(Material(
      color: DS.third ? Colors.transparent : DS.cardMuted,
      borderRadius: BorderRadius.circular(DS.rMedia),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: n.canOpen
            ? () {
                HapticFeedback.selectionClick();
                c.open(n);
              }
            : null,
        onLongPress: _snooze,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DS.s16, DS.s12, DS.s8, DS.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NotifIcon(n: n),
                  const SizedBox(width: DS.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${n.app}${n.work ? ' · Work' : ''} · ${_ago(n.time)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DS.rowSub.copyWith(fontSize: 12),
                        ),
                        if (n.title.isNotEmpty)
                          Text(n.title, maxLines: _open ? 3 : 1, overflow: TextOverflow.ellipsis, style: DS.rowTitle.copyWith(fontSize: 15)),
                        if (_open && n.messages.length > 1)
                          for (final m in n.messages.reversed.take(6).toList().reversed)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (m.sender != null) TextSpan(text: '${m.sender}  ', style: DS.rowSub.copyWith(color: DS.ink, fontWeight: FontWeight.w600)),
                                    TextSpan(text: m.text),
                                  ],
                                ),
                                style: DS.rowSub,
                              ),
                            )
                        else if (n.text.isNotEmpty || n.fullText.isNotEmpty)
                          Text(_open ? n.fullText : n.text, maxLines: _open ? 12 : 2, overflow: TextOverflow.ellipsis, style: DS.rowSub),
                      ],
                    ),
                  ),
                  if (more)
                    IconButton(
                      tooltip: _open ? 'Show less' : 'Show more',
                      onPressed: () => setState(() => _open = !_open),
                      icon: AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: Motion.snapDuration,
                        child: Icon(Icons.expand_more_rounded, color: DS.inkMuted),
                      ),
                    ),
                ],
              ),
              if (n.progress != null || n.indeterminate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, DS.s8, DS.s8, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: n.indeterminate ? null : (n.progress! / 100), minHeight: 4, color: DS.hero, backgroundColor: DS.hairline),
                  ),
                ),
              if (_open && n.picture != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, DS.s8, DS.s8, 0),
                  child: ClipRRect(borderRadius: BorderRadius.circular(DS.s12), child: Image.memory(n.picture!, fit: BoxFit.cover)),
                ),
              if (_replying != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, DS.s8, 0, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reply,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          cursorColor: DS.ink,
                          style: DS.rowTitle.copyWith(fontWeight: FontWeight.w400, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Reply',
                            hintStyle: DS.rowSub,
                            filled: true,
                            fillColor: DS.card,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.s24), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      IconButton(tooltip: 'Send', onPressed: _send, icon: Icon(Icons.send_rounded, color: DS.ink)),
                    ],
                  ),
                )
              else if (n.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(44, DS.s4, 0, 0),
                  child: Wrap(
                    spacing: DS.s4,
                    children: [
                      for (final a in n.actions)
                        TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            if (a.reply) {
                              setState(() => _replying = a.index);
                            } else {
                              c.act(n, a.index);
                            }
                          },
                          child: Text(a.title, style: DS.rowTitle.copyWith(fontSize: 14, color: DS.ink)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    if (!n.clearable) return card;
    // (Tactile: a plate; it slides away like a card pulled off a tray.)
    return Dismissible(
      key: ValueKey('d:${n.key}'),
      onDismissed: (_) {
        HapticFeedback.lightImpact();
        c.dismiss(n);
      },
      child: card,
    );
  }
}

/// Tactile: a notification is a moulded plate (lit top edge, soft shadow); others as they are.
Widget _plate(Widget child, {double? radius}) => DS.third
    ? DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? DS.rMedia),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(Tactile.plate, Colors.white, Tactile.dark ? .04 : .35)!, Tactile.plate],
            stops: const [0, .1],
          ),
          border: Border.all(color: Tactile.rim, width: .6),
          boxShadow: Tactile.plateShadow,
        ),
        child: child,
      )
    : child;

/// A call: the caller big, with the call's own buttons (Answer / Decline / Hang up…) as large
/// round buttons — green to pick up, red to end.
class _CallCard extends StatelessWidget {
  const _CallCard({required this.n});
  final OneNotification n;

  static bool _isEnd(String t) => RegExp('decline|reject|hang|end|dismiss', caseSensitive: false).hasMatch(t);
  static bool _isAnswer(String t) => RegExp('answer|accept|pick', caseSensitive: false).hasMatch(t);

  @override
  Widget build(BuildContext context) {
    final c = NotificationCenter.instance;
    return Material(
      color: DS.hero,
      borderRadius: BorderRadius.circular(DS.rCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: n.canOpen ? () => c.open(n) : null,
        child: Padding(
          padding: const EdgeInsets.all(DS.s20),
          child: Column(
            children: [
              _NotifIcon(n: n, size: 64),
              const SizedBox(height: DS.s12),
              Text(n.title.isEmpty ? 'Call' : n.title, textAlign: TextAlign.center, style: DS.title.copyWith(fontSize: 24, color: DS.heroInk)),
              const SizedBox(height: DS.s4),
              Text(
                [n.text, n.app].where((s) => s.isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                style: DS.rowSub.copyWith(color: DS.heroInk.withValues(alpha: .75)),
              ),
              if (n.actions.isNotEmpty) ...[
                const SizedBox(height: DS.s20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final a in n.actions)
                      Column(
                        children: [
                          if (DS.third) // Tactile: big round keys, green / red caps
                            TKey(
                              width: 60,
                              height: 60,
                              radius: 30,
                              tint: _isEnd(a.title) ? const Color(0xFFD8443F) : (_isAnswer(a.title) ? const Color(0xFF3E9B57) : null),
                              onTap: () => c.act(n, a.index),
                              child: Icon(
                                _isEnd(a.title) ? Icons.call_end_rounded : (_isAnswer(a.title) ? Icons.call_rounded : Icons.more_horiz_rounded),
                                color: _isEnd(a.title) || _isAnswer(a.title) ? Colors.white : Tactile.ink,
                              ),
                            )
                          else
                          FloatingActionButton(
                            heroTag: null,
                            elevation: 0,
                            backgroundColor: _isEnd(a.title)
                                ? const Color(0xFFE5484D)
                                : _isAnswer(a.title)
                                ? const Color(0xFF2EA043)
                                : DS.card,
                            foregroundColor: _isEnd(a.title) || _isAnswer(a.title) ? Colors.white : DS.ink,
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              c.act(n, a.index);
                            },
                            child: Icon(
                              _isEnd(a.title)
                                  ? Icons.call_end_rounded
                                  : _isAnswer(a.title)
                                  ? Icons.call_rounded
                                  : Icons.more_horiz_rounded,
                            ),
                          ),
                          const SizedBox(height: DS.s8),
                          Text(a.title, style: DS.rowSub.copyWith(color: DS.heroInk, fontSize: 13)),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
