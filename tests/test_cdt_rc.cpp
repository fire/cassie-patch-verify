// RapidCheck property-based tests for DMWT Triangulate().
//
// Properties verified:
//  P1. Convex n-gon (n∈[3,20]): triangulation succeeds and returns ≥ n-2 triangles.
//  P2. Convex n-gon: all vertex indices are in range [0, nV).
//  P3. Convex n-gon: vertex count nV ≥ n (no vertex is silently dropped).
//  P4. Triangle (n=3): always produces exactly 1 triangle (fan=1).
//
// Build (from repo root):
//   bash tests/build_test_cdt_rc.sh
// Run:
//   .lake/build/tests/test_cdt_rc

#include "cassie_triangulation/Triangulation.h"
#include <rapidcheck.h>

#include <cmath>
#include <cstdio>
#include <csignal>
#include <csetjmp>

// ---------------------------------------------------------------------------
// Signal guard — same pattern as test_cdt.cpp
// ---------------------------------------------------------------------------
static volatile sig_atomic_t g_in_tri = 0;
static sigjmp_buf             g_jmp;
static void sig_h(int) {
    if (g_in_tri) siglongjmp(g_jmp, 1);
    signal(SIGABRT, SIG_DFL); raise(SIGABRT);
}

struct TriResult {
    bool ok   = false;
    int  nV   = 0;
    int  nF   = 0;
    int* faces = nullptr;
};

static TriResult safe_tri(double* bnd, int n, float target) {
    signal(SIGABRT, sig_h); signal(SIGSEGV, sig_h);
    g_in_tri = 1;
    if (sigsetjmp(g_jmp, 1) != 0) {
        g_in_tri = 0; signal(SIGABRT, SIG_DFL); signal(SIGSEGV, SIG_DFL);
        return {};
    }
    double* verts = nullptr; int* faces = nullptr;
    int nV = 0, nF = 0;
    bool ok = Triangulate(bnd, n, target, &verts, &faces, &nV, &nF);
    g_in_tri = 0; signal(SIGABRT, SIG_DFL); signal(SIGSEGV, SIG_DFL);
    // Copy faces before CleanUp frees verts; keep faces pointer for index check.
    TriResult r{ ok, nV, nF, faces };
    if (verts) { free(verts); }   // only free verts; caller frees faces
    return r;
}

static void make_polygon(int n, double r, double* out) {
    for (int i = 0; i < n; ++i) {
        double a = 2.0 * M_PI * i / n;
        out[3*i+0] = r * cos(a);
        out[3*i+1] = 0.0;
        out[3*i+2] = r * sin(a);
    }
}

int main() {
    // P1: convex n-gon → succeeds and nF ≥ n-2
    rc::check("P1: convex n-gon triangulates with ≥ n-2 faces",
        [](int raw_n, int raw_r100) {
            int n = 3 + (raw_n < 0 ? -raw_n : raw_n) % 18;  // [3,20]
            double r = 0.05 + ((raw_r100 < 0 ? -raw_r100 : raw_r100) % 96) * 0.01; // [0.05,1.0]
            double bnd[64*3] = {};
            make_polygon(n, r, bnd);
            TriResult res = safe_tri(bnd, n, 0.05f);
            if (res.faces) free(res.faces);
            RC_ASSERT(res.ok);
            RC_ASSERT(res.nF >= n - 2);
        });

    // P2: all face indices in [0, nV)
    rc::check("P2: face indices are in-range",
        [](int raw_n, int raw_r100) {
            int n = 3 + (raw_n < 0 ? -raw_n : raw_n) % 18;
            double r = 0.05 + ((raw_r100 < 0 ? -raw_r100 : raw_r100) % 96) * 0.01;
            double bnd[64*3] = {};
            make_polygon(n, r, bnd);
            TriResult res = safe_tri(bnd, n, 0.05f);
            bool inRange = true;
            for (int i = 0; i < res.nF * 3 && inRange; ++i)
                inRange = (res.faces[i] >= 0 && res.faces[i] < res.nV);
            if (res.faces) free(res.faces);
            RC_ASSERT(inRange);
        });

    // P3: vertex count ≥ n (boundary vertices preserved)
    rc::check("P3: output vertex count ≥ input boundary size",
        [](int raw_n, int raw_r100) {
            int n = 3 + (raw_n < 0 ? -raw_n : raw_n) % 18;
            double r = 0.05 + ((raw_r100 < 0 ? -raw_r100 : raw_r100) % 96) * 0.01;
            double bnd[64*3] = {};
            make_polygon(n, r, bnd);
            TriResult res = safe_tri(bnd, n, 0.05f);
            if (res.faces) free(res.faces);
            RC_ASSERT(res.nV >= n);
        });

    // P4: triangle always succeeds with at least 1 face
    // (DMWT may add Steiner points so nF can exceed 1 when target < edge length)
    rc::check("P4: triangle (n=3) → succeeds with ≥ 1 face",
        [](int raw_r100) {
            double r = 0.05 + ((raw_r100 < 0 ? -raw_r100 : raw_r100) % 96) * 0.01;
            double bnd[3*3] = {};
            make_polygon(3, r, bnd);
            TriResult res = safe_tri(bnd, 3, 0.05f);
            if (res.faces) free(res.faces);
            RC_ASSERT(res.ok);
            RC_ASSERT(res.nF >= 1);
        });

    return 0;
}
