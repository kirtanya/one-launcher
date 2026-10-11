import 'package:flutter/material.dart';

import 'apps.dart';

/// A group of similar apps shown as one card in the app view.
class Folder {
  const Folder(this.id, this.name, this.icon, this.keywords, {this.categories = const []});
  final String id;
  final String name;
  final IconData icon;
  final List<String> keywords; // matched against package id + app name
  final List<int> categories; // Android ApplicationInfo.CATEGORY_* values
}

/// Order here = order on screen. "Other" is always last.
// dart format off
const folders = <Folder>[
  Folder('social', 'Social', Icons.chat_bubble_outline_rounded, [
    'whatsapp', 'telegram', 'instagram', 'facebook', 'katana', 'messenger', 'orca', 'snapchat', 'twitter', 'threads', 'barcelona',
    'discord', 'signal', 'messaging', 'messages', 'linkedin', 'reddit', 'sharechat', 'dialer', 'contacts', 'truecaller', 'mohalla',
    'pinterest', 'tinder', 'bumble', 'hinge',
  ], categories: [4]),
  Folder('work', 'Work', Icons.work_outline_rounded, [
    'slack', 'gmail', 'outlook', 'teams', 'zoom', 'meet', 'tachyon', 'calendar', 'apps.docs', 'drive', 'docs', 'sheets',
    'slides', 'notion', 'figma', 'jira', 'atlassian', 'asana', 'linear', 'keep', 'todo', 'office', 'zoho', 'claude', 'anthropic', 'chatgpt',
    'openai', 'gemini', 'bard', 'perplexity', 'copilot', 'dropbox', 'trello', 'miro', 'webex', 'clickup', 'confluence', 'github', 'mail',
    'keka', 'capacities',
  ]),
  Folder('money', 'Money', Icons.account_balance_wallet_outlined, [
    'pay', 'upi', 'bank', 'paytm', 'phonepe', 'gpay', 'nbu.paisa', 'wallet', 'cred', 'dreamplug', 'zerodha', 'kite', 'groww', 'upstox',
    'lemonn', 'coinswitch', 'finance', 'invest', 'sbi', 'hdfc', 'icici', 'axis', 'kotak', 'splitwise', 'autosplit', 'money', 'mutual',
    'angel', 'dhan', 'indmoney', 'indwealth', 'jupiter', 'slice', 'stockgro', 'sensibull', 'smallcase', 'walnut', 'axio', 'pnb',
  ]),
  Folder('media', 'Watch & Listen', Icons.play_circle_outline_rounded, [
    'music', 'spotify', 'youtube', 'netflix', 'primevideo', 'avod', 'hotstar', 'jiocinema', 'sonyliv', 'zee5', 'photos', 'gallery',
    'camera', 'podcast', 'audible', 'saavn', 'gaana', 'wynk', 'video', 'player', 'snapseed', 'lightroom', 'vsco', 'capcut', 'shazam',
    'pocketfm', 'kukufm', 'nuvio', 'vlc', 'stremio',
  ], categories: [1, 2, 3]),
  Folder('shopping', 'Shop & Services', Icons.shopping_bag_outlined, [
    'amazon.mshop', 'flipkart', 'myntra', 'swiggy', 'zomato', 'blinkit', 'grofers', 'zepto', 'bigbasket', 'instamart', 'meesho', 'ajio',
    'nykaa', 'dunzo', 'tatacliq', 'decathlon', 'ikea', 'urbanclap', 'urban company', 'dmart', 'jiomart', 'licious', 'eatsure', 'eatclub',
    'magicpin', 'adidas', 'nike', 'snabbit', 'pronto', 'waterwala', 'drinkprime', 'rentomojo', 'delhivery', 'district', 'shop',
  ]),
  Folder('travel', 'Travel', Icons.explore_outlined, [
    'maps', 'uber', 'olacabs', 'rapido', 'irctc', 'makemytrip', 'goibibo', 'airbnb', 'booking', 'indigo', 'cleartrip', 'redbus',
    'metro', 'waze', 'ixigo', 'yatra', 'agoda', 'skyscanner', 'blusmart', 'airindia', 'akasa',
  ], categories: [6]),
  Folder('reading', 'News & Reading', Icons.menu_book_outlined, [
    'news', 'inshorts', 'kindle', 'medium', 'pocket', 'quora', 'economictimes', 'moneycontrol', 'flipboard', 'books', 'wattpad', 'substack',
  ], categories: [5]),
  Folder('games', 'Games', Icons.sports_esports_outlined, [
    'game', 'chess', 'ludo', 'puzzle', 'supercell', 'rummy', 'dream11',
  ], categories: [0]),
  Folder('life', 'Health & Home', Icons.favorite_border_rounded, [
    'health', 'fitbit', 'shealth', 'pazcare', 'daylio', 'headspace', 'calm.', 'cult', 'healthify', 'strava', 'sleep', 'meditat',
    'practo', 'pharmeasy', '1mg', 'alexa', 'chromecast', 'smart home', 'wearable', 'watchmanager', 'realme', 'mi.fit', 'noise', 'boat',
  ]),
  Folder('tools', 'Tools', Icons.tune_rounded, [
    'settings', 'deskclock', 'clock', 'calculator', 'files', 'documentsui', 'chrome', 'browser', 'brave', 'firefox', 'vending',
    'weather', 'recorder', 'authenticator', 'vpn', 'security', 'safety', 'googlequicksearchbox', 'assistant', 'lens', 'translate',
    'wellbeing', 'print', 'scanner', 'launcher', 'easymover', 'nowplaying', 'apps.adm', 'subscriptions', 'betterbug', 'digilocker',
    'nonet', 'microg', 'revanced', 'ntiles', 'android.stk', 'torr', 'sendfiles', 'developer',
  ], categories: [8]),
];
// dart format on

