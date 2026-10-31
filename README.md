# Leo Desk

**Leo Desk** is an open-source business management application built with Flutter for embroidery and Aari businesses. It brings day-to-day operations such as customer and order management, billing, costing, and staff payroll into one desktop/mobile application.

[![Flutter CI](https://github.com/Ravenvd/Leo-Desk/actions/workflows/flutter-ci.yml/badge.svg?branch=main)](https://github.com/Ravenvd/Leo-Desk/actions/workflows/flutter-ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Customer management** — maintain customer records.
- **Order management** — track embroidery and Aari work orders.
- **Billing** — create and manage bills associated with orders.
- **Cost calculator** — estimate embroidery and Aari costs, including machine-time pricing, quantity discounts, and operating-cost inputs.
- **Staff management** — maintain staff profiles and active/inactive status.
- **Attendance and overtime** — record full-day, half-day, absent, and leave attendance, with optional check-in/check-out times and overtime calculations.
- **Payroll** — review monthly earnings, payments, and outstanding balances. Staff payments are linked to salary expenses.
- **Business expenses and reporting** — record expenses and review business figures.
- **LAN synchronisation** — synchronise supported business data between Android and Windows devices on the same local network.

Feature availability and behaviour may vary by release. See [CHANGELOG.md](CHANGELOG.md) for version-specific changes.

## Supported platforms

- Android
- Windows

The repository also contains Flutter platform scaffolding for other targets, but Android and Windows are the supported distribution targets for this project at present.

## Getting started

### Requirements

- Flutter SDK (stable channel)
- Dart SDK version compatible with the constraint in `pubspec.yaml`
- Android Studio / Android SDK for Android builds
- Visual Studio with the **Desktop development with C++** workload for Windows desktop builds

### Get the source

```bash
git clone https://github.com/Ravenvd/Leo-Desk.git
cd Leo-Desk
flutter pub get
```

### Run the application

List the devices Flutter can use:

```bash
flutter devices
```

Run on a connected device or desktop target:

```bash
flutter run -d <device-id>
```

### Build Android

```bash
flutter build apk --release
```

The APK is generated under `build/app/outputs/flutter-apk/`.

### Build Windows

Run this command on Windows with the required Visual Studio C++ workload installed:

```powershell
flutter build windows --release
```

The application bundle is generated under `build/windows/x64/runner/Release/`. Distribute the complete Release folder (normally packaged as a ZIP), not just the executable.

## Quality checks

Run the analyzer and test suite before submitting changes:

```bash
flutter analyze
flutter test
```

GitHub Actions runs these checks automatically for pushes to `main` and pull requests targeting `main`.

## Contributing

Contributions are welcome.

1. Fork the repository.
2. Create a focused branch for your change.
3. Add or update tests where appropriate.
4. Run `flutter analyze` and `flutter test`.
5. Open a pull request describing the change and its impact.

Please avoid including real customer information, business records, database files, credentials, signing keys, or other private data in issues and pull requests.

## Releases

Download published Android and Windows builds from the [GitHub Releases](https://github.com/Ravenvd/Leo-Desk/releases) page. Check the release notes for changes and any upgrade considerations before installing.

## License

Leo Desk is distributed under the [MIT License](LICENSE).

The MIT License applies to the software in this repository. Product names, logos, and other trademarks are not granted for reuse by that software licence.
