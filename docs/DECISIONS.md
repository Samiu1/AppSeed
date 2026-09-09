# Decision log

The calls that shape AppSeed, with the tradeoff accepted for each and the
condition that should trigger a revisit.

## 1. Clone a pre-compiled engine blueprint

- **Decision:** the factory embeds a compiled `AppSeedEngine.app` and
  generates apps by cloning and mutating it, not by compiling or linking
  anything per app.
- **Why:** generation completes in under a second, needs no toolchain at
  runtime, and every generated app is a self-contained bundle the user can
  move or delete like any other app.
- **Tradeoff accepted:** generated apps freeze on the engine that built
  them. `EngineVersion` stamping plus "Update All Apps" is the mitigation.
- **Revisit when:** engine updates become frequent enough that stale apps
  are the common case, or a shared-runtime model would serve better.

## 2. Deterministic bundle id per domain, never a UUID

- **Decision:** `com.appseed.wrapped.<domain-slug>` is a pure function of
  the site's registrable domain.
- **Why:** macOS silos `WKWebsiteDataStore` and Keychain by bundle id, so a
  stable id means regenerating an app keeps its logins and local storage.
  It also powers the foreign-bundle guard and the update check. CI asserts
  this invariant.
- **Tradeoff accepted:** one app per domain; you cannot run two isolated
  copies of the same site.
- **Revisit when:** users ask for multiple profiles per site (work/personal
  accounts).

## 3. Zero dependencies, system tools only

- **Decision:** plain `swiftc` builds, and icon/signing work runs through
  `sips`, `iconutil`, `codesign`, `xattr`, and `lsregister`. No Swift
  packages, no CocoaPods, no Sparkle.
- **Why:** the whole build runs on the Xcode Command Line Tools alone, in
  CI and on any Mac, with nothing to vendor or audit.
- **Tradeoff accepted:** a hand-maintained multi-part public-suffix list in
  `DomainUtils` (a known approximation, not the full PSL) and regex-based
  title/icon scraping.
- **Revisit when:** a specific dependency earns its keep - the full Public
  Suffix List is the first candidate.

## 4. Apple Silicon only

- **Decision:** the build targets `arm64-apple-macos13.0`; no universal
  binary.
- **Why:** the spec deferred Intel; GitHub's `macos-14/15` runners are
  M-series, so CI and local builds agree.
- **Tradeoff accepted:** Intel Macs cannot run it.
- **Revisit when:** real Intel demand appears.

## 5. Carbon `RegisterEventHotKey` for the global hotkey

- **Decision:** the hotkey uses Carbon, a deprecated API.
- **Why:** it is the only native mechanism that fires while the app is not
  focused - the entire product interaction depends on that. SwiftUI
  shortcuts and `NSEvent` local monitors only fire when focused.
- **Tradeoff accepted:** deprecation risk; a deliberate refusal to
  "modernize" into something that breaks the trigger.
- **Revisit when:** Apple ships a supported replacement for background-agent
  hotkeys.

## 6. OAuth stays inside the app's WebView

- **Decision:** third-party identity providers (Google, Microsoft, Apple)
  complete their flow in the app's own WebView or a shared-store popup -
  not in `ASWebAuthenticationSession`.
- **Why:** learned on-device. The hand-off version failed with "Invalid
  OAuth state": the site starts the flow in the WebView (recording `state`
  against its cookie jar), but the auth session runs in a separate Safari
  context, so the redirect returns to the wrong jar and the login neither
  validates nor persists. One context keeps `state` and cookies consistent;
  a desktop-Safari user agent clears Google's `disallowed_useragent` block.
- **Tradeoff accepted:** embedded-webview OAuth leans on the user agent
  staying accepted by providers.
- **Revisit when:** providers harden against embedded views. Do not
  reintroduce the `ASWebAuthenticationSession` hand-off.

## 7. Atomic staging, and never overwrite a foreign app

- **Decision:** every mutation happens in a temp directory and only a
  finished, signed bundle reaches the destination; overwrite is honored
  only for bundles AppSeed itself created.
- **Why:** a half-built app must never appear launchable, and AppSeed must
  never be able to destroy, say, the real LinkedIn.app because a user named
  their wrapped app "LinkedIn".
- **Tradeoff accepted:** an overwrite request against a foreign app is
  silently downgraded to auto-rename, which can surprise.
- **Revisit when:** the downgrade confuses users in practice.

## 8. `~/Applications` as the default install location

- **Decision:** generated apps install per-user by default; `/Applications`
  is an explicit opt-in only.
- **Why:** no admin rights required, no permission prompts, and the apps
  belong to the person who made them.
- **Tradeoff accepted:** no system-wide installs by default.
- **Revisit when:** managed (MDM) or shared-machine distribution matters.

## 9. A visible menu bar home (amendment to the original spec)

- **Decision:** AppSeed keeps a permanent status item, although the original
  model was "exists only when invoked."
- **Why:** non-technical users need a discoverable, clickable path to
  everything the hotkey does - Settings, My Apps, Help.
- **Tradeoff accepted:** one more always-on menu bar icon.
- **Revisit when:** - settled; this is the product now.

## 10. Security posture: documented gaps before distribution

- **Decision:** ship the current ad-hoc-signed, unsandboxed engine for
  personal use, and gate broader distribution on the hardening list
  (S1-S8 in [ROADMAP.md](../ROADMAP.md)): hardened runtime, download
  quarantine, ATS scoping, media-prompt scoping, and notarization.
- **Why:** the open items require local presence to exploit and are
  hardening, not remote holes; the honest fix is sequenced work, not a
  silent claim of safety.
- **Tradeoff accepted:** the repo publicly documents its own gaps.
- **Revisit when:** a paid Apple Developer account exists - S1 (hardened
  runtime) and notarization land together.
