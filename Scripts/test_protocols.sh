#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/headphone-protocol-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR" <<'PY'
import re
import sys
from pathlib import Path
out = Path(sys.argv[1])
calls = []
for source in sorted(Path('Tests/HeadphoneControllerTests').glob('*.swift')):
    text = source.read_text().replace('import XCTest\n', '').replace('@testable import HeadphoneController\n', '')
    (out / source.name).write_text(text)
    cls = re.search(r'final class (\w+): XCTestCase', text).group(1)
    for method in re.findall(r'    func (test\w+)\(\)', text):
        calls.append(f'{cls}().{method}()')
(out / 'main.swift').write_text('import Foundation\n' + '\n'.join(calls) + f'\nprint("Ran {len(calls)} tests; \\(assertionFailures) assertion failures")\nexit(assertionFailures == 0 ? 0 : 1)\n')
PY
swiftc -swift-version 5 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$PWD/.build/protocol-module-cache}" \
    Sources/HeadphoneController/Models/*.swift \
    Sources/HeadphoneController/Protocols/CRC16Xmodem.swift \
    Sources/HeadphoneController/Protocols/EdifierProtocol.swift \
    Sources/HeadphoneController/Services/Bluetooth/EdifierControlSession.swift \
    Sources/HeadphoneController/Services/Bluetooth/BluetoothBatteryReader.swift \
    Sources/HeadphoneController/Services/Bluetooth/PairedBluetoothDeviceReader.swift \
    Tests/Support/StandaloneAssertions.swift "$TEST_DIR"/*.swift \
    -o "$TEST_DIR/protocol-tests"
"$TEST_DIR/protocol-tests"
