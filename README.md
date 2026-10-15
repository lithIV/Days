# Tock

A small, native-feeling iOS timer app (SwiftUI, iOS 17+).

- Run as many timers as you want at once, each with an optional label
- Quick-start presets (1m → 1h) and a Recents list
- Pause / resume / +1 minute / restart, progress ring per timer
- Rings with sound + haptics when done, plus a local notification if you're out of the app
- Follows system dark/light mode, or force one from the top-left menu
- Home Screen (small/medium) and Lock Screen widgets

## Getting the IPA

Every push to this branch builds an unsigned `Tock.ipa` on GitHub Actions and
attaches it to the **`tock-latest`** release (also uploaded as a workflow
artifact). Open it on your phone and share it to LiveContainer.

## Building yourself (macOS)

```sh
brew install xcodegen
xcodegen generate
open Tock.xcodeproj
```

## LiveContainer notes

LiveContainer runs the app inside its own process, so iOS never registers the
app's extensions: **the widget won't show up under LiveContainer.** The widget
works if you install the IPA normally with SideStore / AltStore / TrollStore.
Notifications are delivered through LiveContainer, so allow notifications for
LiveContainer itself.
