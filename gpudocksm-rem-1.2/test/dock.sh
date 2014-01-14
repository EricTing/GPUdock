#!/bin/sh
rm -rf output_*

# floor_temp
# lowest temp
# ceiling_temp
# highest temp
# num_temp
# total number of temperatures
# t
# translational scale
# r
# rotation scale


./dock -floor_temp 0.000032f -ceiling_temp 0.14f -nt 20 -t 0.01f -r 0.08f -ns 200000 -nc 10 -p 1a07C.pdb -l 1a07C1.sdf -s 1a07C1.ff -id 1a07C1 > report
