# RunTracker

Premium GPS running tracker with a dark, modern interface and lime accents.

Repository: https://github.com/DRAVEINX/RunTracker

## Included in this first Android MVP

- Start, pause, resume and finish a run.
- GPS route drawn on an OpenStreetMap map.
- Elapsed time, distance, average pace, estimated speed and GPS point count.
- GPS accuracy filter and rejection of implausible position jumps.
- Local training history saved on the device.
- GitHub Actions workflow to analyze, test, and build an Android APK and AAB.
- Dutch interface labels and a responsive layout.

## Build

The GitHub Actions workflow generates the standard Flutter Android platform scaffold in its build environment, then runs:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

Open **Actions** in GitHub to inspect the live build and download the APK/AAB artifacts after a successful run.

## Wear OS status

A watch companion is **not implemented yet**. See [wear-os/README.md](wear-os/README.md) for the planned native Wear OS module, watch workout controls, and Health Services/Data Layer integration. Do not treat watch integration as available until a separate watch build and physical-device tests pass.

## Important notes before public release

- This is an initial MVP, not yet a production-validated sports tracker.
- Test GPS accuracy, app backgrounding, battery use, Android permission flows, pause/resume, and device-specific behavior on real phones.
- Location permission must be granted and location services enabled.
- The current history is local to the app installation; uninstalling the app can remove it.
- OpenStreetMap tiles require internet access and attribution. Review tile usage policy before a large public rollout.
- A Play Store release needs final app identity, privacy disclosures, signing configuration, target SDK verification, and end-to-end device testing.
