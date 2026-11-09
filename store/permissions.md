# Permissions — what to tell Google

Play may ask why the app uses these. All are used only on the phone.

| Permission / access | Why One Launcher needs it | When it's asked for |
|---|---|---|
| Home app (HOME intent) | It is a home screen (launcher) — its core purpose. | Users choose it in Settings → Default home app |
| Usage access (PACKAGE_USAGE_STATS) | Shows today's screen time and top apps on the optional Screen time page. | Only when the user adds/opens the Screen time page; the system settings screen explains it |
| Calendar (READ_CALENDAR) | Shows the next event on the optional Up next page. | Only when the user adds the Up next page |
| Notification access (notification listener) | Needed by Android to read which music/video is playing and show play/pause/skip controls on the optional Now playing page; in the Tiles view it also counts each app's notifications for the optional badges / live tiles. Notification content is not read or stored. | Only when the user adds the Now playing page or turns on tile badges / live tiles |
| Request uninstall (REQUEST_DELETE_PACKAGES) | Lets users uninstall an app from its long-press menu (Android still asks to confirm). | When the user taps Uninstall |
| Set alarm (SET_ALARM) | The Set timer / Alarms quick actions open the phone's Clock app to set them. | No prompt (normal permission) |
| Expand status bar (EXPAND_STATUS_BAR) | Swipe down on the home screen opens notifications, like other launchers. | No prompt (normal permission) |
| Internet (INTERNET) | TV remote: connects to the user's own Google TV / Android TV on the local Wi-Fi. Now playing: downloads the cover picture from the address the music app itself gives (no user data sent). No servers of ours. | No prompt (normal permission); the user pairs a TV with the code it shows |
| App widgets (bind widgets) | Lets users place other apps' widgets on the top area. | Android asks the user when adding a widget |

**Sensitive-permission declarations:** none needed for the Play build (`tool/build_play.sh`):
no accessibility service, and no foreground service — Mindful open works only
inside the launcher there, without the background guard (store/PLAY_REVIEW.md). Nothing else is restricted (no SMS, call log, all-files, background
location, QUERY_ALL_PACKAGES). If a reviewer asks about notification access, use the text above:
media controls and notification counts, on-device only.
