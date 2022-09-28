// block.cu
// Include file for chicken.
// PJ 2022-09-11

#ifndef BLOCK_INCLUDED
#define BLOCK_INCLUDED

#include <string>
#include <fstream>
#include <stdexcept>
#include "include/bxzstr/bxzstr.hpp"
#include "number.cu"
#include "vector3.cu"
#include "gas.cu"
#include "vertex.cu"
#include "flow.cu"
#include "face.cu"
#include "cell.cu"

using namespace std;

namespace BCCode {
    // Boundary condition codes, to decide what to do for the ghost cells.
    // Periodic boundary conditions should just work if we wrap the index in each direction.
    // There's not enough information here to have arbitrary block connections.
    constexpr int wall_with_slip = 0;
    constexpr int wall_no_slip = 1;
    constexpr int exchange = 2;
    constexpr int inflow = 3;
    constexpr int outflow = 4;

    vector<string> names{"wall_with_slip", "wall_no_slip", "exchange", "inflow", "outflow"};
};

int BC_code_from_name(string name)
{
    if (name == "wall_with_slip") return BCCode::wall_with_slip;
    if (name == "wall_no_slip") return BCCode::wall_no_slip;
    if (name == "exchange") return BCCode::exchange;
    if (name == "inflow") return BCCode::inflow;
    if (name == "outflow") return BCCode::outflow;
    return BCCode::wall_with_slip;
}

struct Block {
    int nic; // Number of cells i-direction.
    int njc; // Number of cells j-direction.
    int nkc; // Number of cells k-direction.
    int nActiveCells; // Number of active cells (with conserved quantities) in the block.
    // Ghost cells will be stored at the end of the active cells collection.
    int nGhostCells[6]; // Number of ghost cells on each face.
    int firstGhostCells[6]; // Index of the first ghost cell for each face.
    //
    vector<FVCell> cells;
    vector<FVFace> iFaces;
    vector<FVFace> jFaces;
    vector<FVFace> kFaces;
    vector<Vector3> vertices;
    //
    // Active cells have conserved quantities data, along with the time derivatives.
    vector<ConservedQuantities> Q;
    vector<ConservedQuantities> dQdt;
    //
    int bcCodes[6];

    __host__
    string toString() {
        string repr = "Block(nic=" + to_string(nic) +
            ", njc=" + to_string(njc) + ", nkc=" + to_string(nkc) + ")";
        return repr;
    }

    // Methods to index the elements making up the block.

    __host__ __device__
    int activeCellIndex(int i, int j, int k)
    {
        return k*nic*njc + j*nic + i;
    }

    __host__ __device__
    int ghostCellIndex(int faceIndx, int i0, int i1, int depth)
    {
        int cellIndxOnFace = 0;
        switch (faceIndx) {
        case Face::iminus:
        case Face::iplus:
            // jk face
            cellIndxOnFace = i1*njc + i0;
            break;
        case Face::jminus:
        case Face::jplus:
            // ik face
            cellIndxOnFace = i1*njc + i0;
            break;
        case Face::kminus:
        case Face::kplus:
            // ik face
            cellIndxOnFace = i1*njc + i0;
            break;
        }
        return firstGhostCells[faceIndx] + cellIndxOnFace;
    }

    __host__ __device__
    int iFaceIndx(int i, int j, int k)
    {
        return i*njc*nkc + k*njc + j;
    }

    __host__ __device__
    int jFaceIndx(int i, int j, int k)
    {
        return j*nic*nkc + k*nic + i;
    }

    __host__ __device__
    int kFaceIndx(int i, int j, int k)
    {
        return k*nic*njc + j*nic + i;
    }

    __host__ __device__
    int vtxIndx(int i, int j, int k)
    {
        return k*(nic+1)*(njc+1) + j*(nic+1) + i;
    }

    __host__
    void configure(int i, int j, int k, int codes[])
    // Set up the block to hold the grid and flow data.
    // Do this before reading a grid or flow file.
    {
        nic = i;
        njc = j;
        nkc = k;
        for (int b=0; b < 6; b++) { bcCodes[b] = codes[b]; }
        //
        int nActiveCells = nic*njc*nkc;
        // For the moment assume that all boundary conditions require ghost cells.
        nGhostCells[Face::iminus] = 2*njc*nkc;
        nGhostCells[Face::iplus] = 2*njc*nkc;
        nGhostCells[Face::jminus] = 2*nic*nkc;
        nGhostCells[Face::jplus] = 2*nic*nkc;
        nGhostCells[Face::kminus] = 2*nic*njc;
        nGhostCells[Face::kplus] = 2*nic*njc;
        firstGhostCells[0] = nActiveCells;
        for (int f=1; f < 6; f++) firstGhostCells[i] = firstGhostCells[i-1] + nGhostCells[i-1];
        // Now that we know the numbers of cells, resize the vector to fit them all.
        cells.resize(firstGhostCells[5]+nGhostCells[5]);
        // Each set of finite-volume faces is in the index-plane of the corresponding vertices.
        iFaces.resize((nic+1)*njc*nkc);
        jFaces.resize(nic*(njc+1)*nkc);
        kFaces.resize(nic*njc*(nkc+1));
        // And the vertices.
        vertices.resize((nic+1)*(njc+1)*(nkc+1));
        return;
    }

    __host__
    void readGrid(string fileName, bool vtkHeader=false)
    // Reads the vertex locations from a compressed file, resizing storage as needed.
    // The numbers of cells are also checked.
    {
        auto f = bxz::ifstream(fileName); // gzip file
        if (!f) {
            throw new runtime_error("Did not open grid file successfully: "+fileName);
        }
        constexpr int maxc = 256;
        char line[maxc];
        int niv, njv, nkv;
        if (vtkHeader) {
            f.getline(line, maxc); // expect "vtk"
            f.getline(line, maxc); // title line
            f.getline(line, maxc); // expect "ASCII"
            f.getline(line, maxc); // expect "STRUCTURED_GRID"
            f.getline(line, maxc); // DIMENSIONS line
            sscanf(line, "DIMENSIONS %d %d %d", &niv, &njv, &nkv);
        } else {
            f.getline(line, maxc); // expect "structured_grid 1.0"
            f.getline(line, maxc); // label:
            f.getline(line, maxc); // dimensions:
            f.getline(line, maxc);
            sscanf(line, "niv: %d", &niv);
            f.getline(line, maxc);
            sscanf(line, "njv: %d", &njv);
            f.getline(line, maxc);
            sscanf(line, "nkv: %d", &nkv);
        }
        if ((nic != niv-1) || (njc != njv-1) || (nkc != nkv-1)) {
            throw new runtime_error("Unexpected grid size: niv="+to_string(niv)+
                                    " njv="+to_string(njv)+
                                    " nkv="+to_string(nkv));
        }
        vertices.resize(niv*njv*nkv);
        //
        // Standard order of vertices.
        for (int k=0; k < nkv; k++) {
            for (int j=0; j < njv; j++) {
                for (int i=0; i < niv; i++) {
                    f.getline(line, maxc);
                    number x, y, z;
                    #ifdef FLOAT_NUMBERS
                    sscanf(line "%f %f %f", &x, &y, &z);
                    #else
                    sscanf(line, "%lf %lf %lf", &x, &y, &z);
                    #endif
                    vertices[vtxIndx(i,j,k)].set(x, y, z);
                } // for i
            } // for j
        } // for k
        f.close();
        return;
    } // end readGrid()

}; // end Block

#endif