#!/usr/bin/env bash
# Build static libraries from vendored sources.
# All paths are relative to this script's directory — no external deps needed.
#
# Output (in .lake/build/geogram_static/):
#   libcassie_geogram_half.a  — geogram subset (patched: throw→abort for -fno-exceptions compat)
#   libcassie_pmp.a           — pmp-library remeshing subset
#   libcassie_mwt.a           — Ming Zou DMWT 3D polygon triangulation
#   libcassie_geogram_ffi.a   — Lean FFI wrapper (calls Triangulate())

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
GEO_ROOT="$REPO/vendor/geogram"
PMP_ROOT="$REPO/vendor/pmp"
EIGEN_INC="$REPO/vendor/eigen"
MWT_ROOT="$REPO/vendor/cassie-triangulation"
LEAN_TC=/home/ernest.lee/.elan/toolchains/leanprover--lean4---v4.30.0
LEAN_INC="$LEAN_TC/include"
BREW_LLVM=/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1
CXX="$BREW_LLVM/bin/clang++"
CC="$BREW_LLVM/bin/clang"
FFI_SRC="$REPO/ffi/cassie_geogram_ffi.cpp"
FFI_INC="$REPO/ffi"
BUILD="$REPO/.lake/build/geogram_static"
mkdir -p "$BUILD"

# ---------------------------------------------------------------------------
# Common flags
# ---------------------------------------------------------------------------
GEOGRAM_FLAGS=(
  -c -std=c++17 -O2 -fPIC
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1"
  -fexceptions
  -DEIGEN_DONT_PARALLELIZE
  -D__GLIBC_USE_DEPRECATED_SCANF=1
  -DGEOGRAM_WITH_BUILTIN_DEPS -DGEOGRAM_USE_BUILTIN_DEPS
  -DGEO_OS_LINUX -DGEO_DYNAMIC_LIBS= -DGEOGRAM_PSM=
  -I "$LEAN_INC"
  -I "$GEO_ROOT"
  -I "$GEO_ROOT/geogram/third_party"
  -I "$GEO_ROOT/geogram/third_party/numerics/include"
  -I "$GEO_ROOT/geogram/third_party/OpenNL"
)

PMP_FLAGS=(
  -c -std=c++17 -O2 -fPIC
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1"
  -fexceptions
  -DEIGEN_DONT_PARALLELIZE -DPMP_SCALAR_TYPE_64
  -I "$PMP_ROOT"
  -I "$REPO/vendor"
  -Wno-deprecated-declarations -Wno-unknown-warning-option
)

MWT_FLAGS=(
  -c -std=c++17 -O2 -fPIC
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1"
  -fexceptions
  -DEIGEN_DONT_PARALLELIZE -DPMP_SCALAR_TYPE_64
  -DGEOGRAM_WITH_BUILTIN_DEPS -DGEOGRAM_USE_BUILTIN_DEPS
  -DGEO_OS_LINUX -DGEO_DYNAMIC_LIBS= -DGEOGRAM_PSM=
  -I "$MWT_ROOT"
  -I "$MWT_ROOT/DataStructure"
  -I "$MWT_ROOT/Utility"
  -I "$MWT_ROOT/Algorithm"
  -I "$PMP_ROOT"
  -I "$REPO/vendor"
  -I "$GEO_ROOT"
  -I "$GEO_ROOT/geogram/third_party"
  -Wno-deprecated-declarations
)

