# Contributing to react-native-media-toolkit

Read this in: [Tiếng Việt](./CONTRIBUTING.vi.md)

---

Thank you for your interest in contributing. All contributions are welcome, whether it's a bug fix, new feature, documentation improvement, or question.

Please read this guide before submitting anything.

---

## Code of Conduct

This project follows a standard code of conduct. Please be respectful and constructive in all interactions.  
See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for details.

---

## Project Structure

This repository is a **Yarn monorepo** with two packages:

- Root directory: the library (`react-native-media-toolkit`)
- `example/`: the demo app (Expo Dev Client)

```
react-native-media-toolkit/        Library source
├── src/                           TypeScript API and Nitro spec
├── ios/                           Swift native implementation
├── android/                       Kotlin native implementation
├── nitrogen/                      Generated Nitro bridge files (do not edit manually)
└── example/                       Demo app for testing changes
```

---

## Prerequisites

- Node.js: see `.nvmrc` for the exact version
- Yarn 4+: `corepack enable && corepack prepare yarn@stable --activate`
- iOS development: Xcode 16.1+, CocoaPods
- Android development: Android Studio, JDK 17+

---

## Setup

**1. Clone the repo**

```sh
git clone https://github.com/thangdevalone/react-native-media-toolkit.git
cd react-native-media-toolkit
```

**2. Install dependencies**

```sh
yarn
```

This installs dependencies for both the library and the example app.

**3. Install iOS pods**

```sh
cd example/ios && pod install && cd ../..
```

---

## Running the Example App

The example app uses **Expo Dev Client**, so you need to build it natively first.

**Start Metro**

```sh
yarn example start
```

**Run on iOS**

```sh
yarn example ios
```

**Run on Android**

```sh
yarn example android
```

To verify New Architecture is active, check the Metro logs for:

```
Running "MediaToolkitExample" with {"fabric":true,"initialProps":{"concurrentRoot":true},"rootTag":1}
```

---

## Editing Native Code

**iOS (Swift):**  
Open `example/ios/MediaToolkitExample.xcworkspace` in Xcode.  
Library source files: `Pods > Development Pods > react-native-media-toolkit`.

**Android (Kotlin):**  
Open `example/android` in Android Studio.  
Library source files appear under `react-native-media-toolkit` in the project tree.

After modifying native code, you must rebuild the app — a Metro reload is not enough.

---

## Running Codegen

If you change the Nitro spec file (`src/MediaToolkit.nitro.ts`), regenerate the bridge files:

```sh
yarn codegen
```

This runs `nitrogen --config nitro.json` and updates the `nitrogen/` directory.  
After regeneration, rebuild the native app to apply the changes.

---

## Code Quality

**TypeScript check**

```sh
yarn typecheck
```

**Lint**

```sh
yarn lint
```

**Auto-fix lint errors**

```sh
yarn lint --fix
```

All checks must pass before submitting a pull request.

---

## Scripts Reference

| Script | Description |
|---|---|
| `yarn` | Install all dependencies |
| `yarn typecheck` | Type-check with TypeScript |
| `yarn lint` | Lint with ESLint |
| `yarn lint --fix` | Auto-fix lint errors |
| `yarn codegen` | Regenerate Nitro bridge files |
| `yarn example start` | Start Metro server |
| `yarn example ios` | Run example on iOS |
| `yarn example android` | Run example on Android |
| `yarn example build:ios` | Build iOS binary |
| `yarn example build:android` | Build Android APK |

---

## Submitting a Pull Request

Before opening a pull request:

1. Open an issue first if the change is significant (new feature, breaking change, or API change).
2. Keep pull requests small and focused on a single concern.
3. Make sure `yarn typecheck` and `yarn lint` both pass.
4. Test your changes on both iOS and Android using the example app.
5. Update `README.md` if you change or add any public API.

**PR title format:**

```
fix: correct crop coordinates for letterboxed video
feat: add getThumbnail API
docs: update installation guide
```

---

## Reporting Bugs

When reporting a bug, please include:

- Library version (`react-native-media-toolkit@x.x.x`)
- React Native version
- Platform (iOS version / Android API level)
- A minimal code snippet to reproduce the issue
- The full error message or stack trace

Submit bugs at: [https://github.com/thangdevalone/react-native-media-toolkit/issues](https://github.com/thangdevalone/react-native-media-toolkit/issues)

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).
