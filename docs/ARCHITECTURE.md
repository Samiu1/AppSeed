# Architecture

AppSeed is two Swift binaries built by one script, with no Xcode project and
no third-party dependencies.

```
AppSeed/
  AppSeed/          The factory application (background agent)
    App/            Delegate, hotkey, menu bar status item, permissions, login item, favorites
    Factory/        Cloning pipeline, headless CLI, icon/title fetching, registry, updater
    Views/          HUD (Spotlight-style input card), Settings window, update progress window
    Resources/      Info.plist, leaf.svg brand asset
  AppSeedEngine/    The runtime blueprint cloned into every generated app
    Core/           Engine delegate, browser window, navigation policy, popups
    Inject/         inject.js / custom.css injection, web-to-native notification bridge
    Resources/      Default AppConfig.json, Info.plist
  Shared/           AppConfig, DomainUtils, EngineVersion (compiled into both binaries)
  Scripts/          build.sh, make-default-icon.swift
```

## The factory / engine split

**AppSeed** is an `LSUIElement` background agent: no Dock icon, reached
through the menu bar status item or the global hotkey. It owns the HUD, the
generation pipeline, Settings, and the "Update All Apps" flow.

**AppSeedEngine** is a complete, standalone `.app`: a hidden-title-bar
`NSWindow` filled edge-to-edge with a `WKWebView`, plus the navigation
policy, injection system, and notification bridge. It is compiled first and
embedded at `AppSeed.app/Contents/Resources/Engine/AppSeedEngine.app`.

Generation is cloning, not compiling: the factory copies the pre-built
engine bundle and mutates the copy. That is why generation completes in
under a second and why a generated app is frozen on the engine version that
built it (stamped as `engineVersion` in its `AppConfig.json`; see
`Shared/EngineVersion.swift`).

## Generation pipeline

`AppSeed/Factory/AppFactory.swift` runs the pipeline. Every step operates on
a copy inside a UUID-named temp directory; only a finished, signed bundle is
moved to the destination.

1. **Normalize input** (`InputNormalizer`): default the scheme to `https`,
   reject non-URLs, sanitize the app name into a legal macOS filename.
2. **Resolve collisions**: never silently overwrite. Overwrite is honored
   only when the existing bundle is an AppSeed clone (bundle id under
   `com.appseed.*`); anything else is downgraded to auto-rename
   (`App 2.app`). The foreign-bundle guard means AppSeed can never destroy
   an app it did not create.
3. **Clone** the engine blueprint into staging.
4. **Rename the executable** in `Contents/MacOS`, not just the plist - the
   menu bar, Force Quit, and Activity Monitor all read the binary name.
5. **Rewrite Info.plist**: display name plus the deterministic bundle id
   `com.appseed.wrapped.<domain-slug>` (`Shared/DomainUtils.swift`). The id
   is a pure function of the site's registrable domain, so regenerating an
   app for the same site reuses its `WKWebsiteDataStore` and Keychain:
   logins survive.
6. **Write `AppConfig.json`**: app name, URL, window size, and the current
   `EngineVersion`. Read once at launch by the engine; there is no live
   config channel.
7. **Install the icon** (`IconBuilder`): scrape the site's touch icons,
   download the best candidate, build a real `.icns` with `sips` +
   `iconutil`. Icon failure is non-fatal: the app keeps the default leaf.
8. **Strip quarantine, then sign**: `xattr -cr` first, then
   `codesign --force --deep --sign -`. A quarantined + ad-hoc-signed bundle
   is exactly what Gatekeeper rejects as "damaged"; the order is the signing
   model, not a workaround.
9. **Install** into `~/Applications` (default; configurable in Settings) and
   nudge Launch Services so Finder shows the right icon.

The same pipeline backs both the HUD and the headless CLI
(`HeadlessFactoryCLI`), so CI exercises the real product path.

## Engine runtime

- **Navigation policy** (`NavigationCoordinator`): same-registrable-domain
  loads stay in-window (SPA route changes never reach the delegate).
  Genuine user-initiated cross-domain clicks hand off to the default
  browser, but redirects and form posts are allowed through, because OAuth
  return legs and checkout flows bounce across domains mid-flow.
  `window.open` popups become real secondary windows built from the
  `WKWebViewConfiguration` WebKit provides, so they share the app's data
  store. Third-party identity providers (Google, Microsoft, Apple) are kept
  inside the app's WebView - see the OAuth decision in
  [DECISIONS.md](DECISIONS.md).
- **Downloads**: anything the web view cannot render becomes a download into
  `~/Downloads`, with collision-safe renaming.
- **Injection** (`ResourceInjector`): per-app `inject.js` / `custom.css`
  from `~/Library/Application Support/AppSeed/<bundle id>/`, applied via
  `WKUserContentController` at document end. Bundle Resources are honored
  as a fallback. The folder lives outside the bundle so edits never
  invalidate the signature and regeneration never wipes them.
- **Notifications** (`NotificationBridge`): a JS shim replaces
  `window.Notification`; calls cross a `WKScriptMessageHandler` to
  `UNUserNotificationCenter`, report the real OS permission back, and route
  clicks to the originating window. Foreground `Notification` API only;
  background service-worker push is out of scope.
- **Media and dialogs**: camera/mic requests forward to the native macOS
  prompt; `alert`/`confirm`/`prompt` become native panels; file inputs get
  a real `NSOpenPanel`.

## The update model

Two layers. **Layer 1** is AppSeed itself (a new build ships a new factory).
**Layer 2** is the apps it generated: they stay on their original engine
until regenerated. `WrappedAppsRegistry` discovers AppSeed-created apps by
scanning install directories (the bundles on disk are the source of truth;
no database). `AppUpdater` regenerates any app whose stamped engine version
is below `EngineVersion.current`. Because bundle ids are deterministic, the
rebuilt app keeps its sessions.

## Build and CI

`Scripts/build.sh` renders the brand icon from `leaf.svg`, compiles the
engine, codesigns it, compiles the factory, embeds the engine, signs again,
and verifies both signatures. Target triple is `arm64-apple-macos13.0`;
`APPSEED_SDK` overrides the SDK path when Command Line Tools updates leave
the default SDK a patch version behind the compiler. CI
(`.github/workflows/build.yml`) runs the same script on `macos-15` plus the
end-to-end smoke test described in [EVALUATIONS.md](EVALUATIONS.md).
