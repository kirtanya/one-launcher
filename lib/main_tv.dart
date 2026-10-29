import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'one_stream.dart';
import 'prefs.dart';
import 'ratings.dart';
import 'tv/tv_apps.dart';
import 'tv/tv_home.dart';
import 'tv/tv_metro.dart';
import 'tv/tv_real.dart';
import 'ui/ds.dart';
import 'ui/glass.dart';
import 'ui/theme.dart';

/// One Launcher TV (build with `--flavor tv -t lib/main_tv.dart`).
/// Same design language as the phone app, laid out for a TV and a remote.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  TvApps.instance.init();
  OneStream.channel = const MethodChannel('one_launcher/tv');
  OneStream.instance.init(); // the user's streaming app, when installed
  TitleExtras.useTv(); // scores & reviews through Android's network stack, kept in the files folder
  final prefs = await Prefs.load();
  final theme = OneTheme(prefs); // same colour engine as the phone (Customise → Colours)
  await theme.refreshSystem();
  runApp(OneLauncherTv(prefs: prefs, theme: theme));
}

class OneLauncherTv extends StatefulWidget {
  const OneLauncherTv({super.key, required this.prefs, this.theme});
  final Prefs prefs;
  final OneTheme? theme;

  @override
  State<OneLauncherTv> createState() => _OneLauncherTvState();
}

class _OneLauncherTvState extends State<OneLauncherTv> {
  late final OneTheme theme = widget.theme ?? OneTheme(widget.prefs);
  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    TvMetro.prefs = prefs;
    TvMetro.apply(theme, prefs); // Tiles: the TV's own Metro accent (keeps every colour choice apart)
    theme.addListener(_onTheme);
    _syncGlass(repaint: false); // no rebuild needed before the first frame
    prefs.addListener(_syncGlass);
    HardwareKeyboard.instance.addHandler(_backSound);
  }

  /// Real: Back on the remote sounds like a heavier key (the set clunks back a level).
  bool _backSound(KeyEvent e) {
    if (DS.third && e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
      TvApps.instance.sound('thunk');
    }
    return false; // never swallows the key
  }

  @override
  void dispose() {
    theme.removeListener(_onTheme);
    prefs.removeListener(_syncGlass);
    HardwareKeyboard.instance.removeHandler(_backSound);
    super.dispose();
  }

  /// Tiles' glass look (frost / tint / edge / sheen) lives in statics the tile surfaces read —
  /// kept in step with prefs, like the phone app does.
  void _syncGlass({bool repaint = true}) {
    final p = prefs;
    final g = (p.glassBlur, p.glassTint, p.glassEdge, p.glassSheen, p.tileStyle == 'glass');
    if (g == (Glass.blur, Glass.tint, Glass.edge, Glass.sheen, Glass.tiles)) return;
    Glass.blur = g.$1;
    Glass.tint = g.$2;
    Glass.edge = g.$3;
    Glass.sheen = g.$4;
    Glass.tiles = g.$5;
    if (repaint) _repaint();
  }

  /// Colours / home view changed: Tiles takes the TV's Metro accent, then everything repaints.
  void _onTheme() {
    TvMetro.apply(theme, prefs);
    _repaint();
  }

  /// New colours: rebuild everything (const widgets included), like the phone app.
  void _repaint() {
    setState(() {});
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One Launcher TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: DS.face, // Real: its own face
        scaffoldBackgroundColor: DS.canvas,
        colorScheme: ColorScheme.dark(primary: DS.onCanvas, surface: DS.canvas),
        // Focus is shown by our own ring/scale; no Material highlight boxes.
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      // Remotes send "select"; treat it like Enter everywhere (text fields, buttons).
      shortcuts: {...WidgetsApp.defaultShortcuts, const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent()},
      // Real: everything is seen through the old set's curved glass.
      builder: (context, child) => DS.third ? Stack(fit: StackFit.expand, children: [child!, const CrtGlass()]) : child!,
      home: TvHome(prefs: prefs, theme: theme),
    );
  }
}
