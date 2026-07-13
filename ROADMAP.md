# AppSeed — Roadmap & Handoff

Status snapshot for continuing development in a fresh session. AppSeed is a
native macOS (Swift, arm64) utility that turns any URL into a standalone `.app`
by cloning a pre-compiled engine bundle. See `CLAUDE.md`-style context below.

## How to build & test (no Xcode project — script-based)

```bash
# Build both bundles (arm64). Renders icon from Resources/leaf.svg, embeds
# the engine into AppSeed.app/Contents/Resources/Engine/AppSeedEngine.app.
Scripts/build.sh

# Headless end-to-end test of the factory (no HUD/hotkey needed):
build/AppSeed.app/Contents/MacOS/AppSeed --make https://linear.app [--name N] [--out DIR] [--overwrite]

# Launch the real app (menu bar leaf appears; ⌥P opens the HUD):
open build/AppSeed.app
```

CI runs the same build + a `--make` smoke test on every push (`.github/workflows/build.yml`).

## Load-bearing invariants (do not break)

- **Deterministic bundle id** `com.appseed.wrapped.<domain-slug>` — never a UUID.
  Keeps `WKWebsiteDataStore`/Keychain (logins) alive across regeneration.
- **`xattr -cr` before `codesign`** (ad-hoc) — a quarantined + ad-hoc-signed
  child fails Gatekeeper with "damaged, move to Trash."
- Build atomically in a temp dir; only a finished bundle reaches the destination.
- Rename the binary in `Contents/MacOS`, not just the plist (menu bar / Force
  Quit / Activity Monitor read the binary name).
- Never overwrite an app AppSeed didn't create (foreign-bundle guard).
- Global hotkey stays **Carbon `RegisterEventHotKey`** (works while unfocused).

---

## ✅ Done (shipped to `main`)

- Original spec Phases 0–4: engine runtime (title-barless WKWebView, isolated
  data store, SPA-aware navigation, in-WebView OAuth, downloads, popups),
  factory clone pipeline, transient HUD, permissions.
- Window drag / traffic-light overlap fix; foreign-app overwrite protection;
  external `inject.js`/`custom.css` customization folders.
- CI build workflow.
- Menu bar status item + plain-language Help window.
- Custom leaf icon (app icon + menu bar template) from `Resources/leaf.svg`.
- Settings window (tabbed: General | My Apps) — shortcut recorder,
  install-location picker, Start at Login — all moved out of the HUD.
- **Start at Login** toggle (`SMAppService`, `LoginItemManager.swift`).
- **Dark-themed windows + custom About panel** (`AboutWindowController`) — all
  app windows (Settings, Help, Update, About) use the HUD dark look.
- **OAuth fix** — third-party logins (Google/Microsoft/Apple) stay in the app's
  WebView; the `ASWebAuthenticationSession` hand-off was removed (it caused
  "Invalid OAuth state"). See the design note in `NavigationCoordinator.swift`.

---

## 🔲 Outstanding

### A. On-device validation — needs a human
- [x] **Google/OAuth login flow — VALIDATED** on comix.to (Google sign-in works
  and persists). The original `ASWebAuthenticationSession` hand-off failed with
  "Invalid OAuth state" (flow split across two contexts); fixed by keeping the
  whole OAuth flow in the app's WebView with its desktop-Safari UA. See the
  OAuth design note in `NavigationCoordinator.swift` — do not reintroduce the
  hand-off.
- [ ] **Real-app pass (broaden).** comix.to confirmed. Still worth spot-checking
  Notion, Figma, Slack, WhatsApp Web for downloads, `window.open` popups,
  video-call camera/mic prompts, and external links.

### B. Non-technical-user features (build order)
1. [x] **"My Apps" list — DONE** (`WrappedAppsRegistry`). Menu bar shows only
   favourited apps (quick launch); the full list lives in **Settings › My Apps**
   with favourite ⭐, Show in Finder, and Remove (moves the `.app` *and* its
   per-bundle-id login/cache data to the Trash). `FavoritesStore` persists stars.
2. [x] **Update All Apps — DONE** (`AppUpdater`, `UpdateProgressWindowController`).
   Regenerates wrapped apps with the current engine (logins survive). Gated by
   `EngineVersion.current` stamped into each app's `AppConfig.json`: the button
   shows only when some app is on an older engine, else "All apps are up to date."
   **Remember to bump `EngineVersion.current` whenever the engine changes.**
3. [x] **Web notifications bridge — DONE** (`NotificationBridge`). JS shim
   replaces `window.Notification`, forwarding to `UNUserNotificationCenter`
   with real-permission reporting and click-through. Verified on-device.
   **Foreground `Notification` API only** — background service-worker Push
   remains out of scope (no push service / VAPID keys). Engine bumped to v3.
4. [ ] **Icon preview in HUD** — show fetched site icon before create, with a
   "choose your own image" option. (Started once, then reverted — nothing kept;
   `IconBuilder.fetchBestIconData` / `installIcon(fromImageData:)` are the
   natural hooks, plus a `customIconData` field on `FactoryRequest`. Note the
   HUD dismisses on resign-key, so guard against teardown while an NSOpenPanel
   is open. Update All / regeneration would not preserve a custom icon — decide
   whether to persist it.)
5. [ ] **First-run welcome** — teach the ⌥P interaction once on first launch.

### C. Distribution & updates (deferred — no paid Apple account yet)
Two update layers: **Layer 1 = AppSeed itself** (what you ship to users);
**Layer 2 = the wrapped apps** (handled by "Update All Apps" above).

- [ ] **Notarization + Developer ID** ($99/yr Apple Developer). *Prerequisite*
  for friction-free distribution to non-technical users — without it every
  download hits Gatekeeper. Add signing+notarize step to `Scripts/build.sh`.
  Deferred by user until paying for the account.
- [ ] **Native in-app updater** — check GitHub Releases API on launch, compare
  version, prompt → download + self-replace. All native `URLSession`, no Sparkle
  (honors the no-dependency rule). On update, prompt "Update your apps too?" →
  runs **Update All Apps**.
- [ ] **Make repo private** — GitHub → Settings → Danger Zone → Change
  visibility (manual, 10s). No secrets in repo today; keep certs/notary creds out.

### D. Optional / lower priority
- [ ] **Xcode workspace** — generate the two-target `.xcodeproj` + Copy Files
  phase (spec's original build setup) for in-IDE debugging. `build.sh` covers
  building today, so this is convenience only.
- [ ] **Intel / universal binary** — explicitly deferred by spec unless needed.

---

## Suggested next session

The core, OAuth, My Apps, Update All, notifications, and window theming are all
done. Remaining feature work is **B4 (icon preview)** and **B5 (first-run
welcome)** — both self-contained UI. The bigger arc is **C (distribution)**:
notarization + a native in-app updater, gated on getting the paid Apple
Developer account. A quick, no-code win any time is the **real-app spot-check**
(Notion / Figma / Slack / WhatsApp Web).
