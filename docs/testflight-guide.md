# Mito — App Store Connect + TestFlight, step by step

Goal: get a **public TestFlight link** you can text to testers. ~2–3 days
(most of which is Apple's one-time Beta App Review for external testers).

Everything below is done in a web browser + Xcode — no code changes left.

---

## Step 1 — Create the app record in App Store Connect

1. Go to **https://appstoreconnect.apple.com** → sign in with your developer
   Apple ID.
2. **My Apps → ➕ → New App.**
3. Fill in:
   - **Platforms:** iOS
   - **Name:** Mito  (must be globally unique on the App Store; if "Mito" is
     taken, use "Mito: Study RPG" or similar — the home-screen name stays "Mito")
   - **Primary language:** English (U.S.)
   - **Bundle ID:** select `com.yukinabe.mitov3` (it should appear in the
     dropdown because your Team is set; if not, register it first at
     developer.apple.com → Identifiers).
   - **SKU:** any internal string, e.g. `mito-ios-001`
   - **User Access:** Full Access
4. **Create.**

## Step 2 — App Privacy (required before external TestFlight)

App Store Connect → your app → **App Privacy → Get Started.** Answer to match
`MitoV3/PrivacyInfo.xcprivacy`:

- **Do you collect data?** Yes.
- Add these data types, each: **linked to the user = Yes**, **used for tracking
  = No**, purpose **App Functionality** (add **Analytics** too for the usage one):
  - **Email Address** — App Functionality
  - **User ID** — App Functionality
  - **Other User Content** (the decks/cards users create) — App Functionality
  - **Product Interaction** (usage events) — App Functionality + Analytics
- **Tracking:** No, the app does not track.
- Publish.

## Step 3 — Host the privacy policy + add the URL

1. Put `docs/privacy-policy.md` somewhere public (a Notion page set to "share to
   web", a GitHub Pages site, or any simple host). Fill in the `[DATE]` and
   `[YOUR CONTACT EMAIL]` placeholders first.
2. App Store Connect → app → **App Information → Privacy Policy URL** → paste it.

## Step 4 — Set the build number, then Archive in Xcode

> Each upload needs a **unique, higher build number** (`CURRENT_PROJECT_VERSION`).
> It's `1` now — fine for the first upload. **Bump it (2, 3, …) before every
> later upload** or App Store Connect rejects the duplicate. (Marketing version
> `1.0` can stay until you do a public release.)

1. In Xcode, top bar device selector → **Any iOS Device (arm64)** (not a
   simulator — archives require a device target).
2. **Product → Archive.** Wait for it to build + appear in the Organizer.
   - If signing complains: target → **Signing & Capabilities** → "Automatically
     manage signing" on, Team = yours, for **both** MitoV3 and MitoWidget.
   - Confirm the **App Groups** capability shows `group.com.yukinabe.mitov3` on
     both targets (needed for the widget). Xcode registers it automatically.
3. In the Organizer: select the archive → **Distribute App → TestFlight & App
   Store → Distribute.** It uploads to App Store Connect.

> Disk note: archives are large. Keep ~10 GB free or the export fails (you hit
> this with builds before).

## Step 5 — Wait for processing, then test internally (instant)

1. App Store Connect → app → **TestFlight** tab. The build shows "Processing"
   (~10–30 min), then "Ready to Test."
2. If it asks **Export Compliance**: the app already declares
   `ITSAppUsesNonExemptEncryption = NO`, so it should skip the questionnaire. If
   asked, answer **No** (standard HTTPS only is exempt).
3. **Internal Testing:** add yourself / teammates (must be Users in your App
   Store Connect account). They get the build immediately via the **TestFlight
   app** on their iPhone. Do a real-device smoke test here first.

## Step 6 — External testers (the public link)

1. TestFlight → **External Testing → ➕** a group (e.g. "Beta").
2. Add the build to the group. Fill in **Test Information**:
   - **What to test:** e.g. "Study loop, battles, classes, focus sessions."
   - **Feedback email**, **marketing URL** (optional), **privacy policy URL**.
3. Submit for **Beta App Review** (one-time, ~24h, much lighter than full App
   Store review).
4. Once approved, enable the **Public Link** for the group → you get a
   `testflight.apple.com/join/XXXX` URL. **Share that** — anyone who taps it
   installs via the TestFlight app. Up to 10,000 external testers.

## Step 7 — Iterate

Push a new build anytime: bump the build number, Archive, Distribute. Internal
testers get it instantly; external testers get it after a quick re-review (often
auto-approved for builds with no new feedback-relevant changes).

---

## Before you invite real people — on-device smoke test
See the smoke-test list in `docs/launch-checklist.md` (sign in, study Classic +
Quiz, battle, airplane-mode offline check, classes with 2 accounts, widget,
delete account).

## Reminders
- **Bump the build number every upload.**
- **Keep ~10 GB free** for archives.
- Mito+ is **free for all testers** (`BetaConfig.premiumFreeForBeta = true`); the
  caps are logged (`cap_would_block` events) but not enforced — watch those in
  your analytics to see where the free tier would bite.
