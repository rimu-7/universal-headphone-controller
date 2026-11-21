# universal-headphone-controller

A native macOS Menu Bar application that provides a unified, elegant Control Center for **HUAWEI FreeLace Pro 2** and **EDIFIER Fit900NB** (as well as compatible FreeBuds and Edifier models). Control Active Noise Cancellation, Sound Effects (EQ), Volume, and Gaming Mode directly from your MacBook's menu bar without touching headphone buttons.

Works natively on both **Apple Silicon (M1/M2/M3/M4)** and **Intel (x86_64)** Macs.

---

## ✨ Features

- **Universal Multi-Device Support**: Controls both **Huawei FreeLace Pro 2** (via Classic Bluetooth RFCOMM) and **Edifier Fit900NB / W820NB** (via CoreBluetooth BLE GATT) in one single menu.
- **Universal Binary**: Built as a Universal 2 fat binary supporting both **Apple Silicon** (`arm64`) and **Intel** (`x86_64`).
- **Live Battery & Status**: Shows real-time battery percentage and active noise mode icon directly in the macOS menu bar.
- **Active Noise Cancellation (ANC) Switcher**:
  - 🔇 **Noise Cancellation (ANC)**
  - ⭕ **Off (Normal)**
  - 🌊 **Transparency / Ambient Sound**
- **Sound Effects & Equalizer Presets**:
  - ⚖️ **Default (Balanced)**
  - 🔊 **Bass Boost**
  - 🎵 **Treble Boost**
  - 🗣️ **Voice Mode**
- **Gaming & Low Latency Mode**: One-click toggle for ultra-low audio latency.
- **Smooth System Volume & Mute**: Direct macOS Master Output volume control and instant mute toggle.
- **Audio Output Routing**: One-click "Route Audio" button to switch Mac system audio to your headphones.
- **Pixel-Perfect Menu Bar Panel**: Native Control Center-style floating panel with frosted glass material (`.ultraThinMaterial`), 16 pt rounded corners, and click-outside dismissal.

---

## 📦 Installation via DMG

1. Download the latest `HeadphoneController.dmg` from [Releases](https://github.com/rimu-7/universal-headphone-controller/releases) or GitHub Actions.
2. Open `HeadphoneController.dmg`.
3. Drag **Headphone Controller** into your **Applications** folder.
4. Launch the app from Applications or Spotlight.
5. The 🎧 icon will appear in your top-right Menu Bar.

---

## 🛠️ Building Locally

### Prerequisites
- macOS 13.0 or later
- Xcode Command Line Tools (`xcode-select --install`)

### Build the Universal .app
```bash
./Scripts/build_app.sh
```

### Build the Installer .dmg
```bash
./Scripts/build_dmg.sh
```
This generates `HeadphoneController.dmg` containing the universal fat binary (`arm64` + `x86_64`) and an `/Applications` symlink.

### Run directly from source
```bash
./run.sh
```

---

## 🤖 Automated GitHub Actions Workflow

This repository includes automated CI in `.github/workflows/build.yml` that:
1. Runs on `macos-latest`.
2. Compiles the Universal 2 fat binary for both **Apple Silicon** and **Intel**.
3. Packages the application bundle and codesigns it.
4. Generates `HeadphoneController.dmg` with `/Applications` drag-and-drop installer.
5. Uploads the DMG as an artifact on every push.
6. Automatically publishes the DMG to GitHub Releases when a version tag (`v*`) is pushed.

---

## 🔄 Supported Protocols & Hardware

| Headphone | Transport & Protocol | Capabilities |
| :--- | :--- | :--- |
| **HUAWEI FreeLace Pro 2**<br>*(and FreeLace / FreeBuds)* | **Bluetooth Classic RFCOMM (Port 1)**<br>Huawei `0x5A` framing + CRC-16/XMODEM | Battery (%), Charging, ANC / Transparency / Off (`0x2B04`), Sound Effects (`0x2B49`), Low Latency (`0x2B6C`) |
| **EDIFIER Fit900NB**<br>*(and W820NB, W820NB Plus)* | **CoreBluetooth BLE GATT UART**<br>Service `4809xxxx-...`, RX `48090002`, TX `48090001`<br>Edifier `0xAA` framing + Checksum | Battery (%), ANC / Ambient / Off (`0xC1`), Sound Effects (`0xC4`), Game Mode (`0x09`) |
| **Mac System Audio** | **macOS CoreAudio & AppleScript Master Volume** | Master Volume Slider, Mute, Audio Output switching |

---

## ⚙️ Launch at Login (Optional)

1. Open **System Settings** ➔ **General** ➔ **Login Items**.
2. Under **Open at Login**, click **`+`**.
3. Choose `HeadphoneController.app` from `/Applications`.
