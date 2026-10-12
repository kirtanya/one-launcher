import 'package:flutter/material.dart';

/// Phone settings pages search can open: name, extra words people type, icon, Android action.
class SystemSetting {
  const SystemSetting(this.title, this.keywords, this.icon, this.action);
  final String title, keywords, action;
  final IconData icon;
}

const systemSettings = <SystemSetting>[
  SystemSetting('Wi-Fi', 'wifi wireless internet network', Icons.wifi_rounded, 'android.settings.WIFI_SETTINGS'),
  SystemSetting('Bluetooth', 'bluetooth pair headphones earbuds', Icons.bluetooth_rounded, 'android.settings.BLUETOOTH_SETTINGS'),
  SystemSetting('Mobile network', 'sim mobile data cellular 5g 4g roaming', Icons.signal_cellular_alt_rounded, 'android.settings.NETWORK_OPERATOR_SETTINGS'),
  SystemSetting('Data usage', 'data usage limit', Icons.data_usage_rounded, 'android.settings.DATA_USAGE_SETTINGS'),
  SystemSetting('Hotspot & internet', 'hotspot tethering airplane flight mode internet', Icons.wifi_tethering_rounded, 'android.settings.WIRELESS_SETTINGS'),
  SystemSetting('Display', 'display brightness screen timeout font size', Icons.brightness_6_rounded, 'android.settings.DISPLAY_SETTINGS'),
  SystemSetting('Dark theme', 'dark mode night theme', Icons.dark_mode_rounded, 'android.settings.DARK_THEME_SETTINGS'),
  SystemSetting('Night Light', 'night light blue light eye comfort', Icons.nightlight_rounded, 'android.settings.NIGHT_DISPLAY_SETTINGS'),
  SystemSetting('Sound & vibration', 'sound volume ringtone vibration silent', Icons.volume_up_rounded, 'android.settings.SOUND_SETTINGS'),
  SystemSetting('Do Not Disturb', 'do not disturb dnd silence focus', Icons.do_not_disturb_on_rounded, 'android.settings.ZEN_MODE_SETTINGS'),
  SystemSetting('Notifications', 'notifications alerts', Icons.notifications_rounded, 'android.settings.NOTIFICATION_SETTINGS'),
  SystemSetting('Battery', 'battery saver power charging', Icons.battery_full_rounded, 'android.intent.action.POWER_USAGE_SUMMARY'),
  SystemSetting('Storage', 'storage space memory free up', Icons.sd_storage_rounded, 'android.settings.INTERNAL_STORAGE_SETTINGS'),
  SystemSetting('Apps', 'apps applications manage uninstall', Icons.apps_rounded, 'android.settings.MANAGE_APPLICATIONS_SETTINGS'),
  SystemSetting('Default apps', 'default apps browser home launcher', Icons.app_settings_alt_rounded, 'android.settings.MANAGE_DEFAULT_APPS_SETTINGS'),
  SystemSetting('Location', 'location gps', Icons.location_on_rounded, 'android.settings.LOCATION_SOURCE_SETTINGS'),
  SystemSetting('Security', 'security lock screen password pin fingerprint face unlock', Icons.lock_rounded, 'android.settings.SECURITY_SETTINGS'),
  SystemSetting('Privacy', 'privacy permissions', Icons.privacy_tip_rounded, 'android.settings.PRIVACY_SETTINGS'),
  SystemSetting('Accessibility', 'accessibility talkback magnify', Icons.accessibility_new_rounded, 'android.settings.ACCESSIBILITY_SETTINGS'),
  SystemSetting('Wallpaper', 'wallpaper background style', Icons.wallpaper_rounded, 'android.intent.action.SET_WALLPAPER'),
  SystemSetting('Date & time', 'date time clock timezone', Icons.schedule_rounded, 'android.settings.DATE_SETTINGS'),
  SystemSetting('Languages & input', 'language keyboard input', Icons.translate_rounded, 'android.settings.LOCALE_SETTINGS'),
  SystemSetting('Keyboard', 'keyboard gboard typing', Icons.keyboard_rounded, 'android.settings.INPUT_METHOD_SETTINGS'),
  SystemSetting('VPN', 'vpn', Icons.vpn_key_rounded, 'android.settings.VPN_SETTINGS'),
  SystemSetting('Cast', 'cast screen mirror tv', Icons.cast_rounded, 'android.settings.CAST_SETTINGS'),
  SystemSetting('NFC', 'nfc tap to pay contactless', Icons.nfc_rounded, 'android.settings.NFC_SETTINGS'),
  SystemSetting('Accounts', 'accounts google sync', Icons.account_circle_rounded, 'android.settings.SYNC_SETTINGS'),
  SystemSetting('Users', 'users guest profile', Icons.group_rounded, 'android.settings.USER_SETTINGS'),
  SystemSetting('Developer options', 'developer usb debugging', Icons.developer_mode_rounded, 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS'),
  SystemSetting('About phone', 'about phone android version build model', Icons.info_rounded, 'android.settings.DEVICE_INFO_SETTINGS'),
  SystemSetting('System update', 'update software system', Icons.system_update_rounded, 'android.settings.SYSTEM_UPDATE_SETTINGS'),
  SystemSetting('Settings', 'settings', Icons.settings_rounded, 'android.settings.SETTINGS'),
];
