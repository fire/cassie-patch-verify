#include "Triangulation.h"

#include "Algorithm/DMWT.h"
#include "DataStructure/MingCurve.h"
#include "refine.h"

#include "Utility/Point3.h"

#include <cmath>
#include <mutex>

bool Triangulate(double* boundary, int nB, float targetEdgeLength, double** vertices, int** faces, int* nV, int* nF)
{
    // Serialize concurrent callers. The library uses process-global
    // state in several places that aren't thread-safe individually:
    //   * Geogram's Numeric::random_engine (file-scope static
    //     std::mt19937_64 with no protection)
    //   * pmp's SurfaceMesh property store (per-instance but the
    //     instance is constructed inside refine_patch each call)
    //   * Eigen's parallel solver in pmp::implicit_smoothing
    // Concurrent calls trigger Windows STATUS_HEAP_CORRUPTION
    // (0xc0000374) intermittently. A coarse mutex is the safe fix
    // until each upstream is hardened; per-call latency is ~1.6ms,
    // so even at 60fps the serialised throughput ceiling (~600
    // calls/sec) is well above what any CASSIE caller does.
    static std::mutex triangulate_mu;
    std::lock_guard<std::mutex> lock(triangulate_mu);

    // MingCurve's edge-protection retry loop calls Point3::pertube()
    // on degenerate inputs (e.g. coplanar polygons). pertube() uses
    // a thread-local std::mt19937; reset it here so consecutive
    // Triangulate calls on the same input take the same perturbation
    // path and produce the same mesh. Paired with the Geogram RNG
    // reset inside DelaunayFaces::compute().
    reset_perturb_rng(0u);

    // nB=3 special case: DMWT's edge-protection step relies on a
    // 3D Delaunay tetrahedralization to verify the input curve is
    // "protected", which needs 4+ points. A 3-vertex polygon IS a
    // single triangle -- there's nothing to triangulate, just
    // (optionally) refine. Bypass DMWT and feed the triangle
    // straight into refine_patch.
    if (nB == 3) {
        // Reject degenerate triangles (collinear, coincident, or
        // near-zero area). pmp's remeshing / heat method don't
        // cope gracefully -- they crash inside Eigen's solver --
        // and downstream callers can't do anything useful with a
        // zero-area input anyway.
        const double ax = boundary[0], ay = boundary[1], az = boundary[2];
        const double bx = boundary[3], by = boundary[4], bz = boundary[5];
        const double cx = boundary[6], cy = boundary[7], cz = boundary[8];
        const double e1x = bx-ax, e1y = by-ay, e1z = bz-az;
        const double e2x = cx-ax, e2y = cy-ay, e2z = cz-az;
        const double nx = e1y*e2z - e1z*e2y;
        const double ny = e1z*e2x - e1x*e2z;
        const double nz = e1x*e2y - e1y*e2x;
        const double area = 0.5 * std::sqrt(nx*nx + ny*ny + nz*nz);
        if (area < 1e-9) {
            *nF = 0; *nV = 0;
            *vertices = new double[0];
            *faces = new int[0];
            return false;
        }
        Eigen::MatrixXd V_in(3, 3);
        Eigen::MatrixXi F_in(1, 3);
        for (int i = 0; i < 3; ++i) {
            V_in(i, 0) = boundary[3*i + 0];
            V_in(i, 1) = boundary[3*i + 1];
            V_in(i, 2) = boundary[3*i + 2];
            F_in(0, i) = i;
        }
        Eigen::MatrixXd V_fine;
        Eigen::MatrixXi F_fine;
        refine_patch(V_in, F_in, targetEdgeLength, V_fine, F_fine);
        *nV = int(V_fine.rows());
        *nF = int(F_fine.rows());
        *vertices = new double[3 * (*nV)];
        *faces = new int[3 * (*nF)];
        for (int i = 0; i < *nV; ++i) {
            (*vertices)[3*i + 0] = V_fine(i, 0);
            (*vertices)[3*i + 1] = V_fine(i, 1);
            (*vertices)[3*i + 2] = V_fine(i, 2);
        }
        for (int i = 0; i < *nF; ++i) {
            (*faces)[3*i + 0] = F_fine(i, 0);
            (*faces)[3*i + 1] = F_fine(i, 1);
            (*faces)[3*i + 2] = F_fine(i, 2);
        }
        return true;
    }

    int point_num = nB;

    //for (int i = 0; i < point_num; i++) {
    //    std::cout << "vertex " << i << std::endl;
    //    std::cout << boundary[i * 3 + 0] << std::endl;
    //    std::cout << boundary[i * 3 + 1] << std::endl;
    //    std::cout << boundary[i * 3 + 2] << std::endl;
    //}

    double* newPoints;
    int newPointNum;
    double* tile_list;
    int tileNum;

    Eigen::MatrixXd V;
    Eigen::MatrixXi F;

    float m_weightTri = 0;
    float m_weightEdge = 0;
    float m_weightBiTri = 1;
    float m_weightTriBd = 1;
    float m_weightWorsDih = 0;

    float weights[] = { float(m_weightTri), float(m_weightEdge), float(m_weightBiTri), float(m_weightTriBd),
                    float(m_weightWorsDih) };

    //int res = delaunayRestrictedTriangulation(boundary, point_num, &newPoints, &newPointNum, &tile_list, &tileNum, weights, false, 0, 0);

    int res = delaunayRestrictedTriangulation(boundary, point_num, &newPoints, &newPointNum, &tile_list, &tileNum, weights, false, 0, 0, V, F);


    if (res == 0)
    {
        // Error case
        // Initialize arrays to empties to avoid crash
        *nF = 0;
        *nV = 0;
        *vertices = new double[0];
        *faces = new int[0];
        return false;
    }

    else
    {
        // Delete unmanaged arrays (they are useless now that we got the matrices anyway)
        delete[] newPoints;
        delete[] tile_list;

        Eigen::MatrixXd V_fine;
        Eigen::MatrixXi F_fine;

        refine_patch(V, F, targetEdgeLength, V_fine, F_fine);

        double* newVertices = new double[V_fine.size()];
        int* newFaces = new int[F_fine.size()];
        
        *nF = F_fine.rows();
        *nV = V_fine.rows();


        for (int i = 0; i < *nV; i++)
        {
            newVertices[3 * i + 0] = V_fine(i, 0);
            newVertices[3 * i + 1] = V_fine(i, 1);
            newVertices[3 * i + 2] = V_fine(i, 2);
        }

        for (int i = 0; i < *nF; i++)
        {
            newFaces[3 * i + 0] = F_fine(i, 0);
            newFaces[3 * i + 1] = F_fine(i, 1);
            newFaces[3 * i + 2] = F_fine(i, 2);
        }

        *vertices = newVertices;
        *faces = newFaces;

        return true;
    }


    //for (int i = 0; i < tileNum * 3 * 3; i++)
    //{
    //    vertices[i] = tile_list[i];
    //}

    //faces = new int[0];

    //vertices = tile_list;
    //*nF = tileNum;

	//return true;
}

