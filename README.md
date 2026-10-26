<p align="center"><img src="media/icon-256.png" width="128" height="128" alt="Skeen Status icon"></p>

# Skeen Status

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)](https://www.apple.com/macos/) [![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

🟢 **Skeen Status** watches [skeen](https://github.com/jinndi/SKeen) on your Keenetic router from the Mac menu bar. A dot tells you at a glance whether sing-box is running, and a banner tells you the moment it stops, so you never wonder why a blocked site won’t open.

The app keeps one SSH session to the router and asks `skeen status` every 15 seconds. It also reads sing-box’s own Clash API for traffic, connections, and the current outbound. You can start or restart skeen from the window, and run your own scripts on this Mac when it goes down or comes back.

[Русская версия](README.RU.md)

![The overview: status orb, tiles, and charts](media/screenshot-overview.png)

## What you get

- 🟢 **A dot in the menu bar**: green while skeen runs, red when it stopped, yellow when the router is out of reach. The menu shows the PID, memory, uptime, traffic, and the outbound in use.
- 📊 **An overview with charts**: speed, connections, memory, and availability, from the last five minutes to all time. Hover a chart to read the exact value.
- 🔔 **Banners that mean it**: one bad reading is checked again 3 seconds later, so a restart or a Mac waking from sleep never rings a false alarm. The banner says how long sing-box ran or how long it was down, and a button starts it again.
- 🎛️ **skeen at hand**: start, stop, restart, reload, and check the config. Everything that cuts traffic asks first.
- 📜 **The sing-box log**: tail it live, filter warnings and errors, search, or pause.
- ⚙️ **Scripts on this Mac**: run any shell commands when skeen goes down or comes back, for example to switch your own VPN on.
- 🧭 **Reads skeen, not its wording**: skeen 5 prints its status in Russian and in color, and the app reads it all the same. A live Clash API proves sing-box runs even when SSH drops.
- 🔐 **Safe by default**: the password lives in the Keychain, the router’s host key is pinned on first connect, and a changed key stops the app from talking to an impostor.
- 📦 **Move to another Mac in one file**: export the settings, the password, and the pinned key in a file sealed with a passphrase you choose.
- 🪟 **Liquid Glass**: the window uses macOS 26’s native glass, and the status orb is a Metal shader of flowing waves.

## Get started

1. Install Xcode from the App Store. There’s no signed release yet, so the app builds on your Mac.
2. Run the installer. It builds the app and puts it into `/Applications`:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/MairwunNx/skeen-status-macos/master/scripts/install.sh | bash
   ```

3. Click the dot in the menu bar, open **Настройки…**, and enter the router’s address, SSH port, login, and password. The defaults fit a stock skeen setup: `192.168.1.1`, port `2022`, user `admin`.
4. Press **Проверить связь**, then **Сохранить**. The dot turns green within seconds.

The app starts in the menu bar only and has no Dock icon. Open it again from Finder or Spotlight to bring the window up.

> [!TIP]
> The installer signs ad hoc by default, and then the Keychain asks for the password again after every update. Sign with a stable identity, even a self-signed one, to keep it quiet: `SKEEN_SIGN_IDENTITY="My Local Signing" bash install.sh`.

## More screenshots

| The menu | The sing-box log |
| --- | --- |
| ![The menu bar dropdown](media/screenshot-menu.png) | ![The live sing-box log](media/screenshot-logs.png) |

| Connection | Scripts | General |
| --- | --- | --- |
| ![Connection settings](media/screenshot-connection.png) | ![Scripts](media/screenshot-scripts.png) | ![General settings](media/screenshot-general.png) |

## How it tells running from stopped

skeen prints a `PID:` line only while sing-box runs, and the words `running` and `stopped` survive every translation. The app looks for those, so a new skeen release that rewords its output doesn’t break it. If your setup prints something else, pick **По своему правилу** in the connection settings and give a substring or a regular expression.

On top of SSH, the app asks sing-box itself through `experimental.clash_api`, at `http://<router>:9090` by default. When the API answers, sing-box is alive, even if SSH is down or skeen printed something odd. Turn it off or point it elsewhere in the same tab.

## Move to another Mac

Open **Общие → Перенос на другой Mac → Экспортировать…** and choose a passphrase of at least 8 characters. On the other Mac, install the app and press **Импортировать…** with the same passphrase.

The file holds the settings, the SSH password, the Clash API secret, and the pinned host key. It’s sealed with AES-256-GCM under a key derived from the passphrase by PBKDF2-HMAC-SHA256 with 600 000 iterations and a random salt, and the header is authenticated too. Without the passphrase the file is useless, so send the two by different channels.

## Privacy and security

- The SSH password and the Clash API secret live in the login Keychain under `skeen-status-macos`. They never reach `config.json`.
- The config sits in `~/Library/Application Support/skeen-status-macos/config.json` with mode `0600`, next to the app’s own log and the chart history.
- The app pins the router’s SSH host key on first connect and refuses to log in if it changes. **Подключение → Забыть ключ** resets it after you replace the router.
- Scripts run on this Mac through `/bin/sh -c`, never on the router.
- The app talks only to your router. It sends nothing anywhere else.

## For developers

Skeen Status is a SwiftUI and AppKit app on [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture), laid out by [Feature-Action Architecture](https://github.com/MairwunNx/Feature-Action-Architecture). [Citadel](https://github.com/orlandos-nl/Citadel) carries SSH and [Alamofire](https://github.com/Alamofire/Alamofire) carries the Clash API.

```
SkeenStatus/
  App/        the root reducer, the window, the menu bar, the demo mode
  Features/   Monitor, ServiceControl, Logs, Settings: a reducer and its views each
  Entities/   Skeen (status, version, controls, log) and SingBox (the Clash API)
  Shared/     config, SSH, Keychain, notifications, helpers, glass UI, the orb shader
```

A layer imports only from the layers below it, and a feature never imports another feature. Their delegate actions meet in `AppFeature`.

```sh
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' -skipMacroValidation build
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' -skipMacroValidation test
```

Xcode 27 ships the Metal compiler apart; get it once with `xcodebuild -downloadComponent MetalToolchain`.

Launch with `--demo` to run against a made-up router: no network, no Keychain, no files. UI tests and the screenshots above use it. `--tab overview|logs|connection|scripts|general` opens the window on a tab.

## Related projects

- **[Feature-Action Architecture](https://github.com/MairwunNx/Feature-Action-Architecture)** – slice the code into features, replace services with actions. Skeen Status is laid out by it.

## Credits

- The icon is drawn in code by [`scripts/draw-icon.swift`](scripts/draw-icon.swift) and ships under the project’s MIT license.
- The wave orb takes its idea from the Shadertoy shaders [wdyczG](https://www.shadertoy.com/view/wdyczG) and [4sS3Dc](https://www.shadertoy.com/view/4sS3Dc). The Metal code is written from scratch.
- [SKeen](https://github.com/jinndi/SKeen) and [sing-box](https://github.com/SagerNet/sing-box) do the real work on the router.

> 🫡 Made by Pavel Erokhin (Павел Ерохин), aka mairwunnx.
