# One Launcher → Google Play: checklist

Everything here is in `~/Desktop/OneLauncher-PlayStore/` (rebuild it any time with
`tool/build_play.sh`).

| File | Where it goes in Play Console |
|---|---|
| `OneLauncher-<version>.aab` | Test and release → a track → Create release → upload |
| `icon-512.png` | Grow → Store listing → App icon |
| `feature-graphic.png` | Store listing → Feature graphic |
| `screenshots/*.png` (6) | Store listing → Phone screenshots |
| `listing.md` | Store listing → name, short and full description |
| `privacy-policy.html` | Host it publicly, paste the link in App content → Privacy policy |
| `data-safety.md` | App content → Data safety, Ads, Content rating, Target audience |
| `permissions.md` | Answers if review asks about permissions |

## Steps
1. **Account** — play.google.com/console, $25 once, identity check (a few days).
   New personal accounts: a closed test with **12+ testers for 14 days** before production.
2. **Create app** — name "One Launcher", App, Free, accept declarations.
3. **App signing (do this before the first upload)** — App integrity → App signing →
   "Use a different key" → "Export and upload a key from Java keystore". Download pepk.jar and the
   encryption key, then run `tool/play_export_key.sh <pepk.jar> <encryption_public_key.pem>` and
   upload `encrypted-key.zip`. This keeps Play's app on the same key as your shared APKs, so
   existing users can update from Play without uninstalling.
4. **Store listing** — paste `listing.md`, upload the icon, feature graphic and screenshots.
   Category: Personalization.
5. **App content** — privacy policy link, then the forms in `data-safety.md`.
6. **Internal testing** — upload the .aab, add yourself, install from the Play link to check.
7. **Closed testing** — add 12+ testers (their Gmail addresses or a Google Group), share the opt-in
   link, keep it running 14 days.
8. **Production** — apply for production access, then create a production release with the same
   .aab (or a newer one). Review usually takes a few days.

Each new upload needs a higher version number (tool/build_play.sh uses pubspec.yaml's).