void CleanUp(double** vertices, int** faces)
{
    // delete[] of a null pointer is well-defined, but dereferencing
    // a null outer pointer is not. Null-check both outers so a
    // caller that forgot to declare an output variable, or that
    // passes the same arguments twice, doesn't crash. After delete,
    // zero the inner pointers so a second CleanUp on the same args
    // is a no-op rather than a double-free.
    if (vertices) {
        delete[] *vertices;
        *vertices = nullptr;
    }
    if (faces) {
        delete[] *faces;
        *faces = nullptr;
    }
}


// Adaptation of Ming Zou's code
int delaunayRestrictedTriangulation(const double* inCurve, const int inNum, double** outCurve,
    int* outPn, double** outFaces, int* outNum, float* weights,
    bool dosmooth, int subd, int laps, //
    Eigen::MatrixXd& V,                //
    Eigen::MatrixXi& F) {

    bool withNorm = false;

    bool isdmwt = true, ismwt = false, isliepa = false, isdot1 = false;
    float weightTri = weights[0];
    float weightEdge = weights[1];
    float weightBiTri = weights[2];
    float weightTriBd = weights[3];
    float weightWorst = weights[4];
    int limit = 1000000;

    try {
        MingCurve* myCurve = new MingCurve(inCurve, inNum, limit, withNorm);
        if (!myCurve->edgeProtect(isdmwt)) {
            delete myCurve;
            cout << "MWT: (0) bad input, not able to protect curve" << endl;
            return 0; // (0) bad input, not able to protect curve
        }
        // myCurve->statistics();
        int ptn = myCurve->getNumOfPoints();
        double* pts = myCurve->getPoints();
        double* deGenPts = myCurve->getDeGenPoints();
        //float* norms = myCurve->getNormal();

        float* newNms;

        if (isdmwt) {
            DMWT* myDMWT = new DMWT(ptn, pts, deGenPts, myCurve->isDeGen);
            myDMWT->setWeights(weightTri, weightEdge, weightBiTri, weightTriBd, weightWorst);
            myDMWT->setDot(isdot1);
            myDMWT->preprocess();
            if (!myDMWT->start()) {
                delete myDMWT;
                delete myCurve;
                cout << "MWT: (0) no solution case" << endl;
                return 0; // (0) no solution case
            }
            myDMWT->getResult(outFaces, outNum, outCurve, &newNms, outPn, dosmooth, subd, laps);
            myDMWT->getResultAsMatrices(V, F);
            delete myDMWT;
        }

        delete myCurve;
    }
    catch (int e) {
        cout << "MWT: Unknown Error!! Exception Nr. " << e << endl;
        return 0; // (0) unknown error
    }
    return 1; // (1) correct results
}