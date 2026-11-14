# Duet 💞 (Flutter app)

Watch movies, listen to songs and watch YouTube **together, in sync**, with chat.
If one of you pauses, seeks or changes speed, it happens on both phones.

Backend: `D:\Backend Projects\Duet-Backend-Nodejs`.

## Features

* **Email accounts and pairing.** Invite your partner by email. They accept and you're a couple.
* **Movie night.** Pick a movie that's already on your phone. Your partner's app finds the
  same file on their phone automatically (by length, size and fingerprint), or they pick it
  and Duet checks it's the identical file. Nothing is uploaded or streamed.
* **Music together.** The same flow for songs, with a spinning record.
* **YouTube together.** Paste a link (it's even auto-detected from the clipboard).
* **Perfect sync.** Play starts on the same server tick on both phones. Small drift is fixed
  by nudging speed 5%; big drift by seeking. Pause, seek and speed apply to both.
* **Movie only on one phone?** Your partner taps "Stream from [name]'s copy". You approve,
  your phone uploads it temporarily to a private S3 bucket, and they stream it in sync. It's
  deleted automatically when you end, finish, or leave.
* **Live chat** while watching (below the video, or as a side panel in landscape), with a
  typing indicator. Messages sent during playback get a 🎬 timestamp chip. **Tap it and you
  both jump back to that scene.**
* **Reply like WhatsApp**: swipe a message right (or long-press → Reply) to quote it. Tap a
  quote to jump to the original.
* **Partner presence**: "online" or "last seen 5 min ago" on home, chat and the player, plus a
  notice when they go offline or come back.
* **"Partner left" popup**: if they leave or lose connection mid-movie, it pauses and asks
  **Leave** (back home) or **Continue** (keep watching alone). If they come back, you're back
  in sync automatically.
* **Floating reactions** ❤️😂😮😢🔥👏🥰 that fly up on both screens.
* **Love taps.** Hug 🤗, kiss 💋, miss you 🥺, come watch 🍿. Your partner's phone buzzes
  with a heart burst.
* **Auto-pause and resume.** If your partner loses connection, buffers or steps out, it pauses
  for you and resumes by itself when they're back ("Back together — resuming 💞").
* **Local history and resume.** Each phone remembers where you stopped, so next time you get
  "Resume from 1:02:13". "Continue watching" row, history screen, and *time spent together*
  stats. Stored only on the phone.
* **Your own subtitles** (.srt/.ass/.vtt) per phone, speed control, double-tap ±10 s,
  fullscreen on rotate. Leaving the app pauses for both.
* **Plays almost anything**: mkv, mp4, avi, webm, flac, mp3… (libmpv via media_kit).

## Config (`.env`)

Copy `.env.example` to `.env` and set the backend address:

```
API_BASE_URL=http://192.168.1.37:4747
```

⚠️ The app's `.env` is **bundled inside the APK**, so anyone who has the APK can read it. Only
put non-secret settings here. The database password, JWT secret and AWS keys live only in the
backend's `.env`.

Priority order: `--dart-define=API_BASE_URL=…` → `.env` → `http://10.0.2.2:4747` (emulator).
You can also change the server inside the app: tap the server chip on the sign-in screen, or
go to Profile → Server. "Default" switches back to the `.env` value. Both phones must use the
same server.

## Run

```bash
flutter pub get
flutter run
flutter build apk --release --split-per-abi
```

## Tests

```bash
flutter test                                                  # unit tests
DUET_TEST_SERVER=http://127.0.0.1:4747 flutter test           # + end-to-end sync through a live backend
```

## Structure

```
lib/
  app/                 app shell, router, global love-tap / "join" listener
  core/                theme, server config, dio client, storage, widgets
  features/
    auth/              sign in / sign up, server settings
    pairing/           invites, couple overview
    home/              dashboard
    session/
      data/            SessionSocket (reconnecting ws) + SessionClient (pure Dart)
      domain/          RoomState, ClockSync, SyncEngine, SyncablePlayer
      presentation/    SessionController (Riverpod)
    library/           device library (photo_manager), file picker, fingerprint, auto-find
    player/            media_kit + YouTube players, watch screen, start/join flows
    sharing/           temporary upload (resumable multipart → S3) + streaming
    chat/              chat controller + view (replies)
    history/           local history store, continue watching, stats
    profile/           name, avatar, unpair, sign out
```

## Notes

* Android 13+ asks for *Videos* / *Music* access, used only to list files already on the phone.
* `android:usesCleartextTraffic="true"` is set so a plain `http://` LAN server works. Remove it
  if you only use an https server.
* Songs keep playing while the screen is off as long as Android keeps the app alive. There's no
  lock-screen media notification yet.

## Logo & app icons

The logo is drawn in code (`lib/core/widgets/duet_logo.dart`): two overlapping shapes (two
people) with a play button. There's one version per theme: **General** (blue circles), **Love**
(a heart) and **Friends** (tangerine and teal circles with a spark). The same painter draws the
in-app logo and renders the launcher icons:

```bash
flutter test tool/generate_app_icons_test.dart
```

This regenerates the Android legacy, adaptive and themed (monochrome) icons for all three themes,
the iOS icon set (General, opaque), and `branding/*.png` (1024 px logos plus a preview sheet).

**Icon follows the theme (Android).** `AndroidManifest.xml` declares three launcher aliases
(`.LauncherGeneral`, `.LauncherLove`, `.LauncherFriends`). `MainActivity.kt` enables the one
matching the shared theme when you leave the app. You can turn this off in Profile → "App icon
follows the theme", which keeps the General icon. Some launchers drop a pinned home-screen shortcut
when the icon changes; the app stays in the app drawer. iOS keeps the General icon.
