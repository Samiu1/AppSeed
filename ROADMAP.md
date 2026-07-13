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
  data store, SPA-aware navigation, OAuth via `ASWebAuthenticationSession`,
  downloads, popups), factory clone pipeline, transient HUD, permissions.
- Window drag / traffic-light overlap fix; foreign-app overwrite protection;
  external `inject.js`/`custom.css` customization folders.
- CI build workflow.
- Menu bar status item + plain-language Help window + About.
- Custom leaf icon (app icon + menu bar template) from `Resources/leaf.svg`.
- Settings window (shortcut recorder + install-location picker), moved out of HUD.
- **Start at Login** toggle (`SMAppService`, `LoginItemManager.swift`).

---

## 🔲 Outstanding

### A. On-device validation — needs a human (highest priority)
These are coded but unverified against live services; the spec flags them as the
riskiest assumptions.

- [ ] **Google/OAuth login flow.** Wrap Gmail, sign in, confirm the
  `ASWebAuthenticationSession` handoff lands session cookies back in the wrapped
  app's shared `WKWebsiteDataStore`. Highest-risk item — validate before relying
  on real-app wrapping. If it fails, likely fix: Safari-UA popup-window strategy.
- [ ] **Real-app pass.** Wrap Notion, Figma, Slack, WhatsApp Web. Exercise
  downloads, `window.open` popups, video-call camera/mic prompts, external links.

### B. Non-technical-user features (build order)
1. [ ] **"My Apps" list** — menu-bar submenu of every app AppSeed created (scan
   install dir for `com.appseed.wrapped.*` via `AppFactory.isAppSeedClone`), with
   Open / Show in Finder / **Remove** (delete the `.app` *and* its
   `~/Library/WebKit/<bundle id>` data — otherwise impossible for a normal user).
2. [ ] **Update All Apps** — regenerate every wrapped app in place with the
   current embedded engine (logins survive via deterministic bundle id). Builds
   on #1. Also refreshes stale icons/engine on existing apps (e.g. current
   `Linear.app`). This is the "Layer 2" update path (see Distribution below).
3. [ ] **Web notifications bridge** — biggest "why doesn't this work" gap
   (WhatsApp/Gmail/Slack). JS shim forwarding page `Notification` →
   `WKScriptMessageHandler` → `UNUserNotificationCenter`. Explicit v1 cut.
4. [ ] **Icon preview in HUD** — show fetched site icon before create, with a
   "choose your own image" option.
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

Do **A (Google-login validation)** yourself — 10 min, decides whether the auth
design holds. In parallel, a fresh chat can build **B1 → B2** ("My Apps" +
"Update All Apps") as a set — they compound into the install-and-forget
experience, and don't touch signing/distribution at all.
