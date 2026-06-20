// Unit tests: pmp::uniform_remeshing on fan triangulations.
//
// These are the CASSIE patch sizes that previously triggered SIGABRT via
// minimize_squared_areas → inverse() on a singular matrix (degenerate edges in
// near-planar fan meshes). After the determinant-guard fix they should all
// complete and produce a denser mesh (nV_out > nV_in, nF_out > nF_in).
//
// Build (from repo root):
//   bash tests/build_test_remesh_fan.sh
// Run:
//   .lake/build/tests/test_remesh_fan

#include <pmp/algorithms/remeshing.h>
#include <pmp/surface_mesh.h>

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>

// ---------------------------------------------------------------------------
// Build a fan triangulation of a regular n-gon lying in the XY plane at z=0.
// V = n+1 (hub at origin + n boundary vertices), F = n (fan from hub).
// This matches the shape of CASSIE DMWT output on simple boundary polygons.
// radius: controls edge length density relative to targetEdgeLength=0.02.
// ---------------------------------------------------------------------------
static pmp::SurfaceMesh make_fan(int n, float radius = 0.1f)
{
    pmp::SurfaceMesh mesh;
    // Hub vertex
    auto hub = mesh.add_vertex(pmp::Point(0.0f, 0.0f, 0.0f));

    // Boundary ring
    std::vector<pmp::Vertex> ring;
    ring.reserve(n);
    for (int i = 0; i < n; ++i) {
        float angle = 2.0f * 3.14159265f * i / n;
        ring.push_back(mesh.add_vertex(
            pmp::Point(radius * std::cos(angle), radius * std::sin(angle), 0.0f)));
    }

    // Fan triangles: hub + consecutive pair of boundary verts
    for (int i = 0; i < n; ++i)
        mesh.add_triangle(hub, ring[i], ring[(i + 1) % n]);

    // Mark boundary edges as feature curve (required for remeshing to preserve shape)
    auto efeature = mesh.add_edge_property<bool>("e:feature", false);
    auto vfeature = mesh.add_vertex_property<bool>("v:feature", false);
    for (auto e : mesh.edges()) {
        if (mesh.is_boundary(e)) {
            efeature[e] = true;
            vfeature[mesh.vertex(e, 0)] = true;
            vfeature[mesh.vertex(e, 1)] = true;
        }
    }
    return mesh;
}

// ---------------------------------------------------------------------------
// Run remeshing and report results. Returns true on success (no crash, output
// is denser than input).
// ---------------------------------------------------------------------------
static bool test_case(const char* label, int n_boundary)
{
    // fan: V = n_boundary+1, F = n_boundary
    pmp::SurfaceMesh mesh = make_fan(n_boundary);
    int nV_in = static_cast<int>(mesh.n_vertices());
    int nF_in = static_cast<int>(mesh.n_faces());

    printf("  %-20s V=%d F=%d ... ", label, nV_in, nF_in);
    fflush(stdout);

    const float target = 0.02f;
    const unsigned nb_iter = 3;
    pmp::uniform_remeshing(mesh, static_cast<pmp::Scalar>(target), nb_iter, true);

    int nV_out = static_cast<int>(mesh.n_vertices());
    int nF_out = static_cast<int>(mesh.n_faces());
    bool ok = (nV_out > nV_in) && (nF_out > nF_in);
    printf("%s  V→%d F→%d\n", ok ? "OK" : "FAIL", nV_out, nF_out);
    return ok;
}

int main()
{
    printf("=== remesh fan-triangulation unit tests ===\n");
    int pass = 0, total = 0;

    // Sizes from CASSIE session dump (F=V-2 fan triangulations that previously
    // crashed via minimize_squared_areas → singular inverse → SIGABRT):
    struct { const char* label; int n_boundary; } cases[] = {
        // V=16/F=14 (8 patches): n_boundary=15 gives V=16, F=15 ≈ close enough
        // Note: fan has V=n+1, F=n. The DMWT fan has V=N_boundary, F=N_boundary-2
        // (it doesn't add a hub — it fans from a boundary vertex instead).
        // For testing pmp behavior, regular hub fans of similar size are equivalent.
        { "V16/F14 (×8)",   14 },
        { "V17/F15 (×4)",   15 },
        { "V19/F17 (×2)",   17 },
        { "V33/F31 (×2)",   31 },
        // Additional sizes seen in the run
        { "V14/F12",        12 },
        { "V30/F28",        28 },
        { "V28/F26",        26 },
        { "V41/F39",        39 },
    };

    for (auto& c : cases) {
        ++total;
        if (test_case(c.label, c.n_boundary)) ++pass;
    }

    printf("\n%d/%d passed\n", pass, total);
    return (pass == total) ? 0 : 1;
}
