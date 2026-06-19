import Pipeline.Core.Vec3
import Pipeline.Ports.TriangulationPort
/-! # DmwtAdapter — wraps the CassieGeogram FFI for triangulation

Converts a closed boundary loop (Array Vec3) into the flat double array
expected by `cassie_triangulate_patch`, calls FFI, unpacks results.
-/
open Pipeline.Core Pipeline.Ports

-- FFI declarations (matches ffi/cassie_geogram_ffi.cpp exports)
@[extern "cassie_triangulate_patch"]
opaque cassieTriangulatePatch
    (boundary : @& ByteArray)   -- packed float64 xyz, row-major
    (nPts     : UInt64)
    (outVerts : @& ByteArray)   -- caller-allocates: nPts*3*8 bytes
    (outTris  : @& ByteArray)   -- caller-allocates: nPts*3*4*4 bytes (over-alloc)
    (outNVerts : @& ByteArray)  -- 8 bytes: uint64 actual vert count
    (outNTris  : @& ByteArray)  -- 8 bytes: uint64 actual tri count
    : UInt32 := 0               -- returns 0 on success

namespace Pipeline.Adapters

private def packBoundary (pts : Array Vec3) : ByteArray :=
  let n := pts.size
  let buf := ByteArray.mkEmpty (n * 3 * 8)
  pts.foldl (init := buf) fun b (x, y, z) =>
    b |> (·.append (Float.toIEEE754Bytes x))
      |> (·.append (Float.toIEEE754Bytes y))
      |> (·.append (Float.toIEEE754Bytes z))

/-- Extract a Float64 from 8 bytes at offset (little-endian IEEE 754). -/
private def getF64 (b : ByteArray) (off : Nat) : Float :=
  Float.fromIEEE754Bytes (b.extract off (off + 8))

/-- Extract a UInt32 from 4 bytes at offset (little-endian). -/
private def getU32 (b : ByteArray) (off : Nat) : Nat :=
  (b.get! off).toNat ||| ((b.get! (off+1)).toNat <<< 8)
  ||| ((b.get! (off+2)).toNat <<< 16) ||| ((b.get! (off+3)).toNat <<< 24)

/-- DmwtAdapter implementation of `TriangulationPort`. -/
def dmwtPort : TriangulationPort where
  triangulate pts := do
    if pts.size < 3 then return .error "boundary < 3 points"
    let n := pts.size
    let packed  := packBoundary pts
    let nVBuf   := ByteArray.mkEmpty 8  -- will hold result vert count
    let nTBuf   := ByteArray.mkEmpty 8  -- will hold result tri count
    let vertBuf := ByteArray.mkEmpty (n * 3 * 8 * 4)  -- generous over-alloc
    let triBuf  := ByteArray.mkEmpty (n * 3 * 4 * 4)
    let rc := cassieTriangulatePatch packed n.toUInt64 vertBuf triBuf nVBuf nTBuf
    if rc != 0 then return .error s!"DMWT FFI returned {rc}"
    let nV := (getU32 nVBuf 0) + (getU32 nVBuf 4 <<< 32)
    let nT := (getU32 nTBuf 0) + (getU32 nTBuf 4 <<< 32)
    let verts : Array Vec3 := Array.range nV |>.map fun i =>
      let off := i * 24
      (getF64 vertBuf off, getF64 vertBuf (off+8), getF64 vertBuf (off+16))
    let tris : Array (Nat × Nat × Nat) := Array.range nT |>.map fun i =>
      let off := i * 12
      (getU32 triBuf off, getU32 triBuf (off+4), getU32 triBuf (off+8))
    return .ok { id := "", boundary := #[pts], verts, tris }

end Pipeline.Adapters
