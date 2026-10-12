import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'tv/tv_apps.dart';
import 'tv/tv_home.dart';
import 'ui/ds.dart';
import 'ui/theme.dart';

/// One Launcher TV (build with `--flavor tv -t lib/main_tv.dart`).
/// Same design language as the phone app, laid out for a TV and a remote.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  TvApps.instance.init();
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
    theme.addListener(_repaint);
  }

  @override
  void dispose() {
    theme.removeListener(_repaint);
    super.dispose();
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
        fontFamily: DS.font,
        scaffoldBackgroundColor: DS.canvas,
        colorScheme: ColorScheme.dark(primary: DS.onCanvas, surface: DS.canvas),
        // Focus is shown by our own ring/scale; no Material highlight boxes.
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      // Remotes send "select"; treat it like Enter everywhere (text fields, buttons).
      shortcuts: {...WidgetsApp.defaultShortcuts, const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent()},
      home: TvHome(prefs: prefs, theme: theme),
    );
  }
}
