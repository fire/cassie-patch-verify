
#pragma once
#ifdef _WIN32
#define DLL_IMPORT __declspec(dllexport)
#else
#define DLL_IMPORT
#endif
#include <iostream>
#include <Eigen/Core>

extern "C"
{

    DLL_IMPORT bool Triangulate(double* boundary, int nB, float targetEdgeLength, double** vertices, int** faces, int* nV, int* nF);

    DLL_IMPORT void CleanUp(double** vertices, int** faces);
}


int delaunayRestrictedTriangulation(const double* inCurve, const int inNum, double** outCurve,
    int* outPn, double** outFaces, int* outNum, float* weights,
    bool dosmooth, int subd, int laps, //
    Eigen::MatrixXd& V,                //
    Eigen::MatrixXi& F);