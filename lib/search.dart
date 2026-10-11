import 'apps.dart';

/// Apps matching [query], best first: name starts with it, then a word starts with it,
/// then it appears anywhere. Hidden apps are included so they stay findable.
List<AppEntry> searchApps(List<AppEntry> apps, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  int rank(AppEntry a) {
    final l = a.label.toLowerCase();
    if (l.startsWith(q)) return 0;
    if (l.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
    if (l.contains(q)) return 2;
    return 3;
  }

  return apps.where((a) => rank(a) < 3).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
}
