# Headphone Controller

A native macOS menu bar app for Huawei and Edifier headphones. Control supported noise modes and sound settings, see battery status, and route Mac audio without opening a phone app.

Requires macOS 13 or later. The packaged app is a Universal 2 binary for Apple Silicon and Intel.

## Edifier support

Audio connectivity and the headphone control connection are separate. The app shows both, detects the protocol with read-only requests, and enables controls after valid state responses. Setting changes stay pending until the headset reports its actual value.

| Device/profile | Control transport | Implemented controls |
| --- | --- | --- |
| Fit900NB | Classic Bluetooth SPP/RFCOMM; vendor service discovered through SDP, documented channel 1 fallback | Battery, charging through F2, Deep/Comfort/Wind/Ambient/Off noise modes for index 0x10, Music/Game/Spatial scenes, ambient gain, firmware |
| W820NB / W820NB Plus | BLE GATT, legacy framing preferred | Battery, ANC/Ambient/Off, ambient gain, game mode when reported; EQ withheld |
| W820NB Double Gold | BLE GATT | Above plus documented Classic/Pop/Classical/Rock sound presets when reported |
| W200BT Plus | BLE GATT | Battery and supported sound presets; no ANC or game control queries |
| Other Edifier models | Recognized Edifier BLE services | Conservative read-based detection of compatible controls; model-specific extensions may be needed |
| Huawei FreeLace / FreeBuds | Existing Classic RFCOMM implementation | Existing Huawei battery, ANC, EQ and low latency controls |

This is an independent implementation of undocumented vendor protocols. Support varies by model and firmware; **all Edifier headphones are not guaranteed**. Fit900NB Turbo is a different product and does not inherit the Fit900NB profile. Models requiring encrypted SPP payloads are not implemented. Fit900NB EQ mappings are unverified and are not exposed as generic Bass/Treble/Voice controls.

Multiple Edifier devices have independent sessions. Classic and BLE rows are joined using a reported MAC address, rather than a brand-wide or name-only match. System audio routing highlights a unique matching device.

## Run or install

