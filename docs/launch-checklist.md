# Mito — TestFlight Launch Checklist

Target: **external TestFlight** (public link to share with testers), not the App
Store yet. Fastest real-user feedback loop. Estimated ~2–3 days, mostly Apple +
Supabase dashboard clicks.

Legend: ☐ = to do · ✅ = done in the app/repo already

---

## 0. Account (the hard gate)
- ✅ Apple Developer Program enrolled — `DEVELOPMENT_TEAM = 359RT325UQ` is set.

## 1. Backend → production (Supabase dashboard)
- ☐ Confirm **all 13 migrations** (`0001`–`0013`) have run in the **production**
  project. You've done 0011–0013; verify 0001–0010 are applied too.
- ☐ **Verify RLS on `cards` and `decks`** (these were created in the dashboard,
  so the repo can't prove it). Each row must be owner-scoped. This is the one
  real security item before real users touch it.
- ☐ **Deploy the `mito-ai` edge function** and set the `DEEPSEEK_API_KEY` secret
  (`supabase/deploy-mito-ai.sh`). **Rotate** the key if it was ever pasted into
  chat. Powers Quiz-mode AI grading; the app falls back to local grading if it's
  down, so this is not a hard blocker — but Quiz is better with it.
- ☐ **Enable Anonymous sign-in** (Auth → Providers). The app relies on it for
  offline/first-run play.
- ☐ **Enable Leaked-password protection** (Auth → Providers → Email).

## 2. App config (repo) — mostly done
- ✅ Export compliance declared (`ITSAppUsesNonExemptEncryption = NO`).
- ✅ `PrivacyInfo.xcprivacy` manifest in the app target.
- ✅ App icon set (`AppIcon` 1024px).
- ✅ Account deletion in-app (Settings → Account → Delete) — required by Apple.
- ✅ Family Controls "Block apps" UI hidden for v1 (`BetaConfig.appShieldEnabled
  = false`) so the restricted entitlement isn't needed to ship. Re-enable in
  v1.1 after Apple grants `com.apple.developer.family-controls`.
- ☐ Decide on `MARKETING_VERSION` (currently `1.0`) and bump `CURRENT_PROJECT_
  VERSION` (build number) on each upload.

## 3. App Store Connect
- ☐ Create the app record (bundle id `com.yukinabe.mitov3`).
- ☐ Provide the **privacy policy URL** — host `docs/privacy-policy.md` somewhere
  public (Notion page, GitHub Pages, a simple site). Fill in the `[DATE]` and
  `[YOUR CONTACT EMAIL]` placeholders first.
- ☐ Fill the **App Privacy** "nutrition label":
  - Email address — App Functionality — **not** used for tracking, linked to user.
  - User ID — App Functionality — not tracking, linked.
  - Other User Content (decks/cards) — App Functionality — not tracking, linked.
  - Product Interaction (usage events) — App Functionality + Analytics — not
    tracking, linked.
  - Tracking: **No.**
- ☐ Confirm the **App Group** `group.com.yukinabe.mitov3` is registered on the
  account and enabled on both the app and widget targets (Signing &
  Capabilities). Needed for the home-screen widget.

## 4. Build → upload → TestFlight
- ☐ In Xcode: select a real device / "Any iOS Device", **Product → Archive**.
- ☐ **Distribute App → TestFlight & App Store** → upload.
- ☐ Wait for processing (~10–30 min), then in App Store Connect → TestFlight:
  - Internal testers (your own ASC users): available immediately for fast smoke
    test.
  - External testers: provide test details + the privacy info, submit for the
    one-time **Beta App Review** (~24h), then share the **public link**.

## 5. Smoke test on a real device before inviting people
- ☐ Sign up with email → confirm "Signed in as …" shows, sign out, sign back in.
- ☐ Create/import a deck → study (Classic + Quiz) → verify a battle + rewards.
- ☐ Airplane mode: confirm studying, battles, streak, and wallet all still work
  and survive a relaunch (offline-first).
- ☐ Create a class, join from a second account, share + copy a deck.
- ☐ Add the home-screen widget; confirm it shows streak/due/quests.
- ☐ Delete account → confirm local data clears and you're signed out.

---

## Beta posture decisions (made)
- **Mito+ is free during the beta** (`BetaConfig.premiumFreeForBeta = true`) —
  every premium feature unlocked so testers see the whole product; the free
  caps are instrumented (logged) but not enforced, so we learn where friction
  would land without walling off feedback.
- **Founding-tester perk** (optional, later): offer beta testers a bounded perk
  at paid launch (founding badge or a few months of Mito+) rather than permanent
  free access.

## Known cuts for v1 (ship without, add later)
- Real OS app-shield (Family Controls) — needs Apple's restricted entitlement.
- RevenueCat / real payments — Mito+ is a flag for now.
- Landscape / split-screen battle mode.
- Two-device verification of co-op/PvP realtime sync.
