import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'tv/tv_apps.dart';
import 'tv/tv_home.dart';
import 'ui/ds.dart';

/// One Launcher TV (build with `--flavor tv -t lib/main_tv.dart`).
/// Same design language as the phone app, laid out for a TV and a remote.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  TvApps.instance.init();
  final prefs = await Prefs.load();
  runApp(OneLauncherTv(prefs: prefs));
}

class OneLauncherTv extends StatelessWidget {
  const OneLauncherTv({super.key, required this.prefs});
  final Prefs prefs;

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
      home: TvHome(prefs: prefs),
    );
  }
}
