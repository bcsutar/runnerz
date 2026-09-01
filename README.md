# Runnerz

Runnerz is a focused watchOS running app for Bluetooth FTMS treadmills. It provides a simple workout experience on Apple Watch and saves standard running workouts to Apple Health.

## Features

- Scan for and connect to Bluetooth FTMS treadmills.
- Choose between `Run` and `Walking` workout modes.
- Start, pause, resume, and finish indoor workouts with a cancellable countdown.
- Display live speed, elapsed time, distance, and heart rate.
- Automatically start, pause, and resume workouts based on treadmill movement, with haptic feedback.
- Parse treadmill incline when an FTMS treadmill reports it and calculate cumulative ascent and descent as workout metadata.
- Review time, distance, average pace, calories, average heart rate, and maximum heart rate before saving.
- Save completed workouts as standard `Running` or `Walking` workouts in Apple Health.
- Confirm destructive and HealthKit actions using native watchOS controls.
- Use a simulator-only treadmill to test workout flow and automatic behavior without Bluetooth hardware.
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

The target includes HealthKit and workout-processing configuration. On launch, Runnerz requests HealthKit and Bluetooth access. On a real watch, grant workout write and heart-rate read access when prompted, then connect an FTMS treadmill from the Treadmills screen. If access was previously denied, update it in the Health privacy settings on the paired iPhone. Simulator builds connect to a fake treadmill automatically.

## Simulator Testing

The watchOS simulator includes a simulator-only treadmill. Open the Treadmills screen to use the Walk, Run, and Stop treadmill controls, then test sport selection, countdown cancellation, automatic start, automatic pause, automatic continue, and the review flow. The simulator does not discover physical treadmills, provide real heart-rate data, or simulate incline changes. Use a paired Apple Watch and a real FTMS treadmill to test Bluetooth scanning, control commands, connection loss, HealthKit data, and reported incline.

## HealthKit Data

Runnerz creates indoor workouts with the selected `.running` or `.walking` activity type. It uses HealthKit's live workout session and builder, records heart-rate data supplied by Apple Watch, and uses Apple Health's active-energy statistics for calories. It parses FTMS incline when available and integrates each reported incline against distance to store cumulative `HKMetadataKeyElevationAscended` and `HKMetadataKeyElevationDescended` values. Treadmills without incline data do not produce elevation metadata. Completed workouts are saved to Apple Health only after explicit confirmation. Apple Fitness may not display elevation metadata for every indoor third-party workout even when it is stored in HealthKit.

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
  -target Runnerz \
  -configuration Debug \
  -sdk watchsimulator26.5 \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Contributing

Bug reports, feature requests, documentation improvements, and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change.

## License

Runnerz is available under the [MIT License](LICENSE).
