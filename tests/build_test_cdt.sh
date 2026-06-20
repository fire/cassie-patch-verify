#!/usr/bin/env bash
# Build and run the CDT triangulation unit tests.
# Run from repo root: bash tests/build_test_cdt.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
BREW_LLVM=/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1
CXX="$BREW_LLVM/bin/clang++"
BUILD="$REPO/.lake/build/tests"
LIBDIR="$REPO/.lake/build/geogram_static"

mkdir -p "$BUILD"

"$CXX" \
  -std=c++17 -O2 \
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1" \
  -fexceptions \
  -I "$REPO/ffi" \
  -I "$REPO/vendor" \
  "$REPO/tests/test_cdt.cpp" \
  "$LIBDIR/libcassie_mwt.a" \
  "$LIBDIR/libcassie_pmp.a" \
  "$LIBDIR/libcassie_geogram_half.a" \
  -L"$BREW_LLVM/lib" -lc++ -lc++abi \
  -lm \
  -o "$BUILD/test_cdt"

echo "Built: $BUILD/test_cdt"
LD_LIBRARY_PATH="$BREW_LLVM/lib" "$BUILD/test_cdt"