CFLAGS_C=(
  -c -std=c11 -O2 -fPIC
  -DGEOGRAM_PSM=
  -I "$GEO_ROOT"
  -I "$GEO_ROOT/geogram/third_party"
  -I "$GEO_ROOT/geogram/third_party/numerics/include"
  -I "$GEO_ROOT/geogram/third_party/OpenNL"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
skip_contains() {
  local needle="$1"; shift
  for s in "$@"; do [ "$s" = "$needle" ] && return 0; done; return 1
}

geo_objs=()
compile_geo_dir() {
  local sub="$1"; shift; local skip=("$@")
  for src in "$GEO_ROOT/geogram/$sub"/*.cpp; do
    [ -f "$src" ] || continue
    local base; base=$(basename "$src")
    skip_contains "$base" "${skip[@]}" && continue
    local obj="$BUILD/geo_${sub//\//_}_${base%.cpp}.o"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
      echo "  c++ geo/$sub/$base"
      "$CXX" "${GEOGRAM_FLAGS[@]}" "$src" -o "$obj"
    fi
    geo_objs+=("$obj")
  done
}
compile_geo_keeplist() {
  local sub="$1"; shift; local keep=("$@")
  for src in "$GEO_ROOT/geogram/$sub"/*.cpp; do
    [ -f "$src" ] || continue
    local base; base=$(basename "$src")
    skip_contains "$base" "${keep[@]}" || continue
    local obj="$BUILD/geo_${sub//\//_}_${base%.cpp}.o"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
      echo "  c++ geo/$sub/$base"
      "$CXX" "${GEOGRAM_FLAGS[@]}" "$src" -o "$obj"
    fi
    geo_objs+=("$obj")
  done
}

# ---------------------------------------------------------------------------
# 1. Geogram
# ---------------------------------------------------------------------------
basic_skip=(geofile.cpp android_utils.cpp)
delaunay_skip=(delaunay_2d.cpp delaunay_tetgen.cpp delaunay_triangle.cpp parallel_delaunay_3d.cpp)
mesh_keep=(mesh.cpp mesh_reorder.cpp)
points_skip=(co3ne.cpp)

compile_geo_dir "basic"       "${basic_skip[@]}"
compile_geo_dir "numerics"
compile_geo_keeplist "mesh"   "${mesh_keep[@]}"
compile_geo_dir "delaunay"    "${delaunay_skip[@]}"
compile_geo_dir "points"      "${points_skip[@]}"
compile_geo_dir "api"
compile_geo_dir "bibliography"
compile_geo_dir "third_party/predicate_generator"
compile_geo_dir "third_party/numerics"

for src in "$GEO_ROOT/geogram/third_party/OpenNL"/*.c; do
  [ -f "$src" ] || continue
  base=$(basename "$src")
  obj="$BUILD/geo_OpenNL_${base%.c}.o"
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
    echo "  cc  geo/OpenNL/$base"
    "$CC" "${CFLAGS_C[@]}" "$src" -o "$obj"
  fi
  geo_objs+=("$obj")
done

# Fedora 44 glibc 2.43 aliases strtoll→__isoc23_strtoll; rename back.
echo "  objcopy: __isoc23_* → classic names in geogram objects"
for obj in "${geo_objs[@]}"; do
  if nm -u "$obj" 2>/dev/null | grep -q __isoc23; then
    objcopy \
      --redefine-sym __isoc23_strtoll=strtoll \
      --redefine-sym __isoc23_strtoull=strtoull \
      --redefine-sym __isoc23_sscanf=sscanf \
      --redefine-sym __isoc23_strtol=strtol \
      --redefine-sym __isoc23_strtoul=strtoul \
      "$obj" "$obj"
  fi
done

ar rcs "$BUILD/libcassie_geogram_half.a" $(printf '%s\n' "${geo_objs[@]}" | sort)
echo "OK  libcassie_geogram_half.a  ($(du -h "$BUILD/libcassie_geogram_half.a" | cut -f1))  ${#geo_objs[@]} objects"

# ---------------------------------------------------------------------------
# 2. pmp-library (remeshing subset)
# ---------------------------------------------------------------------------
pmp_keep=(
  remeshing.cpp decimation.cpp differential_geometry.cpp normals.cpp
  features.cpp smoothing.cpp utilities.cpp distance_point_triangle.cpp
  triangulation.cpp curvature.cpp laplace.cpp numerics.cpp
)
pmp_objs=()

src="$PMP_ROOT/pmp/surface_mesh.cpp"
obj="$BUILD/pmp_surface_mesh.o"
if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
  echo "  c++ pmp/surface_mesh"
  "$CXX" "${PMP_FLAGS[@]}" "$src" -o "$obj"
fi
pmp_objs+=("$obj")

for src in "$PMP_ROOT/pmp/algorithms"/*.cpp; do
  [ -f "$src" ] || continue
  base=$(basename "$src")
  skip_contains "$base" "${pmp_keep[@]}" || continue
  obj="$BUILD/pmp_${base%.cpp}.o"
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
    echo "  c++ pmp/$base"
    "$CXX" "${PMP_FLAGS[@]}" "$src" -o "$obj"
  fi
  pmp_objs+=("$obj")
done

ar rcs "$BUILD/libcassie_pmp.a" $(printf '%s\n' "${pmp_objs[@]}" | sort)
echo "OK  libcassie_pmp.a  ($(du -h "$BUILD/libcassie_pmp.a" | cut -f1))  ${#pmp_objs[@]} objects"

# ---------------------------------------------------------------------------
# 3. MWT — Ming Zou DMWT (cassie-triangulation)
# ---------------------------------------------------------------------------
mwt_srcs=(
  "$MWT_ROOT/Triangulation.cpp"
  "$MWT_ROOT/refine.cpp"
  "$MWT_ROOT/Algorithm/DMWT.cpp"
  "$MWT_ROOT/Algorithm/DMWT_dot.cpp"
  "$MWT_ROOT/DataStructure/EdgeInfo.cpp"
  "$MWT_ROOT/DataStructure/MingCurve.cpp"
  "$MWT_ROOT/DataStructure/TriangleInfo.cpp"
  "$MWT_ROOT/Utility/DelaunayFaces.cpp"
  "$MWT_ROOT/Utility/Point3.cpp"
  "$MWT_ROOT/Utility/Vector3.cpp"
)
mwt_objs=()
for src in "${mwt_srcs[@]}"; do
  base=$(basename "$src" .cpp)
  obj="$BUILD/mwt_${base}.o"
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
    echo "  c++ mwt/$base"
    "$CXX" "${MWT_FLAGS[@]}" "$src" -o "$obj"
  fi
  mwt_objs+=("$obj")
done

echo "  objcopy: __isoc23_* → classic names in mwt objects"
for obj in "${mwt_objs[@]}"; do
  if nm -u "$obj" 2>/dev/null | grep -q __isoc23; then
    objcopy \
      --redefine-sym __isoc23_strtoll=strtoll \
      --redefine-sym __isoc23_strtoull=strtoull \
      --redefine-sym __isoc23_sscanf=sscanf \
      --redefine-sym __isoc23_strtol=strtol \
      --redefine-sym __isoc23_strtoul=strtoul \
      "$obj" "$obj"
  fi
done

ar rcs "$BUILD/libcassie_mwt.a" $(printf '%s\n' "${mwt_objs[@]}" | sort)
echo "OK  libcassie_mwt.a  ($(du -h "$BUILD/libcassie_mwt.a" | cut -f1))  ${#mwt_objs[@]} objects"

# ---------------------------------------------------------------------------
# 4. Lean FFI wrapper + Slang RDP dispatch
# ---------------------------------------------------------------------------
RDP_FLAGS=(
  -c -std=c++17 -O2 -fPIC
  -stdlib=libc++ "-I$BREW_LLVM/include/c++/v1"
  -fexceptions
  -I "$FFI_INC"
)

rdp_obj="$BUILD/curve_rdp_dispatch.o"
RDP_SRC="$REPO/ffi/curve_rdp_dispatch.cpp"
if [ ! -f "$rdp_obj" ] || [ "$RDP_SRC" -nt "$rdp_obj" ]; then
  echo "  c++ curve_rdp_dispatch (Slang RDP)"
  "$CXX" "${RDP_FLAGS[@]}" "$RDP_SRC" -o "$rdp_obj"
fi

ffi_obj="$BUILD/cassie_geogram_ffi.o"
if [ ! -f "$ffi_obj" ] || [ "$FFI_SRC" -nt "$ffi_obj" ]; then
  echo "  c++ cassie_geogram_ffi"
  "$CXX" "${MWT_FLAGS[@]}" \
    -I "$LEAN_INC" \
    -I "$FFI_INC" \
    "$FFI_SRC" -o "$ffi_obj"
fi

COMPAT_SRC="$REPO/ffi/isoc23_compat.c"
compat_obj="$BUILD/isoc23_compat.o"
if [ ! -f "$compat_obj" ] || [ "$COMPAT_SRC" -nt "$compat_obj" ]; then
  echo "  cc  isoc23_compat"
  "$CC" -c -O2 -fPIC "$COMPAT_SRC" -o "$compat_obj"
fi

for obj in "$ffi_obj" "$compat_obj" "$rdp_obj"; do
  if nm -u "$obj" 2>/dev/null | grep -q __isoc23; then
    objcopy \
      --redefine-sym __isoc23_strtoll=strtoll \
      --redefine-sym __isoc23_strtoull=strtoull \
      --redefine-sym __isoc23_sscanf=sscanf \
      --redefine-sym __isoc23_strtol=strtol \
      --redefine-sym __isoc23_strtoul=strtoul \
      "$obj" "$obj"
  fi
done

ar rcs "$BUILD/libcassie_geogram_ffi.a" "$ffi_obj" "$compat_obj" "$rdp_obj"
echo "OK  libcassie_geogram_ffi.a  (wrapper + isoc23 compat + Slang RDP)"
