# MainActivity attaches the phone flavour's smart home bridge by reflection.
-keep class com.kirtanya.one_launcher.SmartHomeBridge { public static void attach(io.flutter.embedding.engine.FlutterEngine, android.content.Context); }
-dontwarn com.kirtanya.one_launcher.SmartHomeBridge
