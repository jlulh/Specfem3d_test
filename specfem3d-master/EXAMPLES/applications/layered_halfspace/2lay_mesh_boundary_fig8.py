#!/usr/bin/env python
##!python
##!/usr/bin/python
###########################################################################
#### TNM: This is the mesh generation, adapted from a journal file
####      specific to the settings of Komatitsch and Tromp 1999, Fig.8
####      Aug 2009
###########################################################################
from __future__ import print_function

import os
import sys

# checks path for GEOCUBIT modules
found_lib = False
for path in sys.path:
    if "geocubitlib" in path:
        found_lib = True
        break
if not found_lib:
    sys.path.append('../../../CUBIT_GEOCUBIT/geocubitlib')
    sys.path.append('../../../CUBIT_GEOCUBIT')
print("path:")
for path in sys.path: print("  ",path)
print("")

# current working directory
print("current dir: ",os.getcwd())

# default directories
SEMoutput='MESH'
CUBIToutput='MESH_GEOCUBIT'

os.system('mkdir -p '+ SEMoutput)
os.system('mkdir -p '+ CUBIToutput)

## obsolete:
#import boundary_definition
#import cubit2specfem3d
## new:
from geocubitlib import boundary_definition
from geocubitlib import cubit2specfem3d

## CUBIT/Trelis
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
distance = 3000
cubit.cmd('split curve 9  distance '+str(distance))
cubit.cmd('split curve 10  distance '+str(distance))
cubit.cmd('split curve 11  distance '+str(distance))
cubit.cmd('split curve 12  distance '+str(distance))

# create surface for interface
# surface at 3 km depth
cubit.cmd('create surface vertex 9 10 12 11')

cubit.cmd('section volume 1 with surface 7 keep normal')
cubit.cmd('section volume 1 with surface 7 reverse')

# create vertices for auxiliary interface
# source will be at 25050 m depth as in Komatitsch et al. (1999); placing this auxiliary surface at 22050 will create a mesh
# such that point force source can be located exactly on a GLL point at that depth.
distance = 22050
cubit.cmd('split curve 29  distance '+str(distance))
cubit.cmd('split curve 31  distance '+str(distance))
cubit.cmd('split curve 32  distance '+str(distance))
cubit.cmd('split curve 36  distance '+str(distance))


# create surface for buffer interface to refine BELOW the discontinuity
# surface at 3 km depth
cubit.cmd('create surface vertex 25 26 28 27')

cubit.cmd('section volume 3 with surface 19 keep normal')
cubit.cmd('section volume 3 with surface 19 reverse')

cubit.cmd('delete volume 2 4')

cubit.cmd('imprint all')
cubit.cmd('merge all')

# Meshing the volumes
## middle volume
#cubit.cmd('volume 3 size 3589.2')
cubit.cmd('volume 3 size 4500.')
cubit.cmd('mesh volume 3')

# refine boundary surface between top and middle volume
# this will create a tripling layer from the bottom to the top in the middle volume
cubit.cmd('refine surface 8 numsplit 1 bias 1.0 depth 1')

#cubit.cmd('pause')

## top volume
#cubit.cmd('volume 1 size 1196.4')
cubit.cmd('volume 1 size 1000.0')
cubit.cmd('mesh volume 1')

#cubit.cmd('pause')

## bottom volume
#cubit.cmd('volume 5 size 4785.71')
cubit.cmd('volume 5 size 4500.')
cubit.cmd('mesh volume 5')

# draw/update mesh lines for visualization
# this will draw also the tripling layer mesh lines
cubit.cmd('draw volume all')

#### End of meshing

###### This is boundary_definition.py of GEOCUBIT
#..... which extracts the bounding faces and defines them into blocks
print('#### DEFINE BC #######################')
boundary_definition.entities=['face']
boundary_definition.define_bc(boundary_definition.entities,parallel=True)

#### Define material properties for the 3 volumes ################
print('#### DEFINE MATERIAL PROPERTIES #######################')
cubit.cmd('block 1 name "elastic 1" ')        # elastic material region
cubit.cmd('block 1 attribute count 6')
cubit.cmd('block 1 attribute index 1 1  ')      # volume 1
cubit.cmd('block 1 attribute index 2 2800 ')   # vp
cubit.cmd('block 1 attribute index 3 1500 ')   # vs
cubit.cmd('block 1 attribute index 4 2300 ')   # rho
cubit.cmd('block 1 attribute index 5 9000.0 ')       # Q_mu
cubit.cmd('block 1 attribute index 6 0 ')     # anisotropy_flag

cubit.cmd('block 2 name "elastic 2" ')        # elastic material region
cubit.cmd('block 2 attribute count 6')
cubit.cmd('block 2 attribute index 1 2  ')      # volume 2
cubit.cmd('block 2 attribute index 2 7500 ')
cubit.cmd('block 2 attribute index 3 4300 ')
cubit.cmd('block 2 attribute index 4 3200 ')
cubit.cmd('block 2 attribute index 5 9000.0 ')
cubit.cmd('block 2 attribute index 6 0 ')     # anisotropy_flag

cubit.cmd('block 3 name "elastic 3" ')        # elastic material region
cubit.cmd('block 3 attribute count 6')
cubit.cmd('block 3 attribute index 1 3  ')      # same properties as for volume 2
cubit.cmd('block 3 attribute index 2 7500 ')
cubit.cmd('block 3 attribute index 3 4300 ')
cubit.cmd('block 3 attribute index 4 3200 ')
cubit.cmd('block 3 attribute index 5 9000.0 ')
cubit.cmd('block 3 attribute index 6 0 ')     # anisotropy_flag

cubit.cmd('export mesh "' + CUBIToutput + '/top.e" dimension 3 overwrite')
cubit.cmd('save as "' + CUBIToutput + '/top.cub" overwrite')

#### Export to SPECFEM3D format using cubit2specfem3d.py of GEOCUBIT

cubit2specfem3d.export2SPECFEM3D(SEMoutput)

# screen shot
# (could crash version < 16.4)
if version_major >= 16 and version_minor >= 4:
    cubit.cmd('view top')
    cubit.cmd('hardcopy "' + CUBIToutput + '/layered-fig8.png" png')

# all files needed by SCOTCH are now in directory MESH





