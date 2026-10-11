import 'package:flutter/material.dart';

/// Pages the user can show in the swipeable top half.
class TopWidget {
  const TopWidget(this.id, this.name, this.description, this.icon);
  final String id, name, description;
  final IconData icon;
}

/// Name/description for any page id, including added app widgets (`widget:<id>`).
TopWidget topWidgetFor(String id, Map<String, String> widgetLabels) =>
    topWidgets[id] ?? TopWidget(id, widgetLabels[id] ?? 'App widget', 'App widget', Icons.widgets_outlined);

const topWidgets = <String, TopWidget>{
  'clock': TopWidget('clock', 'Clock', 'Big time. Tap to open Clock', Icons.schedule_rounded),
  'screen_time': TopWidget('screen_time', 'Screen time', 'Today’s total and your top apps', Icons.hourglass_bottom_rounded),
  'battery': TopWidget('battery', 'Battery', 'Charge level and time to full', Icons.battery_charging_full_rounded),
  'up_next': TopWidget('up_next', 'Up next', 'Your next calendar event', Icons.event_rounded),
};
