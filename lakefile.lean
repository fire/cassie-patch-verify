import Lake
open Lake DSL

package «cassie-patch-verify» where

-- The only dependency: the reusable witness-DAG search/certification driver.
-- This package reads the C++ cassie module's patch OUTPUT (JSON) and certifies
-- it; it never links into the C++/Godot build.
require «plausible-witness-dag» from git
  "https://github.com/fire/plausible-witness-dag" @ "main"

@[default_target] lean_exe «cassie-patch-verify» where
  root := `Main