const other = Folder('other', 'Everything else', Icons.apps_rounded, []);

/// Virtual folder of the apps opened most from One Launcher. Always first, open by default.
const mostUsed = Folder('recent', 'Most used', Icons.bolt_rounded, []);

Folder folderById(String id) => folders.where((f) => f.id == id).firstOrNull ?? other;

/// Picks a folder: the user's own choice, then keywords, then Android's category,
/// then "Tools" for built-in and "productivity" apps, else "Everything else".
/// Android's Productivity category (7) is a catch-all many apps pick, so it never decides Work.
Folder folderFor(AppEntry app, Map<String, String> overrides) {
  final picked = overrides[app.package];
  if (picked != null) return folderById(picked);
  // The automatic folder never changes for an app, so match keywords only once.
  return _autoFolders.putIfAbsent('${app.package}|${app.label}|${app.category}|${app.system}', () => _autoFolder(app));
}

final _autoFolders = <String, Folder>{};

Folder _autoFolder(AppEntry app) {
  final hay = '${app.package} ${app.label}'.toLowerCase();
  // Specific folders first, utilities last ("files" shouldn't beat "Drive").
  final tools = folderById('tools');
  for (final f in [...folders.where((f) => f != tools), tools]) {
    if (f.keywords.any(hay.contains)) return f;
  }
  for (final f in folders) {
    if (f.categories.contains(app.category)) return f;
  }
  if (app.system || app.category == 7) return tools;
  return other;
}

/// Groups apps by folder, in the user's order (else the default order), dropping empty folders.
List<(Folder, List<AppEntry>)> groupApps(List<AppEntry> apps, Map<String, String> overrides, {List<String> order = const []}) {
  final map = <String, List<AppEntry>>{};
  for (final a in apps) {
    map.putIfAbsent(folderFor(a, overrides).id, () => []).add(a);
  }
  final all = [...folders, other];
  int rank(Folder f) {
    final i = order.indexOf(f.id);
    return i < 0 ? order.length + all.indexOf(f) : i;
  }

  return [
    for (final f in all..sort((a, b) => rank(a).compareTo(rank(b))))
      if (map[f.id]?.isNotEmpty ?? false) (f, map[f.id]!),
  ];
}
