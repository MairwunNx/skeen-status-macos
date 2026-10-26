# Skeen Status

Menu-bar app for macOS. It keeps one SSH session to a Keenetic router, polls `skeen status`, and shows whether sing-box is running. The icon is a colored dot. The app has no Dock icon (`LSUIElement`).

User-facing copy is Russian. Code, types, and comments are English.

## Build and test

Xcode project `SkeenStatus.xcodeproj`, scheme `SkeenStatus`. Swift 6. The app target deploys to macOS 26.0. There is no `Package.swift`: the only dependency is the Swift package [Citadel](https://github.com/orlandos-nl/Citadel) 0.12.x, wired in the Xcode project.

```bash
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' build
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' test
```

Unit tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) in `SkeenStatusTests`. They cover pure functions only. `SkeenStatusUITests` launches the app. Prefer a unit test when the change is in `Core/`.

Source folders are synchronized roots. A new `.swift` file inside `SkeenStatus/`, `SkeenStatusTests/`, or `SkeenStatusUITests/` is picked up by Xcode. Do not add file references to `project.pbxproj` by hand.

## Layout

```
SkeenStatus/
  App/        process lifecycle and the status item
  State/      AppState and Config, the in-memory source of truth
  Core/       pure functions: parse, transition, menu text, command markers
  Effects/    SSH, Keychain, disk, notifications, login item, local shell
  UI/         SwiftUI settings
SkeenStatusTests/
SkeenStatusUITests/
```

`AppDelegate` loads config, builds `AppState` and `Engine`, and owns the settings window. `StatusItemController` draws the dot and rebuilds the menu from `menuModel`. `Engine` polls, applies `transition`, and runs the resulting side effects.

## Rules that keep the design intact

- `Core/` does not import AppKit, SwiftUI, Citadel, or Security. It does not touch the network, the Keychain, or the filesystem. New parsing and transition rules go there as `nonisolated` functions.
- The project default actor isolation is `MainActor`. Types and functions in `Core/` that tests call must be marked `nonisolated`. `SSHSession` is an `actor`.
- `AppState` is the only observable state. Do not cache status, config, or log lines in the menu, the window, or `Engine`.
- `parseStatus` never returns `.unreachable`. The poller sets `.unreachable` only when SSH fails.
- `transition` decides notifications and scripts. Scripts run on the real running↔stopped edges. Unreachable counts as stopped only when `treatUnreachableAsDown` is true.
- The SSH password is never written to `config.json`. `Keychain` stores it under service `skeen-status-macos`, account = login.
- Config lives at `~/Library/Application Support/skeen-status-macos/config.json` with mode `0600`. Decode new fields with `decodeIfPresent` and a default so older files still load.
- `SSHSession` keeps one long-lived PTY. Commands are wrapped with begin/end markers from `CommandMarker.swift` and run only after `exec sh`. Do not open a new SSH connection per poll.
- On-down and on-recover scripts run locally through `LocalShell` (`/bin/sh -c`), not on the router.
- The app is not sandboxed (`ENABLE_APP_SANDBOX = NO`). Sandboxing would break SSH, local scripts, and `SMAppService`. Leave it off unless the entitlements are redesigned in the same change.
- Signing for local builds is ad hoc (`CODE_SIGN_IDENTITY = "-"`). Do not commit a personal development team.
- Bundle id is `com.mairwunnx.SkeenStatus`. Version is `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the app target.

## Product behavior worth preserving

Default router is `192.168.1.1:2022`, user `admin`, then `exec sh`, then `skeen status`. Running means the output contains `Status: running` (substring or regex). Poll interval defaults to 15 seconds and is clamped to at least 3. The log tail is `tail -n N` of `/opt/var/log/sing-box.log`, fetched only while Settings is showing logs.

Service buttons call `skeen start|stop|restart|reload`. `restart` and `reload` are disruptive and the UI confirms them. `skeen version` is parsed by `parseSkeenVersion`.
