# Release Signing & Tester Distribution — Focus HRM (Android)

Local, one-time setup so the app can be **release-signed** and shipped to testers
via **Firebase App Distribution**. None of these steps commit secrets.

> 🔒 **Never commit:** `D:/keys/upload-keystore.jks`, `android/key.properties`, `.env`.
> All three are already gitignored. Keep a private backup of the keystore — if you
> lose it you cannot publish updates to the Play Store later.

---

## 1. Create the keys folder (outside the repo)

```powershell
New-Item -ItemType Directory -Force D:/keys
```

## 2. Generate the upload keystore (you choose the password — typed locally)

Run in **your own** PowerShell terminal. The password is typed locally and never
stored in chat or in git:

```powershell
$sec  = Read-Host "Enter NEW keystore password" -AsSecureString
$sec2 = Read-Host "Confirm keystore password"   -AsSecureString
$p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2))
if ($p1 -ne $p2)      { Write-Error "Passwords do not match"; return }
if ($p1.Length -lt 6) { Write-Error "keytool needs at least 6 characters"; return }

keytool -genkeypair -v -keystore D:/keys/upload-keystore.jks -alias upload `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -storepass $p1 -keypass $p1 `
  -dname "CN=Focus HRM, OU=IT, O=Focus Your Finance, L=Kathmandu, ST=Bagmati, C=NP"

$p1=$null; $p2=$null; $sec=$null; $sec2=$null
```

> If `keytool` is not found, it ships with the JDK, e.g. Android Studio's:
> `& "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe" ...`

## 3. Create `android/key.properties` from the template

```powershell
Copy-Item android/key.properties.example android/key.properties
```

Then open `android/key.properties` and replace the placeholders with your real values:

- `YOUR_KEYSTORE_PASSWORD` → your private keystore (store) password
- `YOUR_KEY_PASSWORD`       → your private key password (same as above if you used one password)
- `keyAlias`                → `upload` (matches the alias above)
- `storeFile`              → `D:/keys/upload-keystore.jks`

`android/key.properties` is **gitignored** — never commit it.
`android/app/build.gradle.kts` automatically picks it up and release-signs the build.

## 4. Build the release APKs

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
(arm64-v8a is the right APK for virtually all modern Android phones.)

## 5. Upload the arm64 APK to Firebase App Distribution

```powershell
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-arm64-v8a-release.apk `
  --app 1:752791060886:android:69d1655461f4918fdc5db7 `
  --groups testers `
  --release-notes "Focus HRM tester release"
```

If the `testers` group does not exist yet, create it and add testers first:

```powershell
firebase appdistribution:group:create testers "Testers" --project hrm-app-58f9b
firebase appdistribution:testers:add tester1@example.com tester2@example.com --project hrm-app-58f9b
firebase appdistribution:group:add testers tester1@example.com tester2@example.com --project hrm-app-58f9b
```

Testers receive an email invite → accept → install via the **Firebase App Tester**
app (or the link) → future updates appear in App Tester after each new upload.

---

## Update reminder

- **GitHub push alone does NOT update anyone's phone.**
- App Distribution updates: code change → `flutter build apk --release` → `firebase appdistribution:distribute ...` → tester installs the new build.
- Play Store updates (later): code change → `flutter build appbundle --release` → upload AAB to Play Console → submit for review.
