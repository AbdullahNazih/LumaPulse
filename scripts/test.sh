#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox --cache-path .build/cache
binary_directory=$(swift build -c release --show-bin-path --disable-sandbox --cache-path .build/cache)
"$binary_directory/LumaPulse" --self-test
python3 scripts/security-check.py
python3 -m unittest discover -s Tests -p 'test_*.py'
