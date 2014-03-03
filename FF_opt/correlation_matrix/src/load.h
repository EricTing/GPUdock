#ifndef  LOAD_H
#define  LOAD_H

#include "dock.h"

void loadLigConf (LigandFile *);
void loadLigand (LigandFile *, Ligand0 *);

void loadPrtConf (ProteinFile *, Protein0 *);
void loadProtein (ProteinFile *, Protein0 *);

void loadLHM (LhmFile *, Psp0 *, Kde0 *, Mcs0 *);
void loadEnePara (EneParaFile *, EnePara0 *);

void loadWeight(WeightFile *, EnePara0 *);
void loadNorPara(NorParaFile *, EnePara0 *);  // load the normalization parameter a and b

void loadTrack(TrackFile *, float *);

#endif // LOAD_H
