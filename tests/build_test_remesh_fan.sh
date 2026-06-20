#!/usr/bin/env bash
# Build and run the fan-triangulation remesh unit tests.
# Run from repo root: bash tests/build_test_remesh_fan.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PMP_ROOT="$REPO/vendor/pmp"
BREW_LLVM=/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1
CXX="$BREW_LLVM/bin/clang++"
BUILD="$REPO/.lake/build/tests"
LIBDIR="$REPO/.lake/build/geogram_static"

mkdir -p "$BUILD"

"$CXX" \
  -std=c++17 -O2 \
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1" \
  -fexceptions \
  -DPMP_SCALAR_TYPE_64 \
  -I "$PMP_ROOT" \
  -I "$REPO/vendor" \
  "$REPO/tests/test_remesh_fan.cpp" \
  "$LIBDIR/libcassie_pmp.a" \
  -L"$BREW_LLVM/lib" -lc++ -lc++abi \
  -o "$BUILD/test_remesh_fan"

echo "Built: $BUILD/test_remesh_fan"
LD_LIBRARY_PATH="$BREW_LLVM/lib" "$BUILD/test_remesh_fan"
