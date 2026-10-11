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
const folders = <Folder>[
  Folder(
    'social',
    'Social',
    Icons.chat_bubble_outline_rounded,
    [
      'whatsapp',
      'telegram',
      'instagram',
      'facebook',
      'katana',
      'messenger',
      'orca',
      'snapchat',
      'twitter',
      'threads',
      'barcelona',
      'discord',
      'signal',
      'messaging',
      'messages',
      'linkedin',
      'reddit',
      'sharechat',
      'dialer',
      'contacts',
      'moj',
      'pinterest',
      'tinder',
      'bumble',
      'hinge',
    ],
    categories: [4],
  ),
  Folder(
    'work',
    'Work',
    Icons.work_outline_rounded,
    [
      'slack',
      'gmail',
      'android.gm',
      'outlook',
      'teams',
      'zoom',
      'meet',
      'calendar',
      'apps.docs',
      'drive',
      'docs',
      'sheets',
      'slides',
      'notion',
      'figma',
      'jira',
      'atlassian',
      'asana',
      'linear',
      'keep',
      'todo',
      'tasks',
      'office',
      'zoho',
      'claude',
      'anthropic',
      'chatgpt',
      'openai',
      'gemini',
      'bard',
      'dropbox',
      'trello',
      'miro',
      'webex',
      'clickup',
      'monday',
      'confluence',
      'github',
      'workspace',
      'mail',
    ],
    categories: [7],
  ),
  Folder('money', 'Money', Icons.account_balance_wallet_outlined, [
    'pay',
    'upi',
    'bank',
    'paytm',
    'phonepe',
    'gpay',
    'nbu.paisa',
    'wallet',
    'cred',
    'zerodha',
    'kite',
    'groww',
    'upstox',
    'lemonn',
    'coinswitch',
    'finance',
    'invest',
    'sbi',
    'hdfc',
    'icici',
    'axis',
    'kotak',
    'yesbank',
    'splitwise',
    'money',
    'mutual',
    'angel',
    'dhan',
    'indmoney',
    'jupiter',
    'fi.money',
    'slice',
    'card',
  ]),
  Folder(
    'media',
    'Watch & Listen',
    Icons.play_circle_outline_rounded,
    [
      'music',
      'spotify',
      'youtube',
      'netflix',
      'primevideo',
      'avod',
      'hotstar',
      'jiocinema',
      'sonyliv',
      'zee5',
      'photos',
      'gallery',
      'camera',
      'podcast',
      'audible',
      'saavn',
      'gaana',
      'wynk',
      'video',
      'player',
      'snapseed',
      'lightroom',
      'vsco',
      'capcut',
      'shazam',
      'pocketfm',
      'kukufm',
    ],
    categories: [1, 2, 3],
  ),
  Folder('shopping', 'Shop & Food', Icons.shopping_bag_outlined, [
    'amazon.mshop',
    'flipkart',
    'myntra',
    'swiggy',
    'zomato',
    'blinkit',
    'grofers',
    'zepto',
    'bigbasket',
    'instamart',
    'meesho',
    'ajio',
    'nykaa',
    'dunzo',
    'tatacliq',
    'decathlon',
    'ikea',
    'urbancompany',
    'dmart',
    'jiomart',
    'licious',
    'eatsure',
    'magicpin',
    'shop',
  ]),
  Folder(
    'travel',
    'Travel',
    Icons.explore_outlined,
    [
      'maps',
      'uber',
      'olacabs',
      'rapido',
      'irctc',
      'makemytrip',
      'goibibo',
      'airbnb',
      'booking',
      'indigo',
      'cleartrip',
      'redbus',
      'metro',
      'waze',
      'ixigo',
      'yatra',
      'agoda',
      'trivago',
      'skyscanner',
      'blusmart',
      'namma',
      'airindia',
      'vistara',
      'akasa',
    ],
    categories: [6],
  ),
  Folder(
    'reading',
    'News & Reading',
    Icons.menu_book_outlined,
    ['news', 'inshorts', 'kindle', 'medium', 'times', 'pocket', 'quora', 'hindu', 'economictimes', 'moneycontrol', 'flipboard', 'books', 'wattpad', 'substack'],
    categories: [5],
  ),
  Folder(
    'games',
    'Games',
    Icons.sports_esports_outlined,
    ['game', 'games', 'chess', 'ludo', 'puzzle', 'supercell', 'king.', 'rummy', 'dream11'],
    categories: [0],
  ),
  Folder(
    'tools',
    'Tools',
    Icons.tune_rounded,
    [
      'settings',
      'deskclock',
      'clock',
      'calculator',
      'files',
      'documentsui',
      'chrome',
      'browser',
      'firefox',
      'vending',
      'weather',
      'recorder',
      'authenticator',
      'vpn',
      'security',
      'googlequicksearchbox',
      'assistant',
      'lens',
      'translate',
      'wellbeing',
      'fitbit',
      'health',
      'fit',
      'print',
      'scanner',
      'tips',
      'pixel',
      'samsung',
      'android',
      'google',
    ],
    categories: [8],
  ),
];

const other = Folder('other', 'Everything else', Icons.apps_rounded, []);

Folder folderById(String id) => folders.where((f) => f.id == id).firstOrNull ?? other;

/// Picks a folder: the user's own choice, then keywords, then Android's category,
/// then "Tools" for built-in apps, else "Everything else".
Folder folderFor(AppEntry app, Map<String, String> overrides) {
  final picked = overrides[app.package];
  if (picked != null) return folderById(picked);

  final hay = '${app.package} ${app.label}'.toLowerCase();
  // Specific folders first; "tools" has broad words like "google", so it goes last.
  for (final f in folders.where((f) => f.id != 'tools')) {
    if (f.keywords.any(hay.contains)) return f;
  }
  for (final f in folders) {
    if (f.categories.contains(app.category)) return f;
  }
  final tools = folderById('tools');
  if (app.system || tools.keywords.any(hay.contains)) return tools;
  return other;
}

/// Groups apps by folder, keeping folder order and dropping empty folders.
List<(Folder, List<AppEntry>)> groupApps(List<AppEntry> apps, Map<String, String> overrides) {
  final map = <String, List<AppEntry>>{};
  for (final a in apps) {
    map.putIfAbsent(folderFor(a, overrides).id, () => []).add(a);
  }
  return [
    for (final f in [...folders, other])
      if (map[f.id]?.isNotEmpty ?? false) (f, map[f.id]!),
  ];
}
