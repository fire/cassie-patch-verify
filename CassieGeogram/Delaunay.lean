/-!
# `CassieGeogram.Delaunay` — geogram CDT2d FFI

Constrained Delaunay triangulation from a closed boundary polyline.
C wrapper at `ffi/cassie_geogram_ffi.cpp`.
-/

namespace CassieGeogram

abbrev DelaunayHandle := USize

@[extern "cassie_geogram_delaunay_from_boundary"]
opaque delaunayFromBoundary (n_pts : USize) (positions : @& FloatArray)
    (targetEdgeLength : Float) : IO DelaunayHandle

@[extern "cassie_geogram_delaunay_free"]
opaque delaunayFree (d : DelaunayHandle) : IO Unit

@[extern "cassie_geogram_delaunay_n_vertices"]
opaque nVertices (d : DelaunayHandle) : IO USize

@[extern "cassie_geogram_delaunay_n_triangles"]
opaque nTriangles (d : DelaunayHandle) : IO USize

-- Returns raw bytes: each 8 bytes is one IEEE 754 double (x/y/z, triples).
@[extern "cassie_geogram_delaunay_get_positions"]
opaque getPositions (d : DelaunayHandle) : IO ByteArray

-- Returns raw bytes: each 4 bytes is one little-endian uint32 vertex index.
@[extern "cassie_geogram_delaunay_get_triangles"]
opaque getTriangles (d : DelaunayHandle) : IO ByteArray

end CassieGeogram
