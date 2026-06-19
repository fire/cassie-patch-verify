/**************************************************************************/
/*  cassie_geogram_ffi.cpp                                                */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

// Ming Zou 2013 DMWT triangulation (3D-native, no projection).
// Triangulate() is defined in cassie-triangulation/src/Triangulation.cpp.
#include "cassie_triangulation/Triangulation.h"
// Slang-emitted RDP polyline simplifier (reduces dense stroke samples before DMWT).
#include "curve_rdp_dispatch.h"
#include <lean/lean.h>

#include <atomic>
#include <csetjmp>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <exception>
#include <vector>

namespace {

// Per-thread jmp_buf for catching SIGSEGV/SIGFPE from DMWT on degenerate input.
thread_local sigjmp_buf cdt_jmpbuf;
thread_local volatile bool cdt_recovering = false;

static void cdt_signal_handler(int sig) {
    (void)sig;
    if (cdt_recovering) {
        siglongjmp(cdt_jmpbuf, 1);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

// terminate handler: redirect std::terminate() (from uncaught exceptions) to
// siglongjmp if we're inside a protected Triangulate() call.
static void cdt_terminate_handler() {
    if (cdt_recovering) {
        siglongjmp(cdt_jmpbuf, 1);
    }
    std::abort();
}

struct DelaunayResult {
    std::vector<double>   verts; // flat x,y,z triples
    std::vector<uint32_t> tris;  // flat a,b,c triples
};

inline DelaunayResult *as_result(size_t handle) {
    return reinterpret_cast<DelaunayResult *>(handle);
}

} // namespace

extern "C" {

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_from_boundary(
        size_t n_pts, lean_obj_arg positions, double target_edge_length,
        lean_obj_arg /*world*/) {
    auto *res = new DelaunayResult();
    if (n_pts >= 3) {
        const double *src = lean_float_array_cptr(positions);

        // Dedup: drop consecutive identical 3D points and closed-loop tail.
        const double eps2 = 1e-12;
        auto same3 = [&](size_t i, size_t j) -> bool {
            double dx = src[3*i]-src[3*j], dy = src[3*i+1]-src[3*j+1], dz = src[3*i+2]-src[3*j+2];
            return dx*dx + dy*dy + dz*dz < eps2;
        };
        std::vector<size_t> kept;
        kept.reserve(n_pts);
        for (size_t i = 0; i < n_pts; ++i) {
            if (!kept.empty() && same3(i, kept.back())) continue;
            kept.push_back(i);
        }
        while (kept.size() >= 2 && same3(kept.front(), kept.back()))
            kept.pop_back();
        if (kept.size() < 3) {
            return lean_io_result_mk_ok(lean_box_usize(reinterpret_cast<size_t>(res)));
        }

        // RDP simplification: reduce dense stroke samples so DMWT's edgeProtect
        // stays within BADEDGE_LIMIT=30. Uses the same Slang-emitted kernel as
        // the Unity CASSIE module (cassie_slang_dispatch::curve_rdp_reduce).
        // tolerance=0.005 matches the CASSIE beautifier default (rdp_error=0.002)
        // with some extra margin for raw stroke density.
        {
            std::vector<float> fpts;
            fpts.reserve(kept.size() * 3);
            for (size_t k : kept) {
                fpts.push_back(static_cast<float>(src[3*k+0]));
                fpts.push_back(static_cast<float>(src[3*k+1]));
                fpts.push_back(static_cast<float>(src[3*k+2]));
            }
            const uint32_t n_in = static_cast<uint32_t>(kept.size());
            std::vector<uint32_t> keep_mask(n_in, 0u);
            const float rdp_tol = 0.002f;
            uint32_t n_kept = cassie_slang_dispatch::curve_rdp_reduce(
                fpts.data(), n_in, rdp_tol, keep_mask.data());
            if (n_kept >= 3 && n_kept < n_in) {
                std::vector<size_t> rdp_kept;
                rdp_kept.reserve(n_kept);
                for (uint32_t i = 0; i < n_in; ++i) {
                    if (keep_mask[i]) rdp_kept.push_back(kept[i]);
                }
                kept = std::move(rdp_kept);
            }
        }
        if (kept.size() < 3) {
            return lean_io_result_mk_ok(lean_box_usize(reinterpret_cast<size_t>(res)));
        }

        // Build flat boundary array (copy so Triangulate() can mutate if needed).
        std::vector<double> boundary;
        boundary.reserve(kept.size() * 3);
        for (size_t k : kept) {
            boundary.push_back(src[3*k+0]);
            boundary.push_back(src[3*k+1]);
            boundary.push_back(src[3*k+2]);
        }
        const int nB = static_cast<int>(kept.size());

        double *out_verts = nullptr;
        int    *out_faces = nullptr;
        int     nV = 0, nF = 0;

        // Signal-handler + terminate blocklist: DMWT can crash or abort on degenerate geometry.
        auto prev_segv  = signal(SIGSEGV, cdt_signal_handler);
        auto prev_fpe   = signal(SIGFPE,  cdt_signal_handler);
        auto prev_abrt  = signal(SIGABRT, cdt_signal_handler);
        auto prev_term  = std::set_terminate(cdt_terminate_handler);
        cdt_recovering = true;
        if (sigsetjmp(cdt_jmpbuf, 1) != 0) {
            cdt_recovering = false;
            signal(SIGSEGV, prev_segv); signal(SIGFPE, prev_fpe); signal(SIGABRT, prev_abrt);
            std::set_terminate(prev_term);
            res->verts.clear(); res->tris.clear();
            return lean_io_result_mk_ok(lean_box_usize(reinterpret_cast<size_t>(res)));
        }
        try {
            bool ok = Triangulate(boundary.data(), nB,
                                  static_cast<float>(target_edge_length),
                                  &out_verts, &out_faces, &nV, &nF);
            if (ok && nV > 0 && nF > 0) {
                res->verts.assign(out_verts, out_verts + nV * 3);
                res->tris.resize(static_cast<size_t>(nF) * 3);
                for (int i = 0; i < nF * 3; ++i)
                    res->tris[static_cast<size_t>(i)] = static_cast<uint32_t>(out_faces[i]);
            }
            CleanUp(&out_verts, &out_faces);
        } catch (...) {
            CleanUp(&out_verts, &out_faces);
            res->verts.clear(); res->tris.clear();
        }
        cdt_recovering = false;
        signal(SIGSEGV, prev_segv); signal(SIGFPE, prev_fpe); signal(SIGABRT, prev_abrt);
        std::set_terminate(prev_term);
    }
    // positions is @& (borrowed) — caller owns it, do NOT dec_ref here.
    return lean_io_result_mk_ok(lean_box_usize(reinterpret_cast<size_t>(res)));
}

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_free(
        size_t handle, lean_obj_arg /*world*/) {
    delete as_result(handle);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_n_vertices(
        size_t handle, lean_obj_arg /*world*/) {
    return lean_io_result_mk_ok(lean_box_usize(as_result(handle)->verts.size() / 3));
}

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_n_triangles(
        size_t handle, lean_obj_arg /*world*/) {
    return lean_io_result_mk_ok(lean_box_usize(as_result(handle)->tris.size() / 3));
}

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_get_positions(
        size_t handle, lean_obj_arg /*world*/) {
    const auto *res = as_result(handle);
    const size_t n_bytes = res->verts.size() * sizeof(double);
    lean_object *arr = lean_alloc_sarray(1, n_bytes, n_bytes);
    std::memcpy(lean_sarray_cptr(arr), res->verts.data(), n_bytes);
    return lean_io_result_mk_ok(arr);
}

LEAN_EXPORT lean_obj_res cassie_geogram_delaunay_get_triangles(
        size_t handle, lean_obj_arg /*world*/) {
    const auto *res = as_result(handle);
    const size_t n_bytes = res->tris.size() * sizeof(uint32_t);
    lean_object *arr = lean_alloc_sarray(1, n_bytes, n_bytes);
    std::memcpy(lean_sarray_cptr(arr), res->tris.data(), n_bytes);
    return lean_io_result_mk_ok(arr);
}

} // extern "C"
