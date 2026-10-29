import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'one_stream.dart';
import 'home.dart';
import 'third/tactile/parts.dart';
import 'third/tactile/tactile.dart';
import 'third/third_home.dart';
import 'tiles/tiles_home.dart';
import 'tv_cast.dart';
import 'prefs.dart';
import 'ui/ds.dart';
import 'ui/perf.dart';
import 'ui/glass.dart';
import 'ui/theme.dart';
import 'widgets.dart';

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
  OneStream.instance.init(); // the user's streaming app, when installed
  final prefs = await Prefs.load();
  await Perf.init(prefs); // lighter effects on budget phones
  final theme = OneTheme(prefs);
  await theme.refreshSystem(); // phone's Material You colours, before the first frame
  if (const bool.fromEnvironment('PERF_LOG')) _logFrameTimes();
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
    TvCast.prefs = widget.prefs; // the title sheet's "On <TV>" (the paired remote)
    theme.addListener(_repaint);
    Perf.lite.addListener(_repaint);
    AppIcon.themed = !widget.prefs.themedIcons; // differs → the first sync applies everything
    _themedIcons();
    widget.prefs.addListener(_themedIcons);
  }

  void _themedIcons() {
    final p = widget.prefs;
    // Tactile has no glass: its surfaces are moulded plastic.
    final glass = (p.classicStyle == 'glass' && p.homeView != 'third', p.glassBlur, p.glassTint, p.glassEdge, p.glassSheen, p.tileStyle == 'glass');
    if (AppIcon.themed == p.themedIcons && glass == (Glass.classic, Glass.blur, Glass.tint, Glass.edge, Glass.sheen, Glass.tiles)) return;
    AppIcon.themed = p.themedIcons;
    Glass.classic = glass.$1;
    Glass.blur = glass.$2;
    Glass.tint = glass.$3;
    Glass.edge = glass.$4;
    Glass.sheen = glass.$5;
    Glass.tiles = glass.$6;
    _repaint(); // every icon and surface, including const ones
  }

  @override
  void dispose() {
    theme.removeListener(_repaint);
    Perf.lite.removeListener(_repaint);
    widget.prefs.removeListener(_themedIcons);
    super.dispose();
  }

  /// New colours (or lighter effects switched): rebuild every widget, including const ones Flutter would normally skip
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
        fontFamily: DS.face,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.dark(primary: DS.ink, surface: DS.card),
        sliderTheme: DS.third ? tactileSliderTheme() : null, // Tactile: every slider is a fader
        // Tactile's own versions of the stock widgets, so every screen gets them without being
        // edited: fields are wells, buttons keys, menus plates, tooltips a display.
        inputDecorationTheme: DS.third
            ? InputDecorationTheme(
                filled: true,
                fillColor: Tactile.well,
                hintStyle: TextStyle(color: Tactile.inkMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Tactile.rim, width: .6)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Tactile.rim, width: .6)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Tactile.light, width: 1)),
              )
            : null,
        filledButtonTheme: DS.third
            ? FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: Tactile.capTop,
                  foregroundColor: Tactile.ink,
                  elevation: 3,
                  shadowColor: Tactile.shade,
                  side: BorderSide(color: Tactile.rim, width: .6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: TextStyle(fontFamily: DS.face, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                  splashFactory: NoSplash.splashFactory,
                ),
              )
            : null,
        popupMenuTheme: DS.third
            ? PopupMenuThemeData(
                color: Tactile.plate,
                elevation: 10,
                shadowColor: Tactile.shade,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Tactile.rim, width: .6)),
                textStyle: TextStyle(fontFamily: DS.face, color: Tactile.ink, fontSize: 15),
              )
            : null,
        switchTheme: DS.third
            ? SwitchThemeData(
                thumbColor: WidgetStatePropertyAll(Tactile.capTop),
                trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Color.lerp(Tactile.well, Tactile.light, .3) : Tactile.well),
                trackOutlineColor: WidgetStatePropertyAll(Tactile.rim),
              )
            : null,
        tooltipTheme: DS.third
            ? TooltipThemeData(
                decoration: BoxDecoration(color: TLcd.glass, borderRadius: BorderRadius.circular(8), border: Border.all(color: Tactile.rim)),
                textStyle: TextStyle(fontFamily: Tactile.monoFont, color: TLcd.text, fontSize: 12, letterSpacing: 1),
              )
            : null,
        progressIndicatorTheme: DS.third ? ProgressIndicatorThemeData(color: Tactile.light, linearTrackColor: Tactile.well, circularTrackColor: Tactile.well) : null,
        dividerTheme: DS.third ? DividerThemeData(color: Tactile.rim, thickness: 1) : null,
        listTileTheme: DS.third ? ListTileThemeData(iconColor: Tactile.ink, textColor: Tactile.ink) : null,
        iconTheme: DS.third ? IconThemeData(color: Tactile.ink) : null,
        bottomSheetTheme: DS.third ? BottomSheetThemeData(backgroundColor: Tactile.plate, modalBackgroundColor: Tactile.plate) : null,
        textSelectionTheme: TextSelectionThemeData(cursorColor: DS.ink, selectionHandleColor: DS.ink, selectionColor: DS.hero),
        // Dialogs, snackbars and text buttons speak the active design language too
        // (docs/DESIGN_LANGUAGES.md): Classic cards / Metro flat panels with the accent.
        // Tactile: dialogs are plates; snackbars a backlit display strip; buttons printed legends.
        dialogTheme: DialogThemeData(
          backgroundColor: DS.card,
          elevation: DS.third ? 12 : null,
          shadowColor: DS.third ? Tactile.shade : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rCard),
            side: DS.third ? BorderSide(color: Tactile.rim, width: .6) : BorderSide.none,
          ),
          titleTextStyle: DS.title.copyWith(fontSize: DS.metro ? 28 : 20),
          contentTextStyle: DS.rowSub,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: DS.third ? TLcd.glass : (DS.metro ? DS.hero : DS.ink),
          actionTextColor: DS.third ? TLcd.text : null,
          contentTextStyle: DS.third
              ? TextStyle(fontFamily: Tactile.monoFont, color: TLcd.text, fontSize: 14, letterSpacing: 1.2)
              : TextStyle(fontFamily: DS.font, color: DS.metro ? Colors.white : DS.card, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMedia)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: DS.metro ? DS.hero : DS.ink,
            textStyle: DS.third ? TextStyle(fontFamily: Tactile.legendFont, fontWeight: FontWeight.w700, letterSpacing: 1.3) : null,
            splashFactory: DS.third ? NoSplash.splashFactory : null, // Tactile: things press, they don't ripple
          ),
        ),
        // Sparkle ripples run a shader; budget GPUs get the plain ripple.
        // Tactile: nothing ripples — a press darkens the part, like a key going down.
        splashFactory: DS.third ? NoSplash.splashFactory : (Perf.lite.value ? InkRipple.splashFactory : InkSparkle.splashFactory),
        highlightColor: DS.third ? Tactile.shadeSoft : null, // Tactile: a press darkens, like a key going down
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
      // The home view the user picked (Settings → Look → Home view).
      home: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => switch (prefs.homeView) {
          'tiles' => TilesHome(key: const ValueKey('tiles'), prefs: prefs, theme: theme),
          'third' => ThirdHome(key: const ValueKey('third'), prefs: prefs, theme: theme),
          _ => HomeScreen(key: const ValueKey('classic'), prefs: prefs, theme: theme),
        },
      ),
    );
  }
}

/// Measuring builds only (`--dart-define=PERF_LOG=true`): every ~2 s, log how many frames ran
/// and how slow the slowest were (build = Dart/UI thread, raster = GPU thread), to logcat.
void _logFrameTimes() {
  final build = <int>[], raster = <int>[];
  var last = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
    if (DateTime.now().difference(last).inMilliseconds < 2000 || build.isEmpty) return;
    last = DateTime.now();
    String stats(List<int> v) {
      final s = [...v]..sort();
      final p90 = s[(s.length * .9).floor().clamp(0, s.length - 1)] / 1000, p99 = s[(s.length * .99).floor().clamp(0, s.length - 1)] / 1000;
      return 'p90=${p90.toStringAsFixed(1)}ms p99=${p99.toStringAsFixed(1)}ms max=${(s.last / 1000).toStringAsFixed(1)}ms >16ms=${s.where((x) => x > 16600).length}';
    }

    debugPrint('PERF frames=${build.length} build[${stats(build)}] raster[${stats(raster)}]');
    build.clear();
    raster.clear();
  });
}
