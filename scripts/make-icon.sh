#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift -module-cache-path .build/swift-icon-cache scripts/make-icon.swift
python3 - <<'PY'
from pathlib import Path
import struct
chunks = []
for code, name in [('icp4','16x16'),('icp5','32x32'),('icp6','32x32@2x'),('ic07','128x128'),('ic08','256x256'),('ic09','512x512'),('ic10','512x512@2x'),('ic11','16x16@2x'),('ic12','32x32@2x'),('ic13','128x128@2x'),('ic14','256x256@2x')]:
    data = Path(f'.build/LumaPulse.iconset/icon_{name}.png').read_bytes()
    chunks.append(code.encode() + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
Path('Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
PY
