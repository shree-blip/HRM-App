# Codemagic CI/CD — Focus HRM (Android + iOS from one repo)

This repo builds **both** platforms with [Codemagic](https://codemagic.io).
`codemagic.yaml` (at the repo root) defines two workflows. **No secrets live in
the repo** — every key/password is stored in the Codemagic dashboard and
referenced by name.

## Key facts

- **Same GitHub repo for Android and iOS.** Do *not* create a separate iOS repo;
  the Flutter project already contains the `ios/` folder.
- **iOS cannot be built on Windows.** Building an `.ipa` requires macOS + Xcode.
  Codemagic provides a **cloud Mac**, so you don't need to own a Mac.
- **An Apple Developer account ($99/yr) is still required** to sign and distribute
  iOS builds (TestFlight / App Store / Firebase App Distribution for iOS).
- **All secrets go in the Codemagic dashboard**, never in this repo:
  keystore, keystore passwords, Apple certificates, App Store Connect API key,
  Firebase token. They are injected as environment variables at build time.
- Firebase App Distribution upload can be **added later** (commented templates
  are already in `codemagic.yaml`).

## Workflows

### `android-workflow` (Linux instance)
`flutter clean` -> `pub get` -> `analyze` -> `test` -> optional release signing
(only if keystore vars exist, otherwise debug-signed) -> build **split APKs** and
an **AAB**. Artifacts: APKs, AAB, mapping.txt. An optional, commented Firebase
App Distribution step is included.

### `ios-workflow` (macOS instance)
`flutter clean` -> `pub get` -> `cd ios && pod install` -> `analyze` -> `test` ->
build. The **safe default** is `flutter build ios --release --no-codesign`, which
compiles the app **without** Apple credentials so you can confirm the build is
green immediately. Once you add Apple signing in the dashboard, switch to the
(commented) `xcode-project use-profiles` + `flutter build ipa --release` to
produce a real signed `.ipa`.

## Secrets to add in the Codemagic dashboard (NOT in the repo)

Create these as **Environment variable groups** and reference them in the YAML
(already wired by name):

### Group `android_keystore` (for a release-signed Android build)
| Variable | What it is |
|---|---|
| `CM_KEYSTORE` | base64 of `upload-keystore.jks` (`base64 -w0 upload-keystore.jks`) |
| `CM_KEYSTORE_PASSWORD` | store password |
| `CM_KEY_ALIAS` | `upload` |
| `CM_KEY_PASSWORD` | key password |

> Optional for distribution — group `firebase`: `FIREBASE_TOKEN`
> (`firebase login:ci`), `FIREBASE_APP_ID_ANDROID`
> (`1:752791060886:android:69d1655461f4918fdc5db7`).

### Group `ios_signing` (for a signed IPA)
Recommended: **App Store Connect API key** based automatic signing.
| Variable | What it is |
|---|---|
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | contents of the `.p8` API key |
| `CERTIFICATE_PRIVATE_KEY` | distribution certificate private key |
| `BUNDLE_ID` | e.g. `com.focusyourfinance.hrmFocusFlutter` |

> Codemagic's UI can also manage iOS signing automatically via its
> App Store Connect integration — that's the easiest path.

## Manual steps for you

1. Push `codemagic.yaml` + this file to GitHub (after your approval).
2. Sign up at codemagic.io and **connect this GitHub repo**.
3. Add the environment variable groups above (only the platforms you need).
4. **Android:** run `android-workflow` — works immediately (debug-signed if you
   skip the keystore group; add `android_keystore` for a release build).
5. **iOS:**
   - In **Firebase Console** (project `hrm-app-58f9b`) → Add app → **iOS** →
     set the bundle ID; download `GoogleService-Info.plist` **only if** you later
     add a Firebase SDK (not needed for App Distribution).
   - Set the same bundle ID in Xcode (`ios/Runner`).
   - Add the `ios_signing` group (or use Codemagic's App Store Connect
     integration), then switch the iOS build step to the signed `ipa` command.
   - Run `ios-workflow` → download the `.ipa` → upload to **TestFlight** or
     **Firebase App Distribution** (iOS app id).

## Never commit
`android/key.properties`, `upload-keystore.jks`, `.env`, OAuth `client_secret*.json`,
Firebase service-account / admin-SDK JSON, Apple certificates (`.p12`/`.cer`),
provisioning profiles (`.mobileprovision`), the App Store Connect `.p8` key.
All of these belong only in the Codemagic dashboard.
