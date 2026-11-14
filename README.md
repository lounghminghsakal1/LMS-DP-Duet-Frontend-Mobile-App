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
* **Live chat** while watching (below the video, or as a side panel in landscape), with a
  typing indicator. Messages sent during playback get a 🎬 timestamp chip. **Tap it and you
  both jump back to that scene.**
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

## Run

```bash
flutter pub get
flutter run                                   # Android emulator → uses http://10.0.2.2:4747
flutter run --dart-define=API_BASE_URL=http://192.168.1.26:4747   # real phone on your Wi-Fi
flutter build apk --release --dart-define=API_BASE_URL=https://your-duet-server.com
```

You can also change the server inside the app: tap the server chip on the sign-in screen,
or go to Profile → Server. Both phones must use the same server.

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
    chat/              chat controller + view
    history/           local history store, continue watching, stats
    profile/           name, avatar, unpair, sign out
```

## Notes

* Android 13+ asks for *Videos* / *Music* access, used only to list files already on the phone.
* `android:usesCleartextTraffic="true"` is set so a plain `http://` LAN server works. Remove it
  if you only use an https server.
* Songs keep playing while the screen is off as long as Android keeps the app alive. There's no
  lock-screen media notification yet.
