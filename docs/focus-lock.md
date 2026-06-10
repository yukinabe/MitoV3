# Focus Lock — app blocking during focus sessions

Two layers (see `MitoV3/FocusLock.swift`):

## 1. Soft lock — ships today, no entitlement

When a **timed** focus session (Focus / Deep Focus) is running, leaving Mito for
another app voids the run: no ATP, no streak credit, no quest progress. Driven
by `scenePhase`; the session view auto-ends with a "YOU LEFT — RUN VOID"
screen. Count-up mode is exempt (it has no target to game).

Toggle: **Settings → Focus Lock → Stay-in-app lock** (`focus.softLock`,
default on). Works in the Simulator and needs nothing from Apple.

## 2. Real shield — needs Apple approval before it works

Optional OS-level block of chosen apps via Apple's **Screen Time / Family
Controls** API (`ManagedSettingsStore.shield`). The user picks apps with the
system `familyActivityPicker` (iOS hides real app identities, so the picker is
the only way — we store opaque tokens). Toggle + picker live in
**Settings → Focus Lock → Block apps**.

The code compiles and links without anything special, but it will not *function*
until BOTH are true:

1. **Request the entitlement from Apple.** `com.apple.developer.family-controls`
   is a *restricted* entitlement. Apply at
   <https://developer.apple.com/contact/request/family-controls-distribution>.
   Focus/study apps are an accepted use case.
2. **After Apple grants it**, add it to `MitoV3/MitoV3.entitlements`:
   ```xml
   <key>com.apple.developer.family-controls</key>
   <true/>
   ```
   Do **not** add it before then — a restricted entitlement that isn't in your
   provisioning profile breaks code-signing on every build, including the
   Simulator.

Also note: Family Controls **does not work in the Simulator** — authorization
and shielding only function on a real device.

## Why there is no "silence notifications" switch

iOS gives third-party apps **no API** to enable Do Not Disturb or a system Focus
mode. That's reserved for the OS. The app shield removes the temptation, which
is the real goal; a fake "silence" toggle would do nothing, so it isn't there.
