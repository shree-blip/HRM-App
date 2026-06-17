# Free iOS Testing on Your Own iPhone (no $99 Apple account)

Put Focus HRM on YOUR OWN iPhone for free, from Windows. The app runs for
7 days per install (just re-run Sideloadly to renew) and works only on your
own device. To distribute to OTHER testers over-the-air (like the Android
Firebase link) you need the $99/yr Apple Developer Program — that is the ONLY
thing the $99 unlocks. Building and self-installing are free.

## What costs nothing
- Building the IPA on Codemagic's cloud Mac (free, 500 build min/month)
- Installing it on your own iPhone via Sideloadly + a free Apple ID

---

## Step 1 — Install the Apple device driver (Windows)
Sideloadly can only talk to your iPhone if Apple's Mobile Device driver is
present. Install iTunes:
- Download from https://www.apple.com/itunes/  (or the Microsoft Store).
- Install, reboot if asked.
- Plug in the iPhone, unlock it, tap "Trust This Computer", enter passcode.

## Step 2 — Set Supabase keys in Codemagic (so login works)
The build needs the real keys baked in, or the UI loads but login fails.
In the Codemagic dashboard:
- Create an environment-variable group named exactly  supabase
- Add these two variables to it:
  - SUPABASE_URL       = https://xjjrqafwxqkehlxudmoj.supabase.co
  - SUPABASE_ANON_KEY  = <the eyJhbGci... anon key from the web app .env>
- The anon key is PUBLIC (protected by Row-Level Security) — safe to ship.

The iOS workflow already references this group (`groups: - supabase`), so the
group MUST exist or Codemagic will reject the YAML.

## Step 3 — Build the unsigned IPA
- Codemagic -> run the workflow named  iOS (IPA)
- When green, open the build and download the artifact:  FocusHRM-unsigned.ipa

## Step 4 — Sideload onto the iPhone
- Download Sideloadly from https://sideloadly.io  and install it.
- Keep the iPhone connected and unlocked.
- Open Sideloadly; it should detect your iPhone in the device dropdown.
- Drag  FocusHRM-unsigned.ipa  into the IPA box.
- Enter your free Apple ID (use an app-specific password if 2FA prompts).
- Click Start. Enter the 2FA code that appears on your iPhone if asked.

## Step 5 — Trust the app on the iPhone
- On the iPhone: Settings -> General -> VPN & Device Management
- Tap your Apple ID profile -> Trust
- Open Focus HRM. Done.

---

## Limits of the free path
- App expires after 7 days -> re-run Sideloadly (Step 4) to renew.
- Free Apple ID: max 3 sideloaded apps, your device only.
- Cannot send to other testers OTA (that needs the $99 account).

## When you get the $99 Apple Developer account
- Switch the iOS workflow to signed builds (App Store Connect API key in a
  Codemagic `ios_signing` group; replace the unsigned-IPA step with
  `xcode-project use-profiles` + `flutter build ipa --release`).
- Then distribute via TestFlight or Firebase App Distribution (iOS) exactly
  like the Android tester flow.
