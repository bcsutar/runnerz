# Contributing to Runnerz

Thanks for helping improve Runnerz.

## Before You Start

- Check existing issues and pull requests before starting duplicate work.
- Open an issue for a substantial feature or behavior change first.
- Do not include private data, signing credentials, provisioning files, or local machine paths.
- Keep changes focused and explain the user-visible behavior they affect.

## Development Setup

1. Install Xcode 26 or later.
2. Open `Runnerz/Runnerz.xcodeproj`.
3. Select a watchOS simulator or paired Apple Watch.
4. Choose your own development team in Xcode for local signing.

## Pull Requests

- Use a clear title describing the change.
- Include testing steps and note whether a physical treadmill or Apple Watch was used.
- Update documentation when behavior or setup changes.
- Keep generated files and Xcode user data out of commits.

## Testing

Run the command in the README before opening a pull request. Bluetooth FTMS behavior and HealthKit permissions should also be tested on physical hardware when the change touches those systems.
