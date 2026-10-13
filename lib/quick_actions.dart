import 'package:flutter/material.dart';

/// Built-in quick actions (ids start with "b:"). App shortcuts use `s:<package>|<id>|<profile>`.
const builtInActions = <String, (String, IconData)>{
  'b:timer': ('Set timer', Icons.timer_outlined),
  'b:torch': ('Flashlight', Icons.flashlight_on_outlined),
  'b:camera': ('Camera', Icons.photo_camera_outlined),
  'b:calculator': ('Calculator', Icons.calculate_outlined),
  'b:alarm': ('Alarms', Icons.alarm_rounded),
  'b:internet': ('Internet', Icons.wifi_rounded),
  'b:bluetooth': ('Bluetooth', Icons.bluetooth_rounded),
  'b:note': ('New note', Icons.edit_note_rounded),
  'b:remote': ('TV remote', Icons.settings_remote_rounded), // opens One Launcher's own remote
};

/// An app shortcut offered by an installed app.
class AppShortcut {
  const AppShortcut(this.map);
  final Map map;
  String get id => map['id'] as String;
  String get label => map['label'] as String;
  String get app => map['app'] as String;
  String get package => map['package'] as String;
  bool get work => map['work'] == true;
}
