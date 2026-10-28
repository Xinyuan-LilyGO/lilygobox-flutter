<h1 align="center">LilygoBox</h1>

## **English | [中文](./README_CN.md)**

[![Flutter](https://img.shields.io/badge/Flutter-3.35.6%2B-02569B?style=flat-square&logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.9.2%2B-0175C2?style=flat-square&logo=dart)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square)](./LICENSE)

**LilygoBox** is a Flutter-based device control application for LILYGO hardware. The project is organized with an app shell, shared core modules, and feature-first business modules, so device pages, settings pages, localization, theme, and desktop window behavior can evolve independently.

The current application focus is the Windows desktop experience. Other platform folders may exist because they are part of the Flutter project scaffold, but they are not supported targets at this stage.

## Table of Contents

- [Features](#features)
- [Supported Platforms and Devices](#supported-platforms-and-devices)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Development Notes](#development-notes)

## Features

### Desktop Application Shell

The app shell contains the desktop frame, title bar, resize overlay, page stack, and left-side navigation. Page navigation is separated from desktop window state, keeping application UI routing independent from window maximize, focus, minimize, and close behavior.

On Windows, closing the window (including Alt+F4) keeps LilygoBox running in the system tray. Click its tray icon to restore the current page, or right-click for **Show window** and **Exit**. Exit saves pending settings before terminating; if saving fails, the window reopens with the existing retry notice. If the tray is unavailable, closing minimizes the window instead. The tray icon may appear under Windows' hidden-icons arrow.

### Device-Oriented Architecture

LAN devices use the shared device page by default. A dedicated device page is added only when a model requires distinct UI or behavior.

### Shared Core Modules

Common services and reusable UI building blocks are placed under `lib/core`, including theme, localization helpers, window state, context menus, and shared split-view widgets.

### Localization

Translation source files are stored as ARB files under `lib/l10n`. Generated localization Dart files are stored under `lib/generated/l10n` and excluded from analyzer rules.

## Supported Platforms and Devices

### Supported Platforms

| Platform | Status | Notes |
| --- | --- | --- |
| Windows | Supported | Current primary development and build target |
| Linux | Not supported yet | Platform folder may exist, but release build and runtime behavior are not verified |
| macOS | Not supported yet | Platform folder may exist, but release build and runtime behavior are not verified |
| Android | Not supported | Retained from the Flutter project scaffold |
| iOS | Not supported | Retained from the Flutter project scaffold |
| Web | Not supported | Retained from the Flutter project scaffold |

### Supported Devices

| Device | Hardware Version |
| --- | --- |
| T-Display-P4 Air | V1 |
| T-Display-P4 | V1 |
| T-Display-P4 | V2 |

## Requirements

| Tool | Version | Notes |
| --- | --- | --- |
| Flutter | 3.35.6 or later | Defined in `pubspec.yaml` |
| Dart | 3.9.2 or later | Defined in `pubspec.yaml` |
| Windows desktop toolchain | Platform dependent | Required for Windows desktop builds |

## Quick Start

Install dependencies:

```bash
flutter pub get
```

Generate localization files if ARB files have changed:

```bash
flutter gen-l10n
```

Run the desktop application:

```bash
flutter run -d windows
```

Build a Windows release package:

```bash
flutter build windows
```

## Project Structure

```text
lib/
  app/                         # App-level shell, bootstrap, provider wiring, and navigation.
    bootstrap/                 # Desktop startup code, such as window initialization.
    navigation/                # App UI page routing state.
    shell/                     # Main app shell, sidebar, and shell-level state.
      pages/                   # App shell pages and home content.
      state/                   # App shell selection state.
      widgets/                 # App shell widgets, such as sidebar buttons.
    widgets/                   # Window frame, title bar, page stack, and resize overlay.

  core/                        # Cross-feature reusable modules.
    app_info/                  # Application/package information provider.
    context_menu/              # Shared right-click menu utilities.
    l10n/                      # Localization helper/provider code.
    layout/                    # Shared layout state, such as split-view width.
    theme/                     # Theme definitions and theme provider.
    widgets/                   # Shared UI primitives.
    window/                    # Desktop window state and operations.

  features/                    # Feature-first business modules.
    devices/                   # Device management and device pages.
      domain/                  # Supported device names and domain-level catalogs.
      presentation/            # Device feature pages, widgets, and presentation mapping.
      state/                   # Device feature state.
    settings/                  # Settings pages and settings-specific widgets.

  generated/                   # Generated source files.
    l10n/                      # Flutter gen-l10n output files.

  l10n/                        # Editable ARB translation source files.
  main.dart                    # Flutter entry point.
```

Root configuration files:

| File | Purpose |
| --- | --- |
| `pubspec.yaml` | Flutter package metadata, SDK constraints, and dependencies |
| `analysis_options.yaml` | Flutter lint rules and analyzer exclusions |
| `l10n.yaml` | Flutter localization generation configuration |
| `package_rename_config.yaml` | App/package rename configuration |
| `pubspec.lock` | Locked dependency versions |

## Development Notes

- Keep application-level shell code under `lib/app`.
- Keep reusable cross-feature code under `lib/core`.
- Keep business features under `lib/features/<feature>`.
- Keep editable translation files under `lib/l10n`.
- Do not manually edit generated files under `lib/generated/l10n`; update ARB files and run `flutter gen-l10n` instead.
- Prefer relative imports for files inside this package.
