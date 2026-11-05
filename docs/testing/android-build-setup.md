# Completing the Android build setup

This repository now includes minimal Gradle Kotlin DSL files and Android theme
resources. The files are a **build scaffold**, not a tested build. Android Gradle
Plugin/Kotlin versions can need adjustment to match the installed Flutter SDK.

## Recommended first run on Windows

1. Install Flutter SDK and Android Studio; install Android SDK Platform Tools and
   an Android SDK platform from Android Studio's SDK Manager.
2. Add Flutter's `bin` folder to PATH, open a new PowerShell, and run:
   ```powershell
   flutter doctor -v
   cd path\to\inlink-foundation\app
   flutter pub get
   ```
3. If `app/android/local.properties` is still missing, let Flutter generate it
   using `flutter pub get`, or open the Android project in Android Studio and
   configure the Flutter SDK path. Do not commit `local.properties`.
4. Run:
   ```powershell
   flutter analyze
   flutter test
   flutter build apk --debug
   ```
5. If Gradle reports a plugin/Java compatibility error, use the version guidance
   from the installed Flutter SDK's generated Android template rather than
   blindly upgrading packages. Android builds generally require JDK 17 for the
   configured toolchain.
6. Connect an Android phone with USB debugging enabled and run:
   ```powershell
   flutter devices
   flutter run -d <device-id>
   ```

## If the generated platform files are needed

Prefer Flutter's own template for your installed SDK. Back up `android/` first,
then use a separate temporary Flutter project:
```powershell
flutter create --platforms=android --org com.example C:\temp\inlink_android_template
```
Compare its Gradle files and resources with this repository and merge differences.
Do not blindly copy over `MainActivity.kt`, the BLE manifest permissions, or
existing app Dart files.

## What success means

A successful APK build only proves compilation. M1 is not complete until two
physical Android phones can discover one another and exchange synthetic frames
in both directions, with connection/disconnection and retry behavior recorded.
Do not use this prototype for sensitive communication.
