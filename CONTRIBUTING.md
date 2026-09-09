# Contributing

## Dev setup

You need macOS 13+, Apple Silicon, and the Xcode Command Line Tools.

```bash
./Scripts/build.sh           # builds build/AppSeedEngine.app + build/AppSeed.app
open build/AppSeed.app       # launches the menu bar agent
```

There is no Xcode project on purpose; `Scripts/build.sh` is the build.
Set `APPSEED_SDK` if a Command Line Tools update leaves the default SDK a
patch version behind the compiler.

## Project structure

```
AppSeed/          Factory: HUD, hotkey, menu bar, Settings, cloning pipeline
AppSeedEngine/    Runtime blueprint: WKWebView window, navigation, injection
Shared/           AppConfig, DomainUtils, EngineVersion (both binaries)
Scripts/          build.sh, make-default-icon.swift
docs/             Architecture, verification, decision log
```

## Conventions

- **Comment the why.** Load-bearing choices carry a comment where they live
  (see `NavigationCoordinator.swift` for the model). If you change a
  behavior, change its comment.
- **Bump `EngineVersion.current`** whenever engine behavior changes, or
  "Update All Apps" stops flagging stale apps.
- **Icon and signing steps use system tools** (`sips`, `iconutil`,
  `codesign`, `xattr`). No new dependencies without a decision-log entry.

## Do-not-break invariants

CI enforces the first two; the rest are on you.

1. **Deterministic bundle id** `com.appseed.wrapped.<domain-slug>` - never a
   UUID. Regeneration must keep logins alive.
2. **`xattr -cr` before `codesign`** - a quarantined, ad-hoc-signed app
   fails Gatekeeper as "damaged".
3. **Atomic builds** - mutate only in a temp directory; install finished
   bundles only.
4. **Rename the binary** in `Contents/MacOS`, not just the plist.
5. **Foreign-bundle guard** - never overwrite an app AppSeed did not
   create, whatever the caller asked for.
6. **Carbon hotkey** - do not replace `RegisterEventHotKey` with a
   focus-dependent API.
7. **OAuth in-WebView** - do not reintroduce the
   `ASWebAuthenticationSession` hand-off (see docs/DECISIONS.md #6).

## Verification checklist

- `Scripts/build.sh` succeeds and both bundles pass
  `codesign --verify --deep --strict`.
- Headless smoke test:
  `build/AppSeed.app/Contents/MacOS/AppSeed --make https://example.com --name SmokeTest --out /tmp/appseed`
  produces a signed app with bundle id `com.appseed.wrapped.example-com`
  and no quarantine attribute.
- For engine changes: regenerate a real app and confirm its login session
  survived.