Download a packaged DMG from [Releases](https://github.com/rimu-7/universal-headphone-controller/releases), open it, and drag the app to Applications. Bluetooth access must be allowed in **System Settings → Privacy & Security → Bluetooth**.

To build the current source and launch it:

```bash
./Scripts/build_app.sh
./run.sh
```

`run.sh` launches the existing local app bundle. Rebuild after source changes, and quit an older running copy before opening the new one.

To create the installer:

```bash
./Scripts/build_dmg.sh
```

The app provides system volume/mute and **Set as Output** independently of proprietary headphone features. Add the app in **System Settings → General → Login Items** to launch at login.

## Updates from the app

Install this updater-enabled release manually once. Open the menu bar panel and use **Updates → Check for Updates…** for future releases. Sparkle shows download progress and offers **Install and Relaunch**; installing an update preserves app preferences.

**Check Automatically** is enabled by default and checks hourly. You can turn it off in the same menu, or enable **Download and Install Automatically** for Sparkle's background update flow. Automatic downloading/installing is not enabled on first install. The panel shows both the app version and build number.

Updates use Sparkle 2.10.1, pinned by SHA-256. Both the update archive and feed are signed with Ed25519, and archives are verified before extraction. The private key is kept in macOS Keychain under the account `com.user.HeadphoneController` and in the repository's encrypted `SPARKLE_PRIVATE_KEY` Actions secret. Only the public key in `Config/SparklePublicKey.txt` belongs in Git.

## Publishing changes

Push an ordinary commit to `main`; no manual version tag or DMG packaging is needed:

1. GitHub Actions runs protocol and release tests and builds both Mac architectures.
2. The build receives a unique `CFBundleVersion` from the Actions run number and attempt.
3. A separate release job signs the update ZIP and feed, validates them against the app's public key, and uploads all files to a draft release.
4. Only after all uploads succeed does the release become public and become the updater's latest feed.

Releases contain **HeadphoneController.dmg** for manual installation, **HeadphoneController-update.zip** for Sparkle, **appcast.xml**, and **SHA256SUMS**. Pull requests build artifacts but cannot publish or access the signing secret. Failed builds leave the previous update available. Rerunning a release job resumes its draft without overwriting a published build.

If a newer commit reaches `main` during a build, the superseded build skips publication and leaves that newer build to publish. This prevents an outdated commit from replacing the latest feed or requiring extra workflow-write permissions.

The product version is in `VERSION`. Release tags look like `v1.1.0-build.12.1`; the final numbers distinguish repeated development updates even when the product version is unchanged. Local builds use build `0`, so they can find the published CI build. The workflow can also be run manually from GitHub's Actions page on `main`.

The build remains ad-hoc signed, as before; it is not Apple-notarized. Sparkle's separate Ed25519 signatures authenticate app updates. Keep the existing signing key when making future changes so already installed copies continue to trust new releases.

## Troubleshooting Fit900NB

1. Pair and connect **EDIFIER Fit900NB** in macOS Bluetooth settings.
2. Close Edifier Connect on your phone. The headset may allow only one SPP control client at a time.
3. Open the menu bar panel and choose **Retry Controls**. Audio can stay connected while the control channel reconnects.
4. If controls remain unavailable, choose **Copy Diagnostics**. The report contains the detected profile, transport, services, firmware, confirmed features, timeouts and recent protocol frames.

An unknown battery is shown as `--%`; a real 0% response remains valid. When proprietary queries or Classic discovery are unavailable, an asynchronous macOS Bluetooth report supplies connected-device discovery and battery once a minute. The UI remains responsive when IOBluetooth stalls, and reports how to recover control access. Unrecognized state bytes are ignored instead of being displayed as Off or Default. Diagnostics stay in a bounded in-memory log and are copied only when requested; frame logs can contain device identifiers.

## Development and validation

Install Xcode Command Line Tools with `xcode-select --install`. The app build script uses `swiftc` directly. The first build downloads the pinned official Sparkle distribution; subsequent builds reuse its verified cache.

```bash
# Hardware-independent protocol/state regression tests; works without XCTest
./Scripts/test_protocols.sh

# Validate release/feed invariants
python3 -m unittest discover -s Tests/ReleaseTests -v

# XCTest target, with a working SwiftPM/Xcode installation
swift test
```

The same test methods run in both paths. Coverage includes captured frame vectors, fragmented/coalesced notifications, checksum failures, stale buffers, battery 0%, Fit900NB indexed ANC and scenes, acknowledgement/readback separation, timeouts, rejected writes, disconnect cleanup and independent sessions. CI runs these tests before packaging.

Implementation boundaries:

- `AppUpdater`: Sparkle settings and native update UI, independent of Bluetooth.
- `EdifierProfile`: model/service matching, supported command policy, indexed mode tables.
- `EdifierPacket` / `EdifierFrameDecoder`: framing, checksums and bounded stream reassembly.
- `EdifierControlSession`: protocol detection, serialized requests, readback confirmation and capability state.
- `EdifierRFCOMMConnection`: Fit900NB SDP/SPP transport and reconnect backoff.
- `PairedBluetoothDeviceReader`: background Classic discovery, avoiding an IOBluetooth main-thread initialization deadlock.
- `EdifierBLEManager`: discovery of advertised/cached/system-connected peripherals, per-device GATT endpoints, standard BLE battery fallback and identity reconciliation.

Adding a model requires evidence for its transport, framing, payload layouts and mode meanings, plus captured regression vectors. Do not enable a feature from an unparsed D8 bit or reuse another model's labels without verification.

Protocol references: [Fit900NB interoperability notes](https://github.com/OldWooood/edifier-fit900nb/blob/main/docs/fit900nb-protocol.md), [legacy Edifier captures](https://github.com/GlitchPunkWTF/edifier-proto), [mEDIFIER](https://github.com/wh201906/mEDIFIER), and [macOS BLE transport notes](https://github.com/estevao-tarifa/edifier-macos/blob/main/docs/protocol.md). This implementation does not bundle their code or vendor APK/configuration files.
