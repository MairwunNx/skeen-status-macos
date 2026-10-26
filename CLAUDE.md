# Skeen Status

Menu-bar app for macOS. It keeps one SSH session to a Keenetic router, polls `skeen status`, reads sing-box's Clash API, and shows whether sing-box is running. The app has no Dock icon (`LSUIElement`) and starts in the menu bar only.

User-facing copy is Russian. Code, types, and comments are English. The README exists in English (`README.md`) and Russian (`README.RU.md`); change both together.

## Build and test

Xcode project `SkeenStatus.xcodeproj`, scheme `SkeenStatus`. Swift 6, macOS 26. There is no `Package.swift`: the Swift packages are wired in the Xcode project.

- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) 1.26.x for state, reducers, dependencies, and `@Shared`.
- [Alamofire](https://github.com/Alamofire/Alamofire) 5.12.x for the Clash API.
- [Citadel](https://github.com/orlandos-nl/Citadel) 0.12.x for SSH.

```bash
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' -skipMacroValidation build
xcodebuild -project SkeenStatus.xcodeproj -scheme SkeenStatus -destination 'platform=macOS' -skipMacroValidation test
```

The status orb is a Metal shader. Xcode 27 needs `xcodebuild -downloadComponent MetalToolchain` once. `scripts/install.sh` builds a Release and installs it into `/Applications`.

Unit tests use Swift Testing in `SkeenStatusTests`, laid out by layer. Pure functions get plain tests; reducers get `TestStore` tests with dependencies overridden and `@Shared` values replaced by `Shared(value:)`. `SkeenStatusUITests` launches the app with `--demo`.

Source folders are synchronized roots. A new file inside `SkeenStatus/`, `SkeenStatusTests/`, or `SkeenStatusUITests/` is picked up by Xcode. Do not add file references to `project.pbxproj` by hand.

## Layout: Feature-Action Architecture

The code follows [FAA](https://github.com/MairwunNx/Feature-Action-Architecture). A layer imports only from the layers below it. A feature never touches another feature, and an entity never touches another entity.

```
SkeenStatus/
  App/        AppFeature (root reducer), AppDelegate, StatusItemController, SettingsRootView, DemoMode
  Features/
    Monitor/        polling, confirmation, transitions, banners, scripts, metrics, the dashboard
    ServiceControl/ skeen start/stop/restart/reload/check and the version
    Logs/           the sing-box log tail
    Settings/       the config draft, Keychain secrets, encrypted export and import
  Entities/
    Skeen/    SkeenState, parsers, SkeenClient (commands over the router shell), @Shared(.skeenSnapshot)
    SingBox/  ClashAPI (Alamofire, read only), outbound groups, @Shared(.singBoxSnapshot)
  Shared/
    Config/   Config, ConfigStore, @Shared(.config)
    Infra/    SSH session and RouterShell, Keychain, AppLog, LocalShell, Notifier, LoginItem
    Lib/      pure helpers
    UI/       glass cards, the StatusOrb shader, list editor
```

Features talk through delegate actions that `AppFeature` routes, e.g. `service(.delegate(.serviceChanged))` → `monitor(.checkNow)`.

## Rules that keep the design intact

- Every side effect goes through a TCA dependency (`@DependencyClient` with `liveValue` and `testValue`). Reducers never call AppKit, the Keychain, the filesystem, or the network directly.
- The project has no default actor isolation. Views and AppKit controllers are `@MainActor`; `SSHSession` is an `actor`.
- Shared state lives in `@Shared` keys: `.config`, `.skeenSnapshot`, `.singBoxSnapshot`. Do not copy them into other state.
- `parseStatus` never returns `.unreachable`; only a failed SSH reading does. `.automatic` detection looks for a `PID:` line or the words `running`/`stopped`, never for translated labels.
- A move into stopped or unreachable must show up twice in a row (`confirm`) before scripts and banners fire. A live Clash API counts as running (`resolveState`).
- `transition` decides banners and scripts. Scripts run only on the real running↔stopped edges; unreachable counts as stopped only with `treatUnreachableAsDown`.
- The Clash API is read only. Do not add controls that switch modes or outbounds.
- The SSH password and the Clash API secret are never written to `config.json`. `Keychain` stores them under service `skeen-status-macos`, accounts = login and `clash-api`.
- Config lives at `~/Library/Application Support/skeen-status-macos/config.json` with mode `0600`. Decode new fields with `decodeIfPresent` and a default so older files still load.
- `SSHSession` keeps one long-lived PTY, runs post-connect commands, proves the shell with a marker round trip, and pins the router's host key on first connect. Commands are wrapped with markers from `CommandMarker.swift`. Do not open a new SSH connection per poll.
- The settings file is AES-256-GCM with a PBKDF2-HMAC-SHA256 key (600 000 iterations, random salt) and an authenticated header. Do not weaken it.
- `--demo` must stay fully offline and diskless: override every live dependency in `DemoMode.apply`, including `metricsStore`.
- The app is not sandboxed (`ENABLE_APP_SANDBOX = NO`); sandboxing would break SSH, local scripts, and `SMAppService`.
- Signing for local builds is ad hoc (`CODE_SIGN_IDENTITY = "-"`). Do not commit a personal development team or identity.
- Bundle id is `com.mairwunnx.SkeenStatus`. Version is `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the app target.

## Product behavior worth preserving

Default router is `192.168.1.1:2022`, user `admin`, then `exec sh`, then `skeen status`. Poll interval defaults to 15 seconds and is clamped to at least 3. The Clash API defaults to `http://<gateway>:9090`. The log tail is `tail -n N` of `/opt/var/log/sing-box.log`, fetched only while the logs tab is on screen; the dashboard reads the Clash API every 2 seconds only while it is on screen.

Service buttons call `skeen start|stop|restart|reload|check`. `stop`, `restart`, and `reload` interrupt traffic and the UI confirms them.

## Commits

Small, atomic commits with one plain-English line in the imperative that says what changes for the user, e.g. “Check a stop a second time before scripts and banners run”. No CI and no releases yet.
