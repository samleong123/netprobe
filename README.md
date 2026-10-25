# NetProbe: Advanced Network & Speed Toolkit

> Precision network testing. No bloat, no tracking, and complete throughput control.

NetProbe is a lightweight, open-source utility designed to benchmark your Internet speed and inspect your mobile or Wi-Fi environment with clinical accuracy. Powered by a native, concurrent HTTP engine and integrated as an Android foreground service, NetProbe continues measuring background throughput safely even when you minimize the app—ensuring interruption-free testing under heavy loads.

Designed for Android 8.0+ using Material 3, NetProbe is completely self-contained, requiring zero account setups, subscriptions, or complex installations.

<div align="center">
  <img src="https://github.com/user-attachments/assets/872b0b55-9c62-457e-9965-8900700bcc43" alt="image 1" height="500" />
</div>

---

## Highlights

* **Native Concurrent Transfer Engine:** Configurable from 1 to 64 parallel threads to saturate fast gigabit fiber or cellular connections.
* **Persistent Android Foreground Service:** Tests run reliably in the background without being killed by aggressive OEM battery managers; includes live notification updates and an instant Stop action.
* **Real-Time Wire Throughput:** Immediate upload and download rate sampling with zero delay—no artificial smoothing or 0 Mbps freezes.
* **Instant Cancellation:** Tapping Stop terminates active socket I/O and shuts down workers immediately.
* **Comprehensive Network Telemetry:** Inspect active transport, Wi-Fi SSID, mobile carrier, radio technology (LTE, NR/5G, 5G NSA), IP addresses, and ISP metadata.
* **Flexible Transfer Limits:** Set custom duration limits (seconds) or data caps (GB), or run indefinitely until manually stopped.
* **Privacy-First & Self-Contained:** No tracking, analytics, or telemetrySDKs. All preferences and history stay locally on your device.

---

## Testing Modes

| Mode | Behavior |
| :--- | :--- |
| **Speed Test (Normal)** | Runs a full two-phase benchmark: download first, followed immediately by upload. Features continuous progress tracking (0% → 50% download, 50% → 100% upload). |
| **Download Only** | Sustained download testing with optional duration (seconds) or data caps (GB). Runs continuously until a limit is met or stopped. |
| **Upload Only** | Sustained upload testing with adaptive chunk sizing and real-time wire rate computation. Runs continuously until a limit is met or stopped. |

---

## App Settings & Configuration

The **Settings** page (`lib/ui/settings_screen.dart`) provides complete control over your testing environment, display preferences, and platform permissions:

### 1. Appearance
* Choose between **System Default**, **Light Mode**, or **Dark Mode**.
* Styled using Material 3 dynamic color tokens and typography.

### 2. Speed Units
* Toggle between **Mbps** (megabits per second) and **MB/s** (megabytes per second).
* Standard conversion factor: `1 MB/s = 8 Mbps`.
* Unit selection updates all active tests, speed meters, charts, notifications, and historical records.

### 3. Network Details & Permissions
* **Permission Diagnostics:** View and grant necessary Android permissions:
  * **Phone State (`READ_PHONE_STATE`):** Required by Android to read cellular radio technology (LTE, 5G NSA, NR).
  * **Location (`ACCESS_FINE_LOCATION`):** Required by Android to read the connected Wi-Fi SSID.
  * **Notifications (`POST_NOTIFICATIONS`):** Required on Android 13+ to display foreground transfer progress and the Stop button in the system tray.
* **Direct Navigation:** One-tap shortcuts to **App Permission Settings** and Android **Location Source Settings**.

### 4. Background Transfer Controls
* Detailed explanations of Android `dataSync` foreground service allowances, wake locks, and system power management behaviors.

### 5. Measurement Methodology
* Transparent documentation of payload calculation, HTTP transfer mechanics, server selection, and error reporting.

### 6. About & Footer
* Displays the active release version and author attribution:
  ```text
  Created by Sam Sam (https://www.samsam123.name.my) | v1.0.0
  ```

---

## Architecture

```
NetProbe
├── lib/                     # Flutter Material 3 UI Layer
│   ├── core/
│   │   ├── app_controller.dart   # State management & bridge event coordinator
│   │   ├── models.dart           # Data structures & configurations
│   │   ├── platform_bridge.dart  # MethodChannel & EventChannel bindings
│   │   ├── strings.dart          # Localized application copy
│   │   └── theme.dart            # Material 3 color schemes & typography
│   └── ui/
│       ├── test_screen.dart      # Real-time gauge, progress bar, limits & thread selector
│       ├── server_screen.dart    # Nearby discovery, search, favorites & custom servers
│       ├── settings_screen.dart  # Theme, units, permissions, diagnostic info & footer
│       └── history_screen.dart   # Local benchmark history and log management
│
└── android/app/src/main/kotlin/dev/sam/speedtest/
    ├── MainActivity.kt          # Platform channel dispatcher & permission handler
    ├── TransferService.kt       # Android Foreground Service, notification ticker & wake lock
    ├── TransferEngine.kt        # Multi-threaded HTTP transfer & socket accounting engine
    ├── NetworkDetails.kt        # Telephony & ConnectivityManager network reader
    └── TransferHttp.kt          # Transport abstraction layer
```

---

## Screenshots

<table>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/872b0b55-9c62-457e-9965-8900700bcc43" alt="image 1" width="443" height="854" /></td>
    <td><img src="https://github.com/user-attachments/assets/dddcc37e-9fd6-4d10-85ab-78354a902b1c" alt="image 2" width="443" height="854" /></td>
    <td><img src="https://github.com/user-attachments/assets/c0f2daee-874f-402f-a098-ea8335b78f2a" alt="image 3" width="443" height="854" /></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/27a4ea7c-a8e4-414a-8c8a-4fcca99f0a0b" alt="image 4" width="443" height="854" /></td>
    <td><img src="https://github.com/user-attachments/assets/f78f743c-85fb-4179-8fcf-3ed477d9d28c" alt="image 5" width="443" height="854" /></td>
    <td><img src="https://github.com/user-attachments/assets/4055392b-fa2b-4921-8482-be4a2dbd053e" alt="image 6" width="443" height="854" /></td>
  </tr>
</table>

---

## Build & Run

### Prerequisites
* Flutter SDK (3.32.0 or newer)
* Android Studio with **Android SDK Platform 36** and **Build Tools 36.0.0**
* Java 17+ / Java 25 (bundled with Android Studio JBR)

### Development
```bash
# Clone and enter the workspace
cd /path/to/speedtest

# Initialize SDK and build wrapper
bash scripts/bootstrap.sh

# Run on connected Android device
flutter run
```

### Build APK
```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

---

## Verification & Testing

NetProbe includes comprehensive native Kotlin engine tests as well as Flutter widget and controller tests:

```bash
# Run native concurrent engine tests (24 checks)
bash scripts/check-native.sh

# Run Flutter tests, static analysis, and formatting
flutter test
flutter analyze
```

---

## License & Credits

Created by **[Sam Sam](https://www.samsam123.name.my)** | `v1.0.0`
Released under the MIT License.
