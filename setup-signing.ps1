# Focus HRM - one-time Android release signing setup.
# Safe to run/share: contains NO password (you type it privately at runtime).
#
# Run once in YOUR terminal:
#   cd D:\hrm-focus-flutter
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-signing.ps1
#
# Generates D:/keys/upload-keystore.jks and writes android/key.properties,
# then verifies. Both files are gitignored - never commit them.

# Do not use 'Stop': keytool writes progress to stderr, which can be promoted
# to a terminating error and abort before the keystore is written.
$ErrorActionPreference = "Continue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$projectDir = if ($PSScriptRoot) { $PSScriptRoot } else { "D:/hrm-focus-flutter" }
$keysDir  = "D:/keys"
$keystore = "D:/keys/upload-keystore.jks"
$keyProps = Join-Path $projectDir "android/key.properties"

Write-Host ("Project dir: " + $projectDir) -ForegroundColor Cyan

# Step 1: keys folder
New-Item -ItemType Directory -Force $keysDir | Out-Null
Write-Host ("[1/4] Keys folder ready: " + $keysDir) -ForegroundColor Green

# Step 2: locate keytool (PATH, JAVA_HOME, Android Studio JBR, common JDK dirs)
function Find-Keytool {
  $c = (Get-Command keytool -ErrorAction SilentlyContinue).Source
  if ($c) { return $c }
  if ($env:JAVA_HOME) {
    $j = Join-Path $env:JAVA_HOME "bin/keytool.exe"
    if (Test-Path $j) { return $j }
  }
  $fixed = @(
    (Join-Path $env:LOCALAPPDATA "Programs/Android Studio/jbr/bin/keytool.exe"),
    "C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe"
  )
  foreach ($f in $fixed) { if (Test-Path $f) { return $f } }
  $globs = @(
    "C:/Program Files/Microsoft/jdk-*/bin/keytool.exe",
    "C:/Program Files/Eclipse Adoptium/jdk-*/bin/keytool.exe",
    "C:/Program Files/Java/jdk*/bin/keytool.exe",
    "C:/Program Files/Android/Android Studio*/jbr/bin/keytool.exe"
  )
  foreach ($g in $globs) {
    $hit = Get-ChildItem -Path $g -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

$keytool = Find-Keytool
if (-not $keytool) {
  Write-Host "ERROR: keytool not found. Install a JDK or set JAVA_HOME, then re-run." -ForegroundColor Red
  exit 1
}
Write-Host ("[2/4] Using keytool: " + $keytool) -ForegroundColor Green

$needKeystore = -not (Test-Path $keystore)
$needKeyProps = -not (Test-Path $keyProps)

if ((-not $needKeystore) -and (-not $needKeyProps)) {
  Write-Host "Both files already exist - nothing to do." -ForegroundColor Yellow
}
else {
  if (-not $needKeystore) {
    Write-Host "Keystore already exists; will rewrite key.properties for it." -ForegroundColor Yellow
  }

  # Step 3: private password entry (typed locally; never shown or stored)
  $sec  = Read-Host "Enter keystore password (min 6 chars)" -AsSecureString
  $sec2 = Read-Host "Confirm keystore password" -AsSecureString
  $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2))
  if ($p1 -ne $p2) {
    Write-Host "ERROR: Passwords do not match." -ForegroundColor Red
    exit 1
  }
  if ($p1.Length -lt 6) {
    Write-Host "ERROR: Password must be at least 6 characters." -ForegroundColor Red
    exit 1
  }

  # Generate the keystore (only if missing)
  if ($needKeystore) {
    Write-Host "[3/4] Generating keystore (this can take a few seconds)..." -ForegroundColor Cyan
    $out = & $keytool -genkeypair -v -keystore $keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000 -storepass $p1 -keypass $p1 -dname "CN=Focus HRM, OU=IT, O=Focus Your Finance, L=Kathmandu, ST=Bagmati, C=NP" 2>&1
    if (($LASTEXITCODE -ne 0) -or (-not (Test-Path $keystore))) {
      Write-Host ("ERROR: keytool failed (exit " + $LASTEXITCODE + "). Output below:") -ForegroundColor Red
      $out | ForEach-Object { Write-Host $_ }
      $p1 = $null; $p2 = $null
      exit 1
    }
    Write-Host ("      Keystore created: " + $keystore) -ForegroundColor Green
  }

  # Write android/key.properties (UTF-8 no BOM so Gradle reads it cleanly)
  New-Item -ItemType Directory -Force (Split-Path $keyProps) | Out-Null
  $content = "storePassword=" + $p1 + "`nkeyPassword=" + $p1 + "`nkeyAlias=upload`nstoreFile=D:/keys/upload-keystore.jks`n"
  [IO.File]::WriteAllText($keyProps, $content, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("[4/4] key.properties written: " + $keyProps) -ForegroundColor Green

  # Wipe plaintext from memory
  $p1 = $null; $p2 = $null; $sec = $null; $sec2 = $null
}

# Verify (no secrets printed)
$okKs = Test-Path $keystore
$okKp = Test-Path $keyProps
Write-Host ""
if ($okKs) { Write-Host ("Keystore       : OK  " + $keystore) -ForegroundColor Green }
else       { Write-Host  "Keystore       : MISSING" -ForegroundColor Red }
if ($okKp) { Write-Host ("key.properties : OK  " + $keyProps) -ForegroundColor Green }
else       { Write-Host  "key.properties : MISSING" -ForegroundColor Red }
Write-Host ""
if ($okKs -and $okKp) {
  Write-Host "Done. Keystore and key.properties are ready."
}
else {
  Write-Host "Setup incomplete - see MISSING above." -ForegroundColor Red
  exit 1
}
