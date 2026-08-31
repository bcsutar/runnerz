# Runnerz

Runnerz is a focused watchOS running app for Bluetooth FTMS treadmills. It provides a simple workout experience on Apple Watch and saves standard running workouts to Apple Health.

## Features

- Scan for and connect to Bluetooth FTMS treadmills.
- Start, pause, resume, and stop indoor running workouts.
- Display live speed, elapsed time, distance, calories, and heart rate.
- Pause automatically and notify you when a connected treadmill drops offline.
- Review time, distance, total calories, and average heart rate before saving.
- Save completed workouts as standard `Running` workouts in Apple Health.
- Confirm destructive and HealthKit actions using native watchOS controls.
- No account, backend, analytics, or network service required.

## Requirements

- Xcode 26 or later.
- watchOS 26 or later.
- An Apple Watch for HealthKit and treadmill testing.
- A Bluetooth FTMS-compatible treadmill for treadmill testing.

## Getting Started

1. Clone the repository.
2. Open `Runnerz/Runnerz.xcodeproj` in Xcode.
3. Select the `Runnerz` scheme and an Apple Watch simulator or paired Apple Watch.
4. Select your local development team under Signing & Capabilities.
5. Build and run.

The target includes HealthKit and workout-processing configuration. On a real watch, grant workout write and heart-rate read access when prompted. If access was previously denied, update it in the Health privacy settings on the paired iPhone.

## Simulator Testing

The watchOS simulator can be used to test the interface, workout flow, HealthKit authorization, and Health app saving. It cannot discover a physical treadmill over Bluetooth. Use a paired Apple Watch and a real FTMS treadmill to test scanning, control commands, and connection-loss behavior.

## HealthKit Data

Runnerz creates indoor workouts with the `.running` activity type. It uses HealthKit's live workout session and builder, writes standard distance and active-energy samples from the treadmill, and records heart-rate data supplied by Apple Watch. Completed workouts are saved to Apple Health only after explicit confirmation.

Runnerz does not upload workout data anywhere. HealthKit permissions are controlled by Apple Watch and Apple Health.

## Project Layout

- `Runnerz/RunnerzApp.swift`: SwiftUI screens, navigation, workout controls, and review UI.
- `Runnerz/WorkoutManager.swift`: HealthKit authorization, live workout lifecycle, metrics, and saving.
- `Runnerz/FTMSTreadmillManager.swift`: Core Bluetooth FTMS discovery, connection, commands, and data parsing.
- `Runnerz/Info.plist`: App metadata, privacy descriptions, icon, and watchOS background modes.
- `Runnerz/Runnerz.entitlements`: HealthKit capability.

## Building from the Command Line

```sh
xcodebuild \
  -project Runnerz/Runnerz.xcodeproj \
  -scheme Runnerz \
  -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Contributing

Bug reports, feature requests, documentation improvements, and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change.

## License

Runnerz is available under the [MIT License](LICENSE).
