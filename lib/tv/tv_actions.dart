import 'package:flutter/material.dart';

/// TV quick actions (the chips above the rows). Built-ins open the TV's own screens
/// (TvActivity.openAction); apps can be pinned too as `a:<package>`.
const tvActions = <String, (String, IconData)>{
  't:inputs': ('Inputs', Icons.input_rounded),
  't:assistant': ('Voice search', Icons.mic_none_rounded),
  't:wifi': ('Network', Icons.wifi_rounded),
  't:bluetooth': ('Remotes & Bluetooth', Icons.bluetooth_rounded),
  't:sound': ('Picture & sound', Icons.tune_rounded),
  't:energy': ('Energy & sleep', Icons.bedtime_outlined),
  't:captions': ('Captions', Icons.closed_caption_outlined),
  't:language': ('Language', Icons.translate_rounded),
  't:storage': ('Storage', Icons.storage_rounded),
  't:datetime': ('Date & time', Icons.schedule_rounded),
  't:accessibility': ('Accessibility', Icons.accessibility_new_rounded),
  't:playstore': ('Get apps', Icons.shop_outlined),
  't:settings': ('Settings', Icons.settings_outlined),
  // Stops One Stream's idle engine, frees our memory, clears every app's cache (TvActivity.boost).
  't:boost': ('Speed up', Icons.rocket_launch_outlined),
};
