//#include <iostream>
#include <cstdlib>
#include <cstdio>
#include <cmath>

#include "dock.h"
#include "size.h"
#include "toggle.h"
#include "timing.h"
#include "hdf5io.h"

#include <cuda.h>
#include "gpu.cuh"
#include "util.h"
#include "size_gpu.cuh"

#include "include_cuda/cutil_inline.h"
#include "include_cuda/cutil_yeah.h"

// inline everything in order to use constant memory
#include "gpu.cu"




#if 1
// parameters for reading HD5 file

//const int myreplica = 0;
//const int repp_begin = 70;
//const int repp_end = 90;
const int iter_begin = 0;
const int iter_end = minimal_int (STEPS_PER_DUMP, 20) - 1;
const int arg = 2;
#endif




void
Run (const Ligand * lig,
     const Protein * prt,
     const Psp * psp,
     const Kde * kde,
     const Mcs * mcs,
     const EnePara * enepara,
     const Temp * temp,
     const Replica * replica,
     const McPara * mcpara,
     McLog * mclog,
     const ComplexSize complexsize)
{
  // sizes
  const int n_lig = complexsize.n_lig;
  const int n_prt = complexsize.n_prt;
  const int n_tmp = complexsize.n_tmp;
  const int n_rep = complexsize.n_rep;
  const int n_pos = complexsize.n_pos;



  // set up kernel parameters
  const int dim_grid = GD;
  const dim3 dim_block (BDx, BDy, 1);



  // initilize random sequence
  srand (time (NULL));
  curandState *curandstate_d[NGPU];
  size_t curandstate_sz = sizeof (curandState) * TperB * GD;

  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    int myrand = rand () + i;
    CUDAMEMCPYTOSYMBOL (seed_dc, &myrand, int);

    cudaMalloc ((void **) &curandstate_d[i], curandstate_sz);
    CUDAMEMCPYTOSYMBOL (curandstate_dc, &curandstate_d[i], curandState*);
    CUDAKERNEL (InitCurand_d, dim_grid, dim_block);
  }




  //int ngpu = 0;
  //cudaGetDeviceCount (&ngpu);

  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    cudaFuncSetCacheConfig (MonteCarlo_Init_d, cudaFuncCachePreferShared);
    cudaFuncSetCacheConfig (MonteCarlo_d, cudaFuncCachePreferShared);
    cudaFuncSetCacheConfig (ExchangeReplicas_d, cudaFuncCachePreferShared);
  }


  // calculate the upper/lower bound for multi-GPU data decomposition
  const int n_rep_per_gpu_max = (int) ceilf ((float) (n_prt * n_tmp) / NGPU) * n_lig;
  const int n_active_gpu = (int) ceilf ((float) n_rep / n_rep_per_gpu_max);
  if (n_active_gpu < NGPU) {
    fprintf (stderr, "error: n_active_gpu < NGPU");
    exit (9999);
  }

  int rep_begin[NGPU], rep_end[NGPU], n_rep_per_gpu[NGPU];
  for (int i = 0; i < NGPU; ++i) {
    rep_begin[i] = n_rep_per_gpu_max * i;
    rep_end[i] = minimal_int (rep_begin[i] + n_rep_per_gpu_max - 1, n_rep);
    n_rep_per_gpu[i] = rep_end[i] - rep_begin[i] + 1;
  }




  // GPU read only scalars
  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    CUDAMEMCPYTOSYMBOL (steps_total_dc, &mcpara->steps_total, int);
    CUDAMEMCPYTOSYMBOL (steps_per_dump_dc, &mcpara->steps_per_dump, int);
    CUDAMEMCPYTOSYMBOL (steps_per_exchange_dc, &mcpara->steps_per_exchange, int);
    CUDAMEMCPYTOSYMBOL (is_random_dc, &mcpara->is_random, int);

    CUDAMEMCPYTOSYMBOL (enepara_lj0_dc, &enepara->lj0, float);
    CUDAMEMCPYTOSYMBOL (enepara_lj1_dc, &enepara->lj1, float);
    CUDAMEMCPYTOSYMBOL (enepara_el0_dc, &enepara->el0, float);
    CUDAMEMCPYTOSYMBOL (enepara_el1_dc, &enepara->el1, float);
    CUDAMEMCPYTOSYMBOL (enepara_a1_dc, &enepara->a1, float);
    CUDAMEMCPYTOSYMBOL (enepara_b1_dc, &enepara->b1, float);
    CUDAMEMCPYTOSYMBOL (enepara_kde2_dc, &enepara->kde2, float);
    CUDAMEMCPYTOSYMBOL (enepara_kde3_dc, &enepara->kde3, float);

    CUDAMEMCPYTOSYMBOL (lna_dc, &lig[0].lna, int);
    CUDAMEMCPYTOSYMBOL (pnp_dc, &prt[0].pnp, int);
    CUDAMEMCPYTOSYMBOL (pnk_dc, &kde->pnk, int);
    CUDAMEMCPYTOSYMBOL (n_pos_dc, &n_pos, int);
    CUDAMEMCPYTOSYMBOL (n_lig_dc, &n_lig, int);
    CUDAMEMCPYTOSYMBOL (n_prt_dc, &n_prt, int);
    CUDAMEMCPYTOSYMBOL (n_tmp_dc, &n_tmp, int);
    CUDAMEMCPYTOSYMBOL (n_rep_dc, &n_rep, int);
  }



  // GPU read only arrays
  const size_t prt_sz = sizeof (Protein) * n_prt;
  const size_t psp_sz = sizeof (Psp);
  const size_t kde_sz = sizeof (Kde);
  const size_t mcs_sz = sizeof (Mcs) * n_pos;
  const size_t enepara_sz = sizeof (EnePara);
  const size_t temp_sz = sizeof (Temp) * n_tmp;
  const size_t move_scale_sz = sizeof (float) * 6;

  Protein *prt_d[NGPU];
  Psp *psp_d[NGPU];
  Kde *kde_d[NGPU];
  Mcs *mcs_d[NGPU];
  EnePara *enepara_d[NGPU];
  Temp *temp_d[NGPU];
  float *move_scale_d[NGPU];

  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    cudaMalloc ((void **) &prt_d[i], prt_sz);
    cudaMalloc ((void **) &psp_d[i], psp_sz);
    cudaMalloc ((void **) &kde_d[i], kde_sz);
    cudaMalloc ((void **) &mcs_d[i], mcs_sz);
    cudaMalloc ((void **) &enepara_d[i], enepara_sz);
    cudaMalloc ((void **) &temp_d[i], temp_sz);
    cudaMalloc ((void **) &move_scale_d[i], move_scale_sz);

    CUDAMEMCPYTOSYMBOL (prt_dc, &prt_d[i], Protein *);
    CUDAMEMCPYTOSYMBOL (psp_dc, &psp_d[i], Psp *);
    CUDAMEMCPYTOSYMBOL (kde_dc, &kde_d[i], Kde *);
    CUDAMEMCPYTOSYMBOL (mcs_dc, &mcs_d[i], Mcs *);
    CUDAMEMCPYTOSYMBOL (enepara_dc, &enepara_d[i], EnePara *);
    CUDAMEMCPYTOSYMBOL (temp_dc, &temp_d[i], Temp *);
    CUDAMEMCPYTOSYMBOL (move_scale_dc, &move_scale_d[i], float *);

    CUDAMEMCPY (prt_d[i], prt, prt_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (psp_d[i], psp, psp_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (kde_d[i], kde, kde_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (mcs_d[i], mcs, mcs_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (enepara_d[i], enepara, enepara_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (temp_d[i], temp, temp_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (move_scale_d[i], &mcpara->move_scale, move_scale_sz, cudaMemcpyHostToDevice);
  }




  // GPU writable arrays that duplicate on multiple GPUs
  const size_t lig_sz = sizeof (Ligand) * n_rep;
  const size_t replica_sz = sizeof (Replica) * n_rep;
  const size_t etotal_sz = sizeof (float) * n_rep;
  const size_t ligmovevector_sz = sizeof (LigMoveVector) * n_rep;
  const size_t tmpenergy_sz = sizeof (TmpEnergy) * n_rep;
  const size_t acs_sz = sizeof (int) * MAXREP; // acceptance counter
  //size_t etotal_sz_per_gpu[NGPU];
  //for (int i = 0; i < NGPU; ++i)
  //etotal_sz_per_gpu[i] = sizeof (float) * n_rep_per_gpu[i];

  Ligand *lig_d[NGPU];
  Replica *replica_d[NGPU];
  float *etotal_d[NGPU];
  LigMoveVector *ligmovevector_d[NGPU];
  TmpEnergy *tmpenergy_d[NGPU];
  int *acs, *acs_d[NGPU];

  acs = (int *) malloc (acs_sz);

  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    cudaMalloc ((void **) &lig_d[i], lig_sz);
    cudaMalloc ((void **) &replica_d[i], replica_sz);
    cudaMalloc ((void **) &etotal_d[i], etotal_sz);
    cudaMalloc ((void **) &ligmovevector_d[i], ligmovevector_sz);
    cudaMalloc ((void **) &tmpenergy_d[i], tmpenergy_sz);
    cudaMalloc ((void **) &acs_d[i], acs_sz);

    CUDAMEMCPYTOSYMBOL (lig_dc, &lig_d[i], Ligand *);
    CUDAMEMCPYTOSYMBOL (replica_dc, &replica_d[i], Replica *);
    CUDAMEMCPYTOSYMBOL (etotal_dc, &etotal_d[i], float *);
    CUDAMEMCPYTOSYMBOL (ligmovevector_dc, &ligmovevector_d[i], LigMoveVector *);
    CUDAMEMCPYTOSYMBOL (tmpenergy_dc, &tmpenergy_d[i], TmpEnergy *);
    CUDAMEMCPYTOSYMBOL (acs_dc, &acs_d[i], int *);

    CUDAMEMCPY (lig_d[i], lig, lig_sz, cudaMemcpyHostToDevice);
    CUDAMEMCPY (replica_d[i], replica, replica_sz, cudaMemcpyHostToDevice);
  }




  // GPU writable arrays that spreads over multiple GPUs

  // ligrecord[n_rep]
  LigRecord *ligrecord, *ligrecord_d[NGPU];
  const size_t ligrecord_sz = sizeof (LigRecord) * n_rep;
  size_t ligrecord_sz_per_gpu[NGPU];
  for (int i = 0; i < NGPU; ++i)
    ligrecord_sz_per_gpu[i] = sizeof (LigRecord) * n_rep_per_gpu[i];

  ligrecord = (LigRecord *) malloc (ligrecord_sz);
  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    cudaMalloc ((void **) &ligrecord_d[i], ligrecord_sz_per_gpu[i]);
    CUDAMEMCPYTOSYMBOL (ligrecord_dc, &ligrecord_d[i], LigRecord *);
  }


  /*
  // debug
  for (int i = 0; i < NGPU; ++i) {
    printf ("rep_begin[%d] = %d\n", i, rep_begin[i]);
    printf ("rep_end[%d] = %d\n", i, rep_end[i]);
  }
  */

  for (int i = 0; i < NGPU; ++i) {
    cudaGetLastError ();
  }




  // launch GPU kernels

#include "gpusingle.cu"
  //#include "gpumulti.cu"






  // calcuate acceptance counters
  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);
    CUDAMEMCPY (acs, acs_d[i], acs_sz, cudaMemcpyDeviceToHost);
    for (int j = 0; j < MAXREP; ++j) {
      mclog->acs[j] += acs[j];
    }
  }
  for (int j = 0; j < MAXREP; ++j) {
    mclog->ac += mclog->acs[j];
  }





  // free memories
  for (int i = 0; i < NGPU; ++i) {
    cudaSetDevice (i);

    cudaFree (curandstate_d[i]);

    cudaFree (prt_d[i]);
    cudaFree (psp_d[i]);
    cudaFree (kde_d[i]);
    cudaFree (mcs_d[i]);
    cudaFree (enepara_d[i]);
    cudaFree (temp_d[i]);
    cudaFree (move_scale_d[i]);

    cudaFree (lig_d[i]);
    cudaFree (replica_d[i]);
    cudaFree (etotal_d[i]);
    cudaFree (ligmovevector_d[i]);
    cudaFree (tmpenergy_d[i]);
    cudaFree (acs_d[i]);

    cudaFree (ligrecord_d[i]);
  }

  free (acs);
  free (ligrecord);


// read outputfiles and print something
#if 1
#if IS_OUTPUT == 1
  char myoutputfile[MAXSTRINGLENG];
  sprintf(myoutputfile, "%s/%s_%04d.h5", mcpara->outputdir, mcpara->outputfile, 0);
  LigRecord *ligrecord2;
  ligrecord2 = (LigRecord *) malloc (ligrecord_sz);
  putchar ('\n');

  ReadLigRecord (ligrecord2, n_rep, myoutputfile);
  //PrintLigRecord (ligrecord2, mcpara->steps_per_dump, myreplica, iter_begin, iter_end, arg);
  //PrintMoveRecord (ligrecord2, mcpara->steps_per_dump, myreplica, iter_begin, iter_end, arg);
  //PrintRepRecord (ligrecord2, mcpara->steps_per_dump, repp_begin, repp_end, iter_begin, iter_end, arg);
  PrintRepRecord2 (ligrecord2, complexsize, STEPS_PER_DUMP, 1, 1, iter_begin, iter_end, arg);

  free (ligrecord2);
#endif
#endif

}

