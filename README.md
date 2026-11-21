# 🎧 Headphone Controller for macOS

A native macOS Menu Bar application to control **HUAWEI FreeLace Pro 2** and **EDIFIER Fit900NB** (and compatible models) directly from your MacBook's menu bar — eliminating the need to use physical headphone buttons.

---

## 🌟 Key Features

- **Universal Multi-Device Control**: Supports both **Huawei FreeLace Pro 2** (via Classic Bluetooth RFCOMM) and **Edifier Fit900NB / W820NB** (via Bluetooth Low Energy / GATT) in a single unified interface.
- **Menu Bar Status & Battery**: See real-time battery percentage and active noise mode icon directly in the macOS menu bar.
- **Active Noise Cancellation (ANC) Modes**: One-click switching between:
  - 🔇 **Noise Cancellation (ANC)**
  - ⭕ **Off (Normal)**
  - 🌊 **Transparency / Ambient Sound**
- **Mac Volume & Mute**: Native CoreAudio volume slider and one-click mute toggle.
- **Audio Output Routing**: Switch macOS system audio output to your headphones with one click.
- **Gaming / Low-Latency Mode**: Toggle low latency mode on both Huawei and Edifier.
- **Equalizer Presets**: Quick sound mode selection (Default, Bass Boost, Treble Boost, Vocal Boost).
- **Native & Lightweight**: Built with Swift, AppKit, SwiftUI, IOBluetooth, and CoreBluetooth. Runs with `LSUIElement` (pure menu bar app, zero Dock clutter).

---

## 🚀 Quick Start

### Launch the App
Run the launcher script from the terminal:
```bash
cd /Users/walter/git-6/headphone-controller
./run.sh
```

The app will appear immediately in your macOS Menu Bar at the top right (look for the 🎧 icon or battery percentage like `82%`).

### Rebuild from Source
If you make any changes to the Swift code, simply run:
```bash
./Scripts/build_app.sh
```
This compiles the release binary and packages `HeadphoneController.app` with ad-hoc code signing.

---

## 🔄 Supported Devices & Protocols

| Device | Protocol / Transport | Features Supported |
| :--- | :--- | :--- |
| **HUAWEI FreeLace Pro 2**<br>*(and FreeLace / FreeBuds)* | **Bluetooth Classic RFCOMM / SPP (Port 1)**<br>Framing: `0x5A` + Length + `0x00` + CMD + TLV + CRC-16/XMODEM | Battery (%), Charging state, ANC / Transparency / Off, Low Latency, EQ presets |
| **EDIFIER Fit900NB**<br>*(and W820NB, W820NB Plus, NeoBuds)* | **CoreBluetooth BLE GATT UART**<br>Service: `4809xxxx-1a48-11e9-ab14-d663bd873d93`<br>Framing: `0xAA` + Len + CMD + Data + Checksum (`sum + 0x2019`) | Battery (%), ANC / Ambient / Off, Game Mode toggle, Device Name query |
| **Universal Mac Audio** | **macOS CoreAudio API** | System volume slider, Mute toggle, Audio output switching |

---

## ⚡ Launch at Login (Optional)

To have **Headphone Controller** launch automatically whenever your MacBook boots:
1. Open **System Settings** on your Mac.
2. Go to **General** ➔ **Login Items**.
3. Under **Open at Login**, click the **`+`** button.
4. Select `HeadphoneController.app` from `/Users/walter/git-6/headphone-controller/HeadphoneController.app`.

---

## 📁 Project Structure

```
headphone-controller/
├── HeadphoneController.app/       # Ready-to-use macOS application bundle
├── run.sh                         # Quick launch script
├── Package.swift                  # Swift Package Manager manifest
├── Scripts/
│   └── build_app.sh               # Build & bundle script
└── Sources/
    └── HeadphoneController/
        ├── App/
        │   ├── AppDelegate.swift  # Menu bar status item & popover logic
        │   └── main.swift         # App entry point (accessory activation policy)
        ├── Models/
        │   ├── ANCMode.swift      # ANC mode enum (cancellation, off, awareness)
        │   ├── EqualizerPreset.swift
        │   ├── HeadphoneBrand.swift
        │   └── HeadphoneDevice.swift
        ├── Protocols/
        │   ├── CRC16Xmodem.swift  # Huawei CRC16/XMODEM & Edifier checksum
        │   ├── HuaweiProtocol.swift # Huawei TLV packet encoder/decoder
        │   └── EdifierProtocol.swift # Edifier packet builder & response parser
        ├── Services/
        │   ├── Audio/
        │   │   └── CoreAudioController.swift # Volume, mute, output routing
        │   ├── Bluetooth/
        │   │   ├── HuaweiRFCOMMManager.swift # Classic Bluetooth RFCOMM channel
        │   │   └── EdifierBLEManager.swift   # CoreBluetooth BLE central
        │   └── HeadphoneManager.swift        # Unified coordinator
        └── Views/
            ├── ANCSelectorView.swift  # Control Center-style segmented ANC switcher
            ├── BatteryBadgeView.swift # Battery icon, color gauge, charging bolt
            ├── DeviceRowView.swift    # Device card with ANC, volume, and EQ
            ├── MainPopoverView.swift  # Menu bar popover layout
            └── VolumeControlView.swift # Native volume slider and mute
```
