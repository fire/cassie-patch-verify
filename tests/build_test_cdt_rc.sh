#!/usr/bin/env bash
# Build and run the RapidCheck property-based CDT triangulation tests.
# Run from repo root: bash tests/build_test_cdt_rc.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
BREW_LLVM=/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1
CXX="$BREW_LLVM/bin/clang++"
BUILD="$REPO/.lake/build/tests"
LIBDIR="$REPO/.lake/build/geogram_static"
RC_DIR="$REPO/vendor/rapidcheck"
RC_BUILD="$REPO/.lake/build/rapidcheck"

mkdir -p "$BUILD" "$RC_BUILD"

# ---------------------------------------------------------------------------
# Compile rapidcheck as a single archive (sources in vendor/rapidcheck/src/)
# ---------------------------------------------------------------------------
RC_LIB="$RC_BUILD/librapidcheck.a"
if [ ! -f "$RC_LIB" ]; then
  RC_OBJS=()
  while IFS= read -r src; do
    # flatten path to unique obj name using slash → underscore
    rel="${src#"$RC_DIR/src/"}"
    obj="$RC_BUILD/${rel//\//_}.o"
    mkdir -p "$(dirname "$obj")"
    "$CXX" \
      -std=c++14 -O2 \
      -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1" \
      -I "$RC_DIR/include" \
      -c "$src" -o "$obj"
    RC_OBJS+=("$obj")
  done < <(find "$RC_DIR/src" -name "*.cpp" | sort)
  ar rcs "$RC_LIB" "${RC_OBJS[@]}"
  echo "Built: $RC_LIB"
fi

# ---------------------------------------------------------------------------
# Compile and link the test binary
# ---------------------------------------------------------------------------
"$CXX" \
  -std=c++17 -O2 \
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1" \
  -fexceptions \
  -I "$REPO/ffi" \
  -I "$REPO/vendor" \
  -I "$RC_DIR/include" \
  "$REPO/tests/test_cdt_rc.cpp" \
  "$LIBDIR/libcassie_mwt.a" \
  "$LIBDIR/libcassie_pmp.a" \
  "$LIBDIR/libcassie_geogram_half.a" \
  "$RC_LIB" \
  -L"$BREW_LLVM/lib" -lc++ -lc++abi \
  -lm \
  -o "$BUILD/test_cdt_rc"

echo "Built: $BUILD/test_cdt_rc"
LD_LIBRARY_PATH="$BREW_LLVM/lib" "$BUILD/test_cdt_rc"
