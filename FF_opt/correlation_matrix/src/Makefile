EXE := corr_matx_gen
OBJ_CPU := dock.o load.o data.o rmsd.o util.o timing.o quicksort.o 
SRC_CPU = dock.C load.C data.C rmsd.f timing.C quicksort.C util.C

CPP := icpc
FC := gfortran

CONFIG = -openmp

OPTFLAGS := -O0
#OPTFLAGS := -O3

CPPFLAGS := $(CONFIG) $(OPTFLAGS) -Wall 
FFLAGS := $(OPTFLAGS) -Wall




default: $(EXE) 

$(EXE): $(OBJ_CPU)
	$(CPP) $(CONFIG) $(OBJ_CPU) -o $@
	@cp $(EXE) ../bin/
	@cp $(EXE) ~/bin/
	@cp $(EXE) ../test/
	@echo "cp $(EXE) ../bin/"
	@echo "cp $(EXE) ~/bin/"
	@echo "cp $(EXE) ../test/"

%.o: %.C
	$(CPP) $(CPPFLAGS) -c $<

%.o: %.f
	$(FC) $(FFLAGS) -c $<


clean:
	@(rm -f ${EXE} ${OBJ_CPU} ${OBJ_GPU} analysis count *i *cubin* *.ptx *cudafe* *.fatbin* *.hash count count.o ../bin/dock)
