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
- Settings window — **sidebar layout** (General | My Apps | About): shortcut
  recorder, install-location picker, Start at Login, the apps manager, and an
  inline About pane. Dark HUD look; brand-leaf footer.
- **Start at Login** toggle (`SMAppService`, `LoginItemManager.swift`).
- **Dark-themed windows** — all app windows (Settings, Help, Update) use the
  HUD dark look. About is an inline Settings section (no separate window).
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

### D. Optional / lower priority
- [ ] **Xcode workspace** — generate the two-target `.xcodeproj` + Copy Files
  phase (spec's original build setup) for in-IDE debugging. `build.sh` covers
  building today, so this is convenience only.
- [ ] **Intel / universal binary** — explicitly deferred by spec unless needed.

### E. Engine (wrapped-app) UX polish
The generated apps are edge-to-edge WKWebViews with hidden title bars — no
browser chrome. Gaps to close:

- [ ] **Escape the "trapped" web experience** — no back/forward/reload except
  the obscure `⌘[` / `⌘]`. Add an **autohiding floating toolbar** (bottom-center
  or top-right) with small back / forward / reload icons that fades after
  inactivity. In `AppSeedEngine/Core/BrowserWindowController.swift`.
- [ ] **Loading progress bar** — a thin (1–2px) Safari-style bar at the top of
  the window while a page loads (observe `WKWebView.estimatedProgress`).
- [ ] **Drag-zone discoverability** — the transparent top ~28pt title strip
  gives no hint it's draggable. On hover, change the cursor / show a subtle
  gradient hairline to reveal the drag zone.

### F. HUD UX polish
In `AppSeed/Views/HUDController.swift` + `HUDPanel.swift`:

- [ ] **Active focus state** — fields set `focusRingType = .none` with no active
  styling, so the focused field isn't obvious. On
  `controlTextDidBeginEditing`/`EndEditing`, tint the field container's border
  to the clay accent.
- [ ] **Title-fetch feedback** — `TitleFetcher` runs 1–4s silently; users may
  submit with the fallback domain name or think it's frozen. Show a spinner /
  status ("Fetching site title…") while it runs.
- [ ] **Placeholder contrast** — placeholder uses `secondaryText` (0.52 alpha)
  on the charcoal surface; bump contrast for accessibility.
- [ ] **Shortcut hint in HUD** — show the current hotkey (e.g. `⌥P`) in the
  HUD's top-right to reinforce muscle memory. (Note: already surfaced in the
  menu bar's "New App ⌥P" row.)

### G. Security hardening
Env-var-injection issues assume local presence — hardening, not remote holes —
but S1 is the notarization enabler (ties to C).

- [ ] **S1 · hardened runtime + library validation (Medium)** — all bundles are
  signed `codesign --force --deep --sign -` with **no `-options runtime`**, so a
  wrapped app (live sessions, camera/mic) is injectable via
  `DYLD_INSERT_LIBRARIES`. Add `-options runtime` to the factory re-sign
  (`AppFactory.swift`) and both `Scripts/build.sh` signings. `--deep` is
  deprecated by Apple — sign nested code inside-out when moving to Developer ID.
- [ ] **S2 · quarantine downloads / add save panel (Medium)** — engine isn't
  sandboxed and has no `LSFileQuarantineEnabled`, so `WKDownload` files land in
  `~/Downloads` without `com.apple.quarantine` (skip Gatekeeper), auto-saved with
  no panel. Fix: sandbox the engine (quarantine becomes automatic) **or** set
  `LSFileQuarantineEnabled` + apply the xattr; and/or present an `NSSavePanel`.
  (`NavigationCoordinator.swift` download delegate.)
- [ ] **S3 · scope down ATS (Low)** — factory Info.plist sets
  `NSAllowsArbitraryLoads = true` (for http title/icon fetches). Drop the blanket
  flag; scope `NSExceptionDomains` or let http fetches fail (fallbacks exist).
  Mirror gap: the **engine** plist has no ATS block, so a wrapped `http://` site
  won't load — worth fixing together.
- [ ] **S4 · scope camera/mic prompts (Low)** — `requestMediaCapturePermissionFor`
  ignores `origin` and always `.prompt`s. Only `.prompt` when the origin's
  registrable domain == `appDomain`; `.deny` otherwise.
- [ ] **S5 · cross-domain main-frame loads (Low / informational)** — by design,
  cross-domain redirects/form posts render in the trusted chrome (OAuth/checkout
  survival). Documented tradeoff; consider showing the real origin when
  off-domain (ties to the E toolbar).
- [ ] **S6 · inject.js/custom.css trust (Low)** — scripts load from an
  unprotected `~/Library/Application Support/AppSeed/<id>/` into every page/frame.
  Intentional feature; add a one-time in-app confirmation or note. (CSS path is
  safe — percent-encoded into `textContent`.)
- [ ] **S7 · sanitize download filename (Low)** — `appendingPathComponent(
  suggestedFilename)` trusts WebKit to strip `/` and `..`. Add defense-in-depth
  (reuse the `InputNormalizer` app-name sanitizing).
- [ ] **S8 · show origin in JS dialogs (Low)** — `alert`/`confirm`/`prompt`
  panels show page-controlled text with no origin, enabling official-looking
  spoof dialogs. Prefix the requesting host.

**Best-practice gaps (context):** no App Sandbox on the **engine** (the biggest
containment win — small entitlement set: `network.client`,
`files.downloads.read-write`, `device.camera`, `device.microphone`; the factory
can't easily be sandboxed but the engine can); no notarization (see C, gated on
S1); incomplete hand-maintained public-suffix list in `DomainUtils.swift`
(dependency-free approximation, known failure mode); regex HTML/title parsing
(fragile but read-only, length-capped, sanitized). Secrets/config: clean.

---

## Suggested next session

Core, OAuth, My Apps, Update All, notifications, and window theming are done.
Highest-leverage remaining work, roughly in order:

- **E — engine UX** (back/forward toolbar, loading bar, drag-zone hint): the
  most user-visible gap; wrapped apps currently feel "trapped."
- **B4 / B5** — icon preview, first-run welcome: small, self-contained UI.
- **G — security**: do **S1 (hardened runtime)** alongside **C (notarization)**
  since S1 enables it; the rest (S2–S8) are low-severity, local-only hardening.
- **C — distribution**: notarization + native in-app updater, gated on the paid
  Apple Developer account.
- Any-time no-code win: **real-app spot-check** (Notion / Figma / Slack /
  WhatsApp Web).
