# Building and signing Linewise

## Toolchain

* Flutter 3.24.5 (pinned in CI) with Dart 3.5
* Java 17 (Temurin)
* Android SDK 34 (build-tools with `zipalign`, `apksigner`, `aapt`)

Local builds:

```bash
flutter pub get
dart format .
flutter analyze
flutter test
bash tool/prepare_gradle_wrapper.sh   # once, pulls gradle wrapper binaries
flutter build apk --release
```

## Release signing

`android/key.properties` and keystore files are **gitignored** — never commit
them (CI enforces this with `tool/secret_scan.sh`).

### Persistent signing (recommended)

Generate a keystore once, on your own machine:

```bash
keytool -genkeypair -v -keystore linewise-release.p12 -storetype PKCS12 \
  -alias linewise -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "<strong password>" -keypass "<strong password>" \
  -dname "CN=Linewise Release, O=Linewise, C=US"
base64 -w0 linewise-release.p12   # → ANDROID_KEYSTORE_BASE64
```

Then add four repository Actions secrets (Settings → Secrets and variables →
Actions). GitHub encrypts them at rest:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | output of the `base64` command above |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `linewise` |
| `ANDROID_KEY_PASSWORD` | key password |

With secrets configured, every release is signed by the **same** key, so users
can update over previous installs normally.

### Fallback

Without secrets, CI generates an **ephemeral** keystore for that build. The APK
is fully signed and verifiable, but a later build will use a different key
(Android then requires uninstall/reinstall to update). The build report records
which mode was used (`signingMode` in `dist/build-info.json`).

## Verification (every CI build)

`tool/verify_apk.sh` fails the build unless all of these pass:

* package `app.linewise.linewise`
* `versionName`/`versionCode` from `pubspec.yaml` (currently 1.11.0 / 12)
* `apksigner verify --print-certs` (signer certificate fingerprint recorded)
* `zipalign -c -v 4`
* SHA-256 of the APK (recorded in `dist/SHA256SUMS` and the release notes)

Artifacts are published two ways: committed to `dist/` on the working branch
and attached to the GitHub Release `v<version>`.

## The Odds API key (end users)

The user's own The Odds API key is stored in **encrypted Android storage**
(Android Keystore). `android:allowBackup="false"` keeps it out of backups; it is
never logged, exported, snapshotted or included in source. It survives normal
signed app updates.
