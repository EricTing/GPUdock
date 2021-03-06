/*
#include <cmath>
#include <cstdlib>
#include <cstdio>

#include <cuda.h>

#include "dock.h"
#include "gpu.cuh"
*/

__forceinline__
__device__ void
Accept_d (const int bidx, Ligand * __restrict__ mylig, const float mybeta, const int myreplica)
{
  __shared__ int is_accept;

  if (bidx == 0) {    
#if IS_RANDOM == 0
      is_accept = 1;
#elif IS_RANDOM == 1
      const float delta_energy = mylig->energy_new.e[MAXWEI - 1] - mylig->energy_old.e[MAXWEI -1];
      is_accept = (MyRand_d () < expf (delta_energy * mybeta));  // mybeta is less than zero
#if IS_REVERSE == 1
      is_accept = (MyRand_d () < expf (- delta_energy * mybeta));
#endif
      // printf ("delta_energy: %.8f\n", delta_energy);
      // printf("is_accept: %d\n", is_accept);
      // printf("Myrand_d: %f\n", MyRand_d());
      // printf("prob: %.32f\n", expf (delta_energy * mybeta));
      // printf("mybeta: %.20f\n", mybeta);
#endif
    acs_mc_dc[myreplica] += is_accept;



    //printf ("beta[%d] = %f\n", myreplica, 1.0f / mybeta);


  }

  __syncthreads ();

  if (is_accept == 1) {
    if (bidx < 6)
      mylig->movematrix_old[bidx] = mylig->movematrix_new[bidx];
    if (bidx < MAXWEI)
      mylig->energy_old.e[bidx] = mylig->energy_new.e[bidx];
    if (bidx == 0)
	  mylig->energy_old.cmcc = mylig->energy_new.cmcc;
  }
}

 
