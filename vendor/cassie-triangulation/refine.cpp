#include "refine.h"

#include <pmp/algorithms/remeshing.h>
#include <pmp/surface_mesh.h>

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

// ---------------------------------------------------------------------------
// full_write: write all bytes even if interrupted by signal.
// ---------------------------------------------------------------------------
static bool full_write(int fd, const void* buf, size_t n) {
    const char* p = static_cast<const char*>(buf);
    while (n > 0) {
        ssize_t r = write(fd, p, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        p += r; n -= static_cast<size_t>(r);
    }
    return true;
}

// full_read with 5-second wall-clock deadline (poll once per 100 ms).
static bool timed_read(int fd, void* buf, size_t n, int timeout_sec) {
    char* p = static_cast<char*>(buf);
    time_t deadline = time(nullptr) + timeout_sec;
    while (n > 0) {
        if (time(nullptr) >= deadline) return false;
        fd_set rset;
        FD_ZERO(&rset); FD_SET(fd, &rset);
        struct timeval tv = {0, 100000}; // 100 ms
        int sel = select(fd + 1, &rset, nullptr, nullptr, &tv);
        if (sel < 0 && errno == EINTR) continue;
        if (sel <= 0) continue;
        ssize_t r = read(fd, p, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        p += r; n -= static_cast<size_t>(r);
    }
    return true;
}

void refine_patch(const Eigen::MatrixXd& V, const Eigen::MatrixXi& F, float targetEdgeLength,
    Eigen::MatrixXd& V_fine, Eigen::MatrixXi& F_fine) {

    // targetEdgeLength <= 0 means "no remeshing" — return the raw DMWT mesh.
    if (targetEdgeLength <= 0.0f) {
        V_fine = V;
        F_fine = F;
        return;
    }

    // Build pmp::SurfaceMesh from V, F.
    pmp::SurfaceMesh mesh;
    std::vector<pmp::Vertex> vmap;
    vmap.reserve(V.rows());
    for (Eigen::Index i = 0; i < V.rows(); ++i) {
        vmap.push_back(mesh.add_vertex(pmp::Point(V(i, 0), V(i, 1), V(i, 2))));
    }
    for (Eigen::Index i = 0; i < F.rows(); ++i) {
        mesh.add_triangle(vmap[F(i, 0)], vmap[F(i, 1)], vmap[F(i, 2)]);
    }

    // Mark boundary as feature curve (preserves boundary shape during remeshing).
    auto efeature = mesh.add_edge_property<bool>("e:feature", false);
    auto vfeature = mesh.add_vertex_property<bool>("v:feature", false);
    for (auto e : mesh.edges()) {
        if (mesh.is_boundary(e)) {
            efeature[e] = true;
            vfeature[mesh.vertex(e, 0)] = true;
            vfeature[mesh.vertex(e, 1)] = true;
        }
    }

    const unsigned int nb_iter = 3;
    time_t t_fork_start = time(nullptr);

    // Run pmp::uniform_remeshing in a fork()ed child so that if it hangs
    // (kd-tree projection loops on near-degenerate DMWT output), the parent
    // can kill it and fall back to the raw DMWT mesh without heap corruption.
    // Result is piped back: [nV:int][nF:int][nV×3 doubles][nF×3 ints].
    int fds[2];
    if (pipe(fds) != 0) {
        V_fine.resize(0, 3); F_fine.resize(0, 3); return;
    }

    pid_t child = fork();
    if (child < 0) {
        close(fds[0]); close(fds[1]);
        V_fine.resize(0, 3); F_fine.resize(0, 3); return;
    }

    if (child == 0) {
        // --- Child process -------------------------------------------------
        // Reset inherited FFI signal handlers so pmp crashes terminate the
        // child normally (SIGABRT/SIGSEGV → default) rather than siglongjmp-ing
        // to a stack frame that no longer exists in the child.
        signal(SIGSEGV, SIG_DFL);
        signal(SIGFPE,  SIG_DFL);
        signal(SIGABRT, SIG_DFL);
        close(fds[0]);
        fprintf(stderr, "[child pid=%d] V=%d F=%d target=%.4f starting dump+remesh\n",
                (int)getpid(), (int)V.rows(), (int)F.rows(), (double)targetEdgeLength);

        // Dump input V,F to /tmp/refine_dump_NV_NF.bin for unit test capture.
        // Format: [nV:int][nF:int][nV*3 doubles][nF*3 ints]
        // Only dumps if the file doesn't already exist (first occurrence wins).
        {
            int nVin = static_cast<int>(V.rows());
            int nFin = static_cast<int>(F.rows());
            char path[256];
            snprintf(path, sizeof(path), "/tmp/refine_dump_%d_%d_pid%d.bin",
                     nVin, nFin, (int)getpid());
            int dfd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (dfd >= 0) {
                full_write(dfd, &nVin, sizeof(int));
                full_write(dfd, &nFin, sizeof(int));
                for (Eigen::Index i = 0; i < V.rows(); ++i) {
                    double d[3] = {V(i,0), V(i,1), V(i,2)};
                    full_write(dfd, d, sizeof(d));
                }
                for (Eigen::Index i = 0; i < F.rows(); ++i) {
                    int tri[3] = {F(i,0), F(i,1), F(i,2)};
                    full_write(dfd, tri, sizeof(tri));
                }
                close(dfd);
            }
        }

        pmp::uniform_remeshing(mesh, static_cast<pmp::Scalar>(targetEdgeLength),
                               nb_iter, /*use_projection=*/true);

        int nV = static_cast<int>(mesh.n_vertices());
        int nF = static_cast<int>(mesh.n_faces());
        full_write(fds[1], &nV, sizeof(int));
        full_write(fds[1], &nF, sizeof(int));

        // Vertices: flat x,y,z doubles.
        for (auto v : mesh.vertices()) {
            const pmp::Point& p = mesh.position(v);
            double d[3] = {static_cast<double>(p[0]),
                           static_cast<double>(p[1]),
                           static_cast<double>(p[2])};
            full_write(fds[1], d, sizeof(d));
        }

        // Faces: flat a,b,c ints (vertex indices, 0-based, dense).
        std::vector<int> vidx(static_cast<size_t>(nV));
        int vi = 0;
        for (auto v : mesh.vertices()) vidx[static_cast<size_t>(v.idx())] = vi++;
        for (auto f : mesh.faces()) {
            int tri[3]; int k = 0;
            for (auto v : mesh.vertices(f))
                tri[k++] = vidx[static_cast<size_t>(v.idx())];
            full_write(fds[1], tri, sizeof(tri));
        }

        close(fds[1]);
        _exit(0);
    }

    // --- Parent process ----------------------------------------------------
    close(fds[1]);

    const int TIMEOUT_SEC = 5;
    int nV = 0, nF = 0;
    bool ok = timed_read(fds[0], &nV, sizeof(int), TIMEOUT_SEC)
           && timed_read(fds[0], &nF, sizeof(int), TIMEOUT_SEC)
           && nV > 0 && nF > 0;

    if (ok) {
        V_fine.resize(nV, 3);
        F_fine.resize(nF, 3);
        for (int i = 0; i < nV && ok; ++i) {
            double d[3];
            ok = timed_read(fds[0], d, sizeof(d), TIMEOUT_SEC);
            if (ok) { V_fine(i,0)=d[0]; V_fine(i,1)=d[1]; V_fine(i,2)=d[2]; }
        }
        for (int i = 0; i < nF && ok; ++i) {
            int tri[3];
            ok = timed_read(fds[0], tri, sizeof(tri), TIMEOUT_SEC);
            if (ok) { F_fine(i,0)=tri[0]; F_fine(i,1)=tri[1]; F_fine(i,2)=tri[2]; }
        }
    }

    close(fds[0]);

    // Reap the child; kill it if it's still running (timed out).
    int status;
    pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == 0) {
        kill(child, SIGKILL);
        waitpid(child, &status, 0);
    }

    time_t elapsed = time(nullptr) - t_fork_start;
    if (!ok) {
        fprintf(stderr, "[refine TIMEOUT] V=%d F=%d elapsed=%lds\n",
                (int)V.rows(), (int)F.rows(), (long)elapsed);
        // Timed out or pipe error: report failure (empty mesh).
        // Callers check nV==0 and treat this patch as unresolved.
        V_fine.resize(0, 3);
        F_fine.resize(0, 3);
    } else {
        fprintf(stderr, "[refine done] V=%d F=%d → V=%d F=%d elapsed=%lds\n",
                (int)V.rows(), (int)F.rows(), nV, nF, (long)elapsed);
    }
}
