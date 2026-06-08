# Smart Glasses Assistance System — Architecture

## Folder structure

```
lib/
├── main.dart                    # App entry, Provider setup, theme mode
├── core/
│   ├── constants/
│   │   └── app_constants.dart   # Prefs keys, resolution labels, app info
│   └── theme/
│       └── app_theme.dart      # Material 3 light/dark themes
├── features/
│   ├── camera/
│   │   ├── camera_screen.dart   # Live view UI (preview, capture, flash)
│   │   └── camera_provider.dart # Camera init, capture, flash, resolution
│   ├── notifications/
│   │   ├── notifications_screen.dart
│   │   ├── notifications_provider.dart
│   │   └── models/
│   │       └── alert_item.dart # Alert type and model
│   ├── settings/
│   │   ├── settings_screen.dart
│   │   └── settings_provider.dart
│   └── shell/
│       └── app_shell.dart      # Bottom nav, IndexedStack of screens
├── widgets/
│   └── alert_card.dart         # Reusable notification card
└── services/
    └── settings_service.dart   # shared_preferences wrapper
```

## Flow

- **main.dart**: Initializes `SettingsService`, registers `SettingsProvider`, `NotificationsProvider`, `CameraProvider`, and builds `MaterialApp` with theme from settings and `AppShell` as home.
- **App shell**: Bottom `NavigationBar` with three destinations; body is an `IndexedStack` of Camera, Notifications, Settings so tab state is kept.
- **Camera**: Uses device camera via `camera` package; resolution from `SettingsService`. Later you can replace the preview with an ESP32 stream (e.g. `Image.network` or a video player).
- **Notifications**: Dummy list of `AlertItem`; UI ready for real-time alerts (e.g. Firebase or WebSocket).
- **Settings**: Dark/light theme, notifications on/off, camera resolution dropdown, About. All persisted via `SettingsService`.

## Extending later

- **ESP32 stream**: In `CameraProvider`, swap `CameraController` for a stream URL and in `CameraScreen` show a video/image stream instead of `CameraPreview`.
- **Firebase**: Add a service under `services/` and inject it; use it in `NotificationsProvider` to push new alerts.
- **AI detection**: Call your API from a service and feed results into `NotificationsProvider.addAlert()`.
