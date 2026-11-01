import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_launcher/main.dart';
import 'package:one_launcher/prefs.dart';
import 'package:one_launcher/search_history.dart';
import 'package:one_launcher/ui/components.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone search → the filter pills that replace the recent pills once something is typed.
void main() {
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.88;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('one_launcher/apps'), (call) async {
      if (call.method == 'getApps') {
        return [
          for (final n in ['Spotify', 'Slack', 'Maps']) {'package': 'com.${n.toLowerCase()}', 'label': n, 'system': false, 'category': -1, 'installed': 0},
        ];
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'searchHistory': ['weather today', 'maps'],
    });
    final prefs = await Prefs.load();
    await tester.pumpWidget(OneLauncher(prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

  Finder section(String k) => find.byWidgetPredicate((w) => w is KeyedSubtree && w.key == ValueKey(k)); // the Cascade around it shares the key
  final apps = section('apps');
  final web = find.byWidgetPredicate((w) => w is OneCard && w.key == const ValueKey('web'));
  Finder pill(SearchFilter f) => find.byKey(ValueKey('filter:${f.name}'));

  testWidgets('filter pills: hidden when empty (recent pills stay), shown on typing, Apps by default, Web narrows, resets', (tester) async {
    await launch(tester);
    expect(find.byType(RecentSearchPills), findsOneWidget);
    expect(find.byType(SearchFilterPills), findsNothing);

    await tester.enterText(find.byType(TextField), 's');
    await tester.pumpAndSettle();
    expect(find.byType(SearchFilterPills), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Movies & shows'), findsOneWidget);
    expect(apps, findsOneWidget, reason: 'Apps is the default');
    expect(web, findsNothing);

    await tester.drag(find.byType(SearchFilterPills), const Offset(-200, 0)); // the test font is wide: the row scrolls sideways here
    await tester.pumpAndSettle();
    await tester.tap(pill(SearchFilter.web));
    await tester.pumpAndSettle();
    expect(web, findsOneWidget);
    expect(apps, findsNothing);

    await tester.drag(find.byType(SearchFilterPills), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(pill(SearchFilter.all));
    await tester.pumpAndSettle();
    expect(apps, findsOneWidget);
    expect(web, findsOneWidget);

    // A new search starts on Apps again.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(SearchFilterPills), findsNothing);
    await tester.enterText(find.byType(TextField), 's');
    await tester.pumpAndSettle();
    expect(apps, findsOneWidget);
    expect(web, findsNothing);
  });

  testWidgets('filter pills: Movies & shows hides the apps and the web', (tester) async {
    await launch(tester);
    await tester.enterText(find.byType(TextField), 's');
    await tester.pumpAndSettle();
    await tester.tap(pill(SearchFilter.movies));
    await tester.pumpAndSettle();
    expect(apps, findsNothing);
    expect(web, findsNothing);
  });
}
