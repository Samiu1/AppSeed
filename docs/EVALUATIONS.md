# Verification and evaluations

AppSeed is a macOS system utility, so its verification layers look different
from a web service's: a CI build, an end-to-end smoke test that asserts the
product's load-bearing invariants, and on-device validation of the flows CI
cannot reach. There is no unit-test suite today; this document is the honest
record of what is checked, where, and what is still open.

## Layer 1: CI build (`.github/workflows/build.yml`)

Runs on every push and pull request to `main`, on `macos-15` (Apple
Silicon - matching the arm64-only spec).

- Compiles `AppSeedEngine.app` and `AppSeed.app` with `Scripts/build.sh`.
- Verifies both bundles' code signatures
  (`codesign --verify --deep --strict`).
- Verifies the engine blueprint is embedded inside the factory.

## Layer 2: end-to-end smoke test (same workflow)

Runs the real headless pipeline:
`AppSeed --make https://example.com --name CITest --out /tmp/appseed-ci`,
then asserts:

| Check | Why it is load-bearing |
|-------|------------------------|
| `CITest.app` exists, is executable, and passes `codesign --verify --deep --strict` | A generated app must actually launch |
| Bundle id equals `com.appseed.wrapped.example-com` exactly | The deterministic-id invariant is what keeps logins and website data alive across regeneration |
| No `com.apple.quarantine` attribute on the bundle | A quarantined, ad-hoc-signed app dies at Gatekeeper with "damaged, move to Trash" |

These two invariants are the product's trust contract; the smoke test fails
the build if either regresses.

## Layer 3: on-device validation

Flows that need a real person on a real Mac. Current status, tracked in
[ROADMAP.md](ROADMAP.md):

| Flow | Status |
|------|--------|
| Google OAuth sign-in and session persistence | Validated on comix.to (this is what retired the `ASWebAuthenticationSession` hand-off; see [DECISIONS.md](DECISIONS.md)) |
| Web notification bridge | Verified on-device |
| Broad real-app pass: Notion, Figma, Slack, WhatsApp Web (downloads, popups, camera/mic, external links) | Open |

## How to run locally

```bash
./Scripts/build.sh
build/AppSeed.app/Contents/MacOS/AppSeed --make https://example.com --name SmokeTest --out /tmp/appseed
codesign --verify --deep --strict /tmp/appseed/SmokeTest.app
```

## Known open risks

The security hardening list (S1-S8) in [ROADMAP.md](ROADMAP.md) is not
covered by automated checks: hardened runtime, download quarantine, ATS
scoping, media-prompt scoping, and related items are reviewed manually and
gate distribution beyond personal use.
