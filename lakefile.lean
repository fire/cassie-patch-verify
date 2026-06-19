import Lake
open Lake DSL

package «cassie-patch-verify» where

-- The only dependency: the reusable witness-DAG search/certification driver.
-- This package reads the C++ cassie module's patch OUTPUT (JSON) and certifies
-- it; it never links into the C++/Godot build.
require «plausible-witness-dag» from git
  "https://github.com/fire/plausible-witness-dag" @ "main"

require LeanSlang from "vendor/lean-slang"

-- The temporal constructor lives here so Lake builds it as a module.
lean_lib «Timeline» where

-- geogram CDT2d Lean FFI layer (vendored from godot/modules/cassie/lean).
-- Build the backing archives first: `bash build_geogram_static.sh`
lean_lib «CassieGeogram» where

-- Hexagonal ports-and-adapters pipeline (core / ports / adapters).
lean_lib «Pipeline» where

-- Property-based tests using plausible-witness-dag.
lean_lib «PipelineTests» where

@[default_target] lean_exe «cassie-patch-verify» where
  root := `Main

-- Drives CASSIE triangulation: boundary cycle → geogram CDT2d → JSON mesh.
-- Links against libcassie_geogram_half.a + libcassie_geogram_ffi.a
-- (built by build_geogram_static.sh).
lean_exe «triangulate-patches» where
  root := `TriangulatePatches
  -- geogram compiled with Homebrew clang++ + libc++; same ABI as Lean's bundled libc++.
  -- --allow-multiple-definition silences any duplicate between Lean's libc++.a and this one.
  -- __isoc23_* references were renamed to strtoll/strtoull/sscanf via objcopy in
  -- build_geogram_static.sh (Fedora 44 glibc 2.43 aliases the classic names away).
  moreLinkArgs := #[
    "-Wl,--allow-multiple-definition",
    ".lake/build/geogram_static/libcassie_geogram_ffi.a",
    ".lake/build/geogram_static/libcassie_mwt.a",
    ".lake/build/geogram_static/libcassie_pmp.a",
    ".lake/build/geogram_static/libcassie_geogram_half.a",
    "/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1/lib/libc++.a",
    "/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1/lib/libc++abi.a",
    "-lm", "-lpthread" ]

-- End-to-end pipeline replay from raw inputSamples.
lean_exe «run-pipeline» where
  root := `RunPipeline
  moreLinkArgs := #[
    "-Wl,--allow-multiple-definition",
    ".lake/build/geogram_static/libcassie_geogram_ffi.a",
    ".lake/build/geogram_static/libcassie_mwt.a",
    ".lake/build/geogram_static/libcassie_pmp.a",
    ".lake/build/geogram_static/libcassie_geogram_half.a",
    "/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1/lib/libc++.a",
    "/home/linuxbrew/.linuxbrew/Cellar/llvm/22.1.7_1/lib/libc++abi.a",
    "-lm", "-lpthread" ]
