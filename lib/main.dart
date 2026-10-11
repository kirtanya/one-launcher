import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'home.dart';
import 'prefs.dart';
import 'ui/ds.dart';
import 'ui/theme.dart';

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
  final theme = OneTheme(prefs);
  await theme.refreshSystem(); // phone's Material You colours, before the first frame
  runApp(OneLauncher(prefs: prefs, theme: theme));
}

class OneLauncher extends StatefulWidget {
  const OneLauncher({super.key, required this.prefs, this.theme});
  final Prefs prefs;
  final OneTheme? theme;

  @override
  State<OneLauncher> createState() => _OneLauncherState();
}

class _OneLauncherState extends State<OneLauncher> {
  late final OneTheme theme = widget.theme ?? OneTheme(widget.prefs);

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

  /// New colours: rebuild every widget, including const ones Flutter would normally skip
  /// (the same thing hot reload does), so nothing keeps an old colour.
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
    final prefs = widget.prefs;
    return MaterialApp(
      title: 'One Launcher',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: DS.font,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.dark(primary: DS.ink, surface: DS.card),
        textSelectionTheme: TextSelectionThemeData(cursorColor: DS.ink, selectionHandleColor: DS.ink, selectionColor: DS.hero),
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
      home: HomeScreen(prefs: prefs, theme: theme),
    );
  }
}
