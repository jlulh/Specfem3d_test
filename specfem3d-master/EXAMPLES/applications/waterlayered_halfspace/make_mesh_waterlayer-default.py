#!/usr/bin/env python
###########################################################################
#### TNM: This is the mesh generation, adapted from a journal file
####      specific to the settings of Komatitsch and Tromp 1999, Fig.8
####      Aug 2009
###########################################################################
#
# modified version: top layer is water
#
###########################################################################
from __future__ import print_function

import os
import sys

# checks for path for modules
found_lib = False
for path in sys.path:
    if "geocubitlib" in path:
        found_lib = True
        break
if not found_lib:
    sys.path.append('../../../CUBIT_GEOCUBIT/geocubitlib')
    sys.path.append('../../../CUBIT_GEOCUBIT/')
#print("path:")
#for path in sys.path: print("  ",path)
#print("")

## choose your size
# hi-resolution
#elementsize = 1196.4

# mid-resolution
#elementsize = 1500.0

# low-resolution
elementsize = 3000.0

# default directories
SEMoutput='MESH'
CUBIToutput='MESH_GEOCUBIT'

os.system('mkdir -p '+ SEMoutput)
os.system('mkdir -p '+ CUBIToutput)

import cubit
try:
    #cubit.init([""])
    cubit.init(["-noecho","-nojournal"])
except:
    pass

version = cubit.get_version()
version_major = int(version.split(".")[0])
version_minor = int(version.split(".")[1])
print("cubit version: ",version)

cubit.cmd('reset')
cubit.cmd('brick x 134000 y 134000 z 60000')

# This seems to conflict with boundary_definition.py
# ....which leaves the model space at e.g. x=[-67,67] km
cubit.cmd('volume 1 move x 67000 y 67000 z -30000')

# create vertices for discontinuity
cubit.cmd('split curve 9  distance 3000')
cubit.cmd('split curve 10  distance 3000')
cubit.cmd('split curve 11  distance 3000')
cubit.cmd('split curve 12  distance 3000')

# create surface for interface
cubit.cmd('create surface vertex 9 10 12 11')

cubit.cmd('section volume 1 with surface 7 keep normal')
cubit.cmd('section volume 1 with surface 7 reverse')

# create vertices for auxiliary interface to allow for refinement
cubit.cmd('split curve 29  distance 9000')
cubit.cmd('split curve 31  distance 9000')
cubit.cmd('split curve 32  distance 9000')
cubit.cmd('split curve 36  distance 9000')

# create surface for buffer interface to refine BELOW the discontinuity
cubit.cmd('create surface vertex 25 26 28 27')

cubit.cmd('section volume 3 with surface 19 keep normal')
cubit.cmd('section volume 3 with surface 19 reverse')

cubit.cmd('delete volume 2 4')

cubit.cmd('imprint all')
cubit.cmd('merge all')

# Meshing the volumes
cubit.cmd('volume 3 size '+str(elementsize))
cubit.cmd('mesh volume 3')

#cubit.cmd('refine surface 8 numsplit 1 bias 1.0 depth 1')
cubit.cmd('volume 1 size '+str(elementsize))
cubit.cmd('mesh volume 1')

cubit.cmd('volume 5 size '+str(elementsize))
cubit.cmd('mesh volume 5')

#### End of meshing

## obsolete:
#import boundary_definition
#import cubit2specfem3d
## new:
from geocubitlib import boundary_definition
from geocubitlib import cubit2specfem3d

###### This is boundary_definition.py of GEOCUBIT
#..... which extracts the bounding faces and defines them into blocks
print('#### DEFINE BC #######################')
boundary_definition.entities=['face']
boundary_definition.define_bc(boundary_definition.entities,parallel=True)

#### Define material properties for the 3 volumes ################
print('#### DEFINE MATERIAL PROPERTIES #######################')
cubit.cmd('block 1 name "acoustic 1" ')       # acoustic material region
cubit.cmd('block 1 attribute count 4')
cubit.cmd('block 1 attribute index 1 1  ')     # material 1
cubit.cmd('block 1 attribute index 2 1480 ')  # vp
cubit.cmd('block 1 attribute index 3 0 ')      # vs
cubit.cmd('block 1 attribute index 4 1028 ')  # rho (ocean salt water density:
                                         # http://www.windows.ucar.edu/tour/link=/earth/Water/density.html

cubit.cmd('block 2 name "elastic 1" ')        # elastic material region
cubit.cmd('block 2 attribute count 7')
cubit.cmd('block 2 attribute index 1 2  ')     # material 2
cubit.cmd('block 2 attribute index 2 7500 ')  # vp
cubit.cmd('block 2 attribute index 3 4300 ')  # vs
cubit.cmd('block 2 attribute index 4 3200 ')  # rho
cubit.cmd('block 2 attribute index 5 9999.0')      # Q_kappa
cubit.cmd('block 2 attribute index 6 9999.0')      # Q_mu
cubit.cmd('block 2 attribute index 7 0 ')     # anisotropy_flag

cubit.cmd('block 3 name "elastic 2" ')        # elastic material region
cubit.cmd('block 3 attribute count 7')
cubit.cmd('block 3 attribute index 1 3  ')     # same properties as material 2
cubit.cmd('block 3 attribute index 2 7500 ')  # vp
cubit.cmd('block 3 attribute index 3 4300 ')  # vs
cubit.cmd('block 3 attribute index 4 3200 ')  # rho
cubit.cmd('block 3 attribute index 5 9999.0')      # Q_kappa
cubit.cmd('block 3 attribute index 6 9999.0')      # Q_mu
cubit.cmd('block 3 attribute index 7 0 ')     # anisotropy_flag

cubit.cmd('export mesh "' + CUBIToutput + '/top.e" dimension 3 overwrite')
cubit.cmd('save as "' + CUBIToutput + '/top.cub" overwrite')

#### Export to SPECFEM3D format using cubit2specfem3d.py of GEOCUBIT

cubit2specfem3d.export2SPECFEM3D(SEMoutput)

# screen shot
# (could crash version < 16.4)
if version_major >= 16 and version_minor >= 4:
    cubit.cmd('view top')
    cubit.cmd('hardcopy "' + CUBIToutput + '/waterlayered.png" png')

# all files needed by SCOTCH are now in directory MESH




