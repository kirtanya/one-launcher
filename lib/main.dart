import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'home.dart';
import 'prefs.dart';
import 'ui/ds.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  Apps.instance.init();
  final prefs = await Prefs.load();
  runApp(OneLauncher(prefs: prefs));
}

class OneLauncher extends StatelessWidget {
  const OneLauncher({super.key, required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One Launcher',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: DS.font,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(primary: DS.ink, surface: DS.card),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: DS.ink, selectionHandleColor: DS.ink, selectionColor: DS.hero),
        splashFactory: InkSparkle.splashFactory,
      ),
      // On the web preview there is no wallpaper, so paint a sample one.
      builder: (context, child) => Apps.isDemo
          ? DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A4A6B), Color(0xFF1E2433), Color(0xFF6B4A3A)],
                ),
              ),
              child: child,
            )
          : child!,
      home: HomeScreen(prefs: prefs),
    );
  }
}
