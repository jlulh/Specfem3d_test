WORKFLOW='inversion'    # inversion, migration, modeling
SOLVER='specfem3d'      # specfem2d, specfem3d
SYSTEM='multicore'       # serial, pbs, slurm
OPTIMIZE='LBFGS'        # base
PREPROCESS='base'       # base
POSTPROCESS='base'      # base

#MISFIT='Dispersion'
MISFIT='Waveform'
#BACKPROJECT='Acceleration'
MATERIALS='LegacyAcoustic' #only update vs
DENSITY='Constant'
PRECOND=None
DAS=0          # DAS or geo
GL=4            

# WORKFLOW
BEGIN=1                 # first iteration
END=50                  # last iteration
NREC=142               # number of receivers
NSRC=1                 # number of sources


# PREPROCESSING
FORMAT='su'             # data file format
CHANNELS='xyz'            # data channels
NORMALIZE=0             # normalize
MUTE=0                  # mute direct arrival
MUTECONST=0.            # mute constant
MUTESLOPE=0.            # mute slope

# DISPERSION
FMIN = 10.0
DF = 1
FMAX = 80.0
VMIN = 500
VMAX = 1200
PCOUNT = 700
ANGMIN = 0
ANGMAX = 360
DANG = 10
ANG_RANG = 5 # angle from theta-ang_rang to theta+ang_rang
RATIO = 0.25
TRACENORMALIZE='false' #true or false
MAXRADIUS = 60 #80
MINMAXRADIUS = 60
DRADIUS= 10
MINRADIUS = 0
SEARCHRATIO = 0.1
INIF = 30
NG = 120 #unuse
NXREC=39
NYREC=22


# POSTPROCESSING
HESSIAN1='hess'     # 'hess' for 3D; 'Hessian1' for 2D
SMOOTH=8.               # smoothing radius
SMOOTHV=8.
SCALE=1.                # scaling factor
USE_GPU='false'        # smooth with gpu? 'true' or 'false'

# OPTIMIZATION
STEPCOUNTMAX=10              # maximum trial steps
STEPLENINIT=0.05           # step length safeguard
STEPLENMAX=0.5
#only apply for VS model
VSMAX=1100
VSMIN=500


# SOLVER
NT=1000                 # number of time steps
DT=0.0002               # time step
F0=30                  # dominant frequency
KEYWORD='dz_SU'       #_dxy_SU or dasxy_SU

# SYSTEM
NTASK=1             # number of tasks or sources
NTASKMAX=1
#NODESIZE=32
SLURMARGS='-A k1046 '
NPROC=1 # number of processers model decomposition
TASKTIME=35 #the time for one forwarding modeling 
WALLTIME=500             # the total time for inversion 

# SAVE
SAVEMODEL=1
SAVEGRADIENT=1
SAVEKERNELS=0
SAVETRACES =1
SAVERESIDUALS=0