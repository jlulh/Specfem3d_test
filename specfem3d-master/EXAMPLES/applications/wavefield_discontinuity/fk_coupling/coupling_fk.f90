  

module fk_injection
  integer, parameter :: CUSTOM_REAL = 4, IMAIN = 6, NGLLSQUARE = 25
  double precision, parameter :: PI = 3.141592653589793d0, &
                                   TINYVAL = 1.d-9
  integer :: myrank
  integer :: NSTEP
  real(kind=CUSTOM_REAL) :: deltat
  character(len=100) :: FKMODEL_FILE = 'fk_model'
  ! FK elastic
  integer :: nlayer
  integer :: NF_FOR_STORING, NF_FOR_FFT, NPOW_FOR_FFT, NP_RESAMP, NPOW_FOR_INTERP
  integer :: NPTS_STORED, NPTS_INTERP
  
  !real(kind=CUSTOM_REAL),dimension(:,:),allocatable :: &
  !                  vxbd,vybd,vzbd,txxbd,txybd,txzbd,tyybd,tyzbd,tzzbd
  real(kind=CUSTOM_REAL) :: Z_REF_for_FK

  ! source
  integer :: type_kpsv_fk = 0  ! incident wave type: 1 == P-wave, 2 == SV-wave
  real(kind=CUSTOM_REAL) :: xx0,yy0,zz0,ff0,tt0,tmax_fk,freq_sampling_fk,amplitude_fk
  real(kind=CUSTOM_REAL) :: phi_FK,theta_FK

  ! model
  real(kind=CUSTOM_REAL),dimension(:),allocatable :: alpha_FK,beta_FK,rho_FK,mu_FK,h_FK
  !complex(kind=8), dimension(:,:), allocatable :: VX_f, VY_f, VZ_f, TX_f, TY_f, TZ_f
  real(kind=CUSTOM_REAL),dimension(:,:,:),allocatable :: displ, accel, traction

  !complex(kind=8), dimension(:), allocatable :: WKS_CMPLX_FOR_FFT
  !real(kind=CUSTOM_REAL), dimension(:), allocatable :: WKS_REAL_FOR_FFT

  real(kind=CUSTOM_REAL),dimension(:),allocatable  :: xx,yy,zz,xi1,xim,bdlambdamu

  ! normal
  real(kind=CUSTOM_REAL),dimension(:),allocatable  :: nmx,nmy,nmz
end module fk_injection

  subroutine FK(al, be, mu, H, nlayer, &
                Tg, ray_p, phi, x0, y0, z0, &
                t0, dt, npts, npt, &
                kpsv, NF_FOR_STORING, NPOW_FOR_FFT, NP_RESAMP, DF_FK, &
                compute_traction)

  use fk_injection, only: myrank,CUSTOM_REAL,IMAIN,PI,TINYVAL,&
                                  NGLLSQUARE, &
                                  displ, accel, traction, &
                                  xx, yy, zz, xi1, xim, bdlambdamu, &
                                  nmx, nmy, nmz, NPTS_STORED, NPTS_INTERP, &
                                  amplitude_fk

  implicit none

  integer,                parameter                         :: CUSTOM_CMPLX = 8
  real(kind=CUSTOM_REAL), parameter                         :: zign_neg = -1.0

  ! input and output
  integer,                                     intent(in)   :: nlayer, npt, npts, kpsv
  integer                                                   :: NF_FOR_STORING, NPOW_FOR_FFT, NP_RESAMP

  ! model
  real(kind=CUSTOM_REAL),  dimension(nlayer),  intent(in)   :: al(nlayer),be(nlayer),mu(nlayer),H(nlayer)

  ! source
  real(kind=CUSTOM_REAL),                      intent(in)    :: dt, ray_p, phi, x0, y0, z0, Tg, t0, DF_FK

  ! local parameters
  real(kind=CUSTOM_REAL),     dimension(:),   allocatable    :: fvec, dtmp
  real(kind=CUSTOM_REAL),     dimension(:,:), allocatable    :: field
  real(kind=CUSTOM_REAL),     dimension(:),   allocatable    :: tmp_t1, tmp_t2, tmp_t3, tmp_it1

  complex(kind=CUSTOM_CMPLX), dimension(:,:), allocatable    :: coeff, field_f
  complex(kind=CUSTOM_CMPLX), dimension(:),   allocatable    :: tmp_f1, tmp_f2, tmp_f3
  complex(kind=CUSTOM_CMPLX)                                 :: C_3,stf_coeff,a,b,c,d,delta_mat
  complex(kind=CUSTOM_CMPLX)                                 :: dx_f,dz_f,txz_f,tzz_f
  complex(kind=CUSTOM_CMPLX)                                 :: N_mat(4,4)

  real(kind=CUSTOM_REAL)                                     :: sigma_rr,sigma_rt,sigma_rz,sigma_tt,sigma_tz,sigma_zz
  real(kind=CUSTOM_REAL)                                     :: Txx_tmp, Txy_tmp, Txz_tmp, Tyy_tmp, Tyz_tmp, Tzz_tmp
  real(kind=CUSTOM_REAL)                                     :: dt_fk,df,om,Tdelay,eta_p,eta_s,f_Nyquist,C_1

  integer                                                    :: npow,npts2,nf,nf2,nn,ii,ipt,i,j,lpts
  integer                                                    :: npoints2
  integer                                                    :: ier,iface,igll,ispec

  ! spline work array
  double precision, dimension(:), allocatable                :: tmp_c

!! DK DK here is the hardwired maximum size of the array
!! DK DK Aug 2016: if this routine is called many times (for different mesh points at which the SEM is coupled with FK)
!! DK DK Aug 2016: this should be moved to the calling program and precomputed once and for all
  real(kind=CUSTOM_REAL) :: mpow(30)

  ! taper
  ! idea: tapers the onset of the injection traces to diminish numerical noise.
  !       the inverse FFT can lead to non-zero onsets for coarse frequency sampling.
  logical, parameter :: USE_TAPERED_BEGINNING = .false.
  integer, parameter :: taper_nlength = 20    ! tapers first 20 steps
  real(kind=CUSTOM_REAL) :: taper

  ! fixed parameters
  !integer, parameter     :: nvar = 5
  logical :: compute_traction
  integer :: nvar

  if (compute_traction) then
    nvar = 3
  else
    nvar = 4
  endif

  ! initializations
  !! new way to do time domain resampling
  df    = DF_FK
  nf2   = NF_FOR_STORING+1   ! number of positive frequency sample points
  nf    = 2*NF_FOR_STORING   ! number of total frequencies after symmetrisation
  npts2 = nf                 ! number of samples in time serie

  !! VM VM recompute new values for new way to do
  npow = ceiling(log(npts2*1.0)/log(2.0))
  npts2 = 2**npow
  NPOW_FOR_FFT = npow

  !! number of points for resampled vector
  npoints2 = NP_RESAMP*(npts2-1)+1

  dt_fk = 1.0_CUSTOM_REAL/(df*(npts2-1))
  f_Nyquist = 1.0_CUSTOM_REAL/(2.0_CUSTOM_REAL * dt)    ! Nyquist frequency of specfem time serie

  ! user output
  if (myrank == 0) then
    write(IMAIN,*)
    write(IMAIN,*) '  Entering the FK synthetics program:'
    write(IMAIN,*) '    Number of samples stored for FK solution = ', NF_FOR_STORING
    write(IMAIN,*) '    Number of points used for FFT            = ', npts2
    write(IMAIN,*) '    Total time length used for FK            = ', t0+(npts2-1)*dt_fk,'(s)'
    write(IMAIN,*)
    write(IMAIN,*) '    simulation Nyquist frequency             = ', f_Nyquist,'(Hz)'
    write(IMAIN,*) '    FK time step                             = ', dt_fk
    write(IMAIN,*) '    FK frequency step                        = ', df
    write(IMAIN,*) '    power of 2 for FFT                       = ', npow
    write(IMAIN,*)
    call flush_IMAIN()
  endif

  !! check if dt_fk is compatible with dt_specfem
  !!
  !!
  !!

  allocate(fvec(nf2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2218')
  if (ier /= 0) stop 'error while allocating'
  fvec(:) = 0.0_CUSTOM_REAL
  do ii = 1, nf2
    fvec(ii) = (ii-1)*df
  enddo

  allocate(coeff(2,nf2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2219')
  if (ier /= 0) stop 'error while allocating'
  coeff(:,:) = (0.d0,0.d0)

  allocate(field_f(nf,nvar),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2220')
  if (ier /= 0) stop 'error while allocating'
  field_f(:,:) = (0.d0,0.d0)

  allocate(field(npts2,nvar),dtmp(npts),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2221')
  if (ier /= 0) stop 'error while allocating'
  field(:,:) = 0._CUSTOM_REAL; dtmp(:) = 0._CUSTOM_REAL

  !! allocate debug vectors
  allocate(tmp_f1(npts2), tmp_f2(npts2), tmp_f3(npts2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2222')
  if (ier /= 0) stop 'error while allocating'
  tmp_f1(:) = (0.d0,0.d0)
  tmp_f2(:) = (0.d0,0.d0)
  tmp_f3(:) = (0.d0,0.d0)

  if (ier /= 0) stop 'error while allocating'
  allocate(tmp_t1(npts2), tmp_t2(npts2), tmp_t3(npts2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2223')
  if (ier /= 0) stop 'error while allocating'
  tmp_t1(:) = 0.0_CUSTOM_REAL
  tmp_t2(:) = 0.0_CUSTOM_REAL
  tmp_t3(:) = 0.0_CUSTOM_REAL

  allocate(tmp_it1(npoints2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2224')
  if (ier /= 0) stop 'error while allocating'
  tmp_it1(:) = 0.0_CUSTOM_REAL

  ! temporary work array for splines
  allocate(tmp_c(npts2),stat=ier)
  if (ier /= 0) call exit_MPI_without_rank('error allocating array 2225')
  tmp_c(:) = 0.d0

  NPTS_STORED = npts2
  NPTS_INTERP = npoints2

  nn = int(-t0/dt) ! what if this is not an integer number?

!! DK DK Aug 2016: if this routine is called many times (for different mesh points at which the SEM is coupled with FK)
!! DK DK Aug 2016: this should be moved to the calling program and precomputed once and for all
  do i = 1,npow
    mpow(i) = 2**(npow-i)
  enddo

  if (myrank == 0) then
    write(IMAIN,*) '    starting from ',nn,' points before time 0'
    write(IMAIN,*)
    call flush_IMAIN()
  endif

  if (kpsv == 1) then
    ! P-wave
    ! for C_3 = i sin(inc) (u=[sin(inc), cos(inc)])
    C_3 = amplitude_fk * cmplx(0,1.) * ray_p * al(nlayer)      ! amp. of incoming P in the bot. layer
    eta_p = sqrt(1.0/al(nlayer)**2 - ray_p**2)                 ! vertical slowness for lower layer

    if (myrank == 0) write(IMAIN,*) '  Incoming P : C_3,  ray_p, eta = ', C_3, ray_p, eta_p

    N_mat(:,:) = (0.d0,0.d0)

    ! find out the wave coefficients in the bottom layer for all freqs -------------------------------
    do ii = 1, nf2
      om = 2.0 * PI * fvec(ii)
      ! propagation matrix
      call compute_N_Rayleigh(al,be,mu,H,nlayer,om,ray_p,sum(H(1:nlayer-1)),N_mat) !total-thickness=sum(H)

      a = N_mat(3,2); b = N_mat(3,4); c = N_mat(4,2); d = N_mat(4,4)
      delta_mat = a*d - b*c
      if (abs(delta_mat) > TINYVAL) then
        coeff(1,ii) = -(d*N_mat(3,3) - b*N_mat(4,3)) / delta_mat * C_3
        coeff(2,ii) = -(-c*N_mat(3,3) + a*N_mat(4,3)) / delta_mat * C_3
      else
        coeff(1,ii) = (0.d0,0.d0)
        coeff(2,ii) = (0.d0,0.d0)
      endif

      !debug
      !if (ii == 1 .and. myrank == 0) then
      !  print *,'debug: Rayleigh coeff ',coeff(1,ii),coeff(2,ii),delta_mat
      !  print *,'N_mat'
      !  print *,N_mat
      !endif
    enddo

    ! loop over all data points -------------------------------------------------
    ! instead of looping over points like:
    do ipt = 1, npt  ! maybe this can be run faster by shifting t for diff. x of fixed z
    ! we loop over the boundary arrays to get ispec & acoustic/elastic domain flag:
    !do iface = 1,num_abs_boundary_faces
    !  ispec = abs_boundary_ispec(iface)

    !  ! GLL points on boundary face
    !  do igll = 1,NGLLSQUARE
    !    ! point index using table lookup
    !    ipt = ipt_table(igll,iface)

        ! initializes
        field_f(:,:) = (0.d0,0.d0)

        ! time delay with respect to top of lower half-space (set to be at z==0)
        Tdelay = ray_p * (xx(ipt)-x0) * cos(phi) + ray_p * (yy(ipt)-y0) * sin(phi) + eta_p * (0.0-z0)

        do ii = 1, nf2
          om = 2.0 * PI * fvec(ii)                                 !! pulsation

          stf_coeff = exp(-(om * Tg/2)**2)                         !! apodization window
          stf_coeff = stf_coeff * exp(cmplx(0,-1)*om*Tdelay)

          !! zz(ipt) is the height of point with respect to the lower layer
          call compute_N_Rayleigh(al,be,mu,H,nlayer,om,ray_p,zz(ipt),N_mat)


          dx_f = N_mat(1,2)*coeff(1,ii) + N_mat(1,4)*coeff(2,ii) + N_mat(1,3)*C_3  ! y_1
          dz_f = N_mat(2,2)*coeff(1,ii) + N_mat(2,4)*coeff(2,ii) + N_mat(2,3)*C_3  ! y_3
          if (.not. compute_traction) then
          ! for the Stacey boundary contribution, we need velocity = (i om) displacement (in frequency domain)
            field_f(ii,1) = stf_coeff * dx_f * cmplx(0,-1)              ! u_x
            field_f(ii,2) = stf_coeff * dz_f                            ! u_z

            field_f(ii,3) = stf_coeff * dx_f * cmplx(0,-1) * cmplx(-om*om,0)     ! (-om^2)u_x
            field_f(ii,4) = stf_coeff * dz_f * cmplx(-om*om,0) ! (-om^2)u_z
          ! acoustic boundary point
          ! note: instead of velocity as in the elastic case, in acoustic domains we would need potentials.
          !       the velocity potential would be defined as: v = 1/rho grad(potential_dot)
          !       thus, we would require to either change the FK formulations or to integrate velocity.
          !       this will be left as a todo for future...
          !
          !       as a reminder, displacement in frequency domains could be obtained by:
          !if (ispec_is_acoustic(ispec)) then
          !  ! displacement: u_x = -i y_1
          !  !               u_z =    y_3   from Tong. (A13)
          !  field_f(ii,1) = stf_coeff * dx_f * cmplx(0,-1)             ! u_x = - i y_1
          !  field_f(ii,2) = stf_coeff * dz_f                           ! u_z =     y_3
          !endif

          ! stress
          else
            txz_f = N_mat(3,2)*coeff(1,ii) + N_mat(3,4)*coeff(2,ii) + N_mat(3,3)*C_3      ! tilde{y}_4
            tzz_f = N_mat(4,2)*coeff(1,ii) + N_mat(4,4)*coeff(2,ii) + N_mat(4,3)*C_3      ! tilde{y}_6

            field_f(ii,1) = stf_coeff * om * ray_p * (xi1(ipt)*tzz_f - 4.0*xim(ipt)*dx_f) ! T_xx
            field_f(ii,2) = stf_coeff * om * ray_p * txz_f * cmplx(0,-1)                  ! T_xz
            field_f(ii,3) = stf_coeff * om * ray_p * tzz_f                                ! T_zz
          endif

          !debug
          !if (ipt==1000 .and. ii == 10 .and. myrank == 0) print *,'debug: coeff',coeff(1,ii),coeff(2,ii), &
          !                                      'dx_f',dx_f,tzz_f,'xi',xi1(ipt),xim(ipt),'field',field_f(ii,3:5)
        enddo

        ! pad negative f, and convert to time series
        do ii = 2, nf2-1
          field_f(nf+2-ii,:) = conjg(field_f(ii,:))
        enddo

        !! inverse fast fourier transform
        field(:,:) = 0.0
        do j = 1, nvar
          ! inverse FFT
          call FFTinv(npow,field_f(:,j),zign_neg,dt,field(:,j),mpow)

          ! wrap around to start from t0: here one has to be careful if t0/dt is not
          ! exactly an integer, assume nn > 0
          if (nn > 0) then
            dtmp(1:nn) = field(npts2-nn+1:npts2,j)
            field(nn+1:npts2,j) = field(1:npts2-nn,j)
            field(1:nn,j) = dtmp(1:nn)
          else if (nn < 0) then
            dtmp(1:nn) = field(1:nn,j)
            field(1:npts-nn,j) = field(nn+1:npts,j)
            field(npts-nn+1:npts,j) = dtmp(1:nn)
          endif
        enddo

        if (.not. compute_traction) then
          !! store undersampled version of velocity  FK solution
          tmp_t1(:) = field(:,1) * cos(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,1) * sin(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,2)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,3) * cos(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,3) * sin(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,4)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

        else
          !! compute traction
          do lpts = 1, NF_FOR_STORING
            sigma_rr = field(lpts,1)
            sigma_rt = 0.0
            sigma_rz = field(lpts,2)
            sigma_zz = field(lpts,3)
            sigma_tt = bdlambdamu(ipt)*(sigma_rr+sigma_zz)
            sigma_tz = 0.0

            Txx_tmp = sigma_rr * cos(phi) * cos(phi) + sigma_tt * sin(phi) * sin(phi)
            Txy_tmp = cos(phi) * sin(phi) * (sigma_rr - sigma_tt)
            Txz_tmp = sigma_rz * cos(phi)
            Tyy_tmp = sigma_rr * sin(phi) * sin(phi) + sigma_tt * cos(phi) * cos(phi)
            Tyz_tmp = sigma_rz * sin(phi)
            Tzz_tmp = sigma_zz

            !! store directly the traction
            traction(1,ipt,lpts) = Txx_tmp*nmx(ipt) +  Txy_tmp*nmy(ipt) +  Txz_tmp*nmz(ipt)
            traction(2,ipt,lpts) = Txy_tmp*nmx(ipt) +  Tyy_tmp*nmy(ipt) +  Tyz_tmp*nmz(ipt)
            traction(3,ipt,lpts) = Txz_tmp*nmx(ipt) +  Tyz_tmp*nmy(ipt) +  Tzz_tmp*nmz(ipt)
          enddo

          !! store undersamped version of tractions FK solution
          tmp_t1(1:NF_FOR_STORING) = traction(1,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(1:NF_FOR_STORING) = traction(2,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(1:NF_FOR_STORING) = traction(3,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)
        endif

        ! user output
        if (myrank == 0 .and. npt > 1000) then
          if (mod(ipt,(npt/10)) == 0) then
            write(IMAIN,*) '  done ',ipt/(npt/10)*10,'% points out of ',npt
            call flush_IMAIN()
          endif
        endif
      !enddo
    enddo

  else if (kpsv == 2) then
    ! SV-wave
    ! for C_2 = sin(inc) (u=[cos(inc), sin(inc)])
    C_1 = amplitude_fk * ray_p * be(nlayer)                   ! amp. of incoming S in the bot. layer
    eta_s = sqrt(1.0/be(nlayer)**2 - ray_p**2)                ! vertical slowness for lower layer

    if (myrank == 0) write(IMAIN,*) '  Incoming S :  C_1,  ray_p, eta = ', C_1, ray_p, eta_s

    N_mat(:,:) = (0.d0,0.d0)

    ! find out the wave coefficients in the bottom layer for all freqs
    do ii = 1, nf2
      om = 2.0 * PI * fvec(ii)
      ! propagation matrix
      call compute_N_Rayleigh(al,be,mu,H,nlayer,om,ray_p,sum(H(1:nlayer-1)),N_mat) !total-thickness=sum(h)

      a = N_mat(3,2); b = N_mat(3,4); c = N_mat(4,2); d = N_mat(4,4)
      delta_mat = a*d - b*c
      if (abs(delta_mat) > TINYVAL) then
        coeff(1,ii) = -(d*N_mat(3,1) - b*N_mat(4,1)) / delta_mat * C_1
        coeff(2,ii) = -(-c*N_mat(3,1) + a*N_mat(4,1)) / delta_mat * C_1
      else
        coeff(1,ii) = (0.d0,0.d0)
        coeff(2,ii) = (0.d0,0.d0)
      endif
    enddo

    ! loop over all data points
    ! instead of looping over points like:
    do ipt = 1, npt  ! maybe this can be run faster by shifting t for diff. x of fixed z
    ! we loop over the boundary arrays to get ispec & acoustic/elastic domain flag:
    !do iface = 1,num_abs_boundary_faces
    !  ispec = abs_boundary_ispec(iface)

    !  ! GLL points on boundary face
    !  do igll = 1,NGLLSQUARE
        ! point index using table lookup
        !ipt = ipt_table(igll,iface)

        ! initializes
        field_f(:,:) = (0.d0,0.d0)

        ! time delay with respect to top of lower half-space (set to be at z==0)
        Tdelay = ray_p * (xx(ipt)-x0) * cos(phi) + ray_p * (yy(ipt)-y0) * sin(phi) + eta_s * (0.0-z0)

        do ii = 1, nf2
          om = 2.0 * PI * fvec(ii)
          stf_coeff = exp(-(om * Tg/2)**2) * exp(cmplx(0,-1)*om*Tdelay)

          ! z is the height of position with respect to the lowest layer interface.
          call compute_N_Rayleigh(al,be,mu,H,nlayer,om,ray_p,zz(ipt),N_mat)


          dx_f = N_mat(1,2)*coeff(1,ii) + N_mat(1,4)*coeff(2,ii) + N_mat(1,1)*C_1  ! y_1
          dz_f = N_mat(2,2)*coeff(1,ii) + N_mat(2,4)*coeff(2,ii) + N_mat(2,1)*C_1  ! y_3
          if (compute_traction) then
          ! for the Stacey boundary contribution, we need velocity = (i om) displacement (in frequency domain)
            field_f(ii,1) = stf_coeff * dx_f * cmplx(0,-1) ! u_x(1.20)
            field_f(ii,2) = stf_coeff * dz_f ! u_z
            field_f(ii,3) = stf_coeff * dx_f * cmplx(0,-1) * cmplx(-om*om,0) ! (-om^2)u_x(1.20)
            field_f(ii,4) = stf_coeff * dz_f * cmplx(-om*om,0) ! (-om^2)u_z

          ! acoustic boundary point
          ! note: instead of velocity as in the elastic case, in acoustic domains we would need potentials.
          !       the velocity potential would be defined as: v = 1/rho grad(potential_dot)
          !       thus, we would require to either change the FK formulations or to integrate velocity.
          !       this will be left as a todo for future...
          !
          !       as a reminder, displacement in frequency domains could be obtained by:
          !if (ispec_is_acoustic(ispec)) then
          !  ! displacement: u_x = -i y_1
          !  !               u_z =    y_3   from Tong. (A13)
          !  field_f(ii,1) = stf_coeff * dx_f * cmplx(0,-1)             ! u_x = - i y_1
          !  field_f(ii,2) = stf_coeff * dz_f                           ! u_z =     y_3
          !endif

          else
            txz_f = N_mat(3,2)*coeff(1,ii) + N_mat(3,4)*coeff(2,ii) + N_mat(3,1)*C_1 ! tilde{y}_4
            tzz_f = N_mat(4,2)*coeff(1,ii) + N_mat(4,4)*coeff(2,ii) + N_mat(4,1)*C_1 ! tilde{y}_6

            field_f(ii,1) = stf_coeff * om * ray_p * (xi1(ipt)*tzz_f - 4.0*xim(ipt)*dx_f) ! T_xx
            field_f(ii,2) = stf_coeff * om * ray_p * txz_f * cmplx(0,-1)                ! T_xz
            field_f(ii,3) = stf_coeff * om * ray_p * tzz_f                              ! T_zz
          endif
        enddo

        ! pad negative f, and convert to time series
        do ii = 2, nf2-1
          field_f(nf+2-ii,:) = conjg(field_f(ii,:))
        enddo

        field(:,:) = 0.0
        do j = 1, nvar
          ! inverse FFT
          call FFTinv(npow,field_f(:,j),zign_neg,dt,field(:,j),mpow)

          ! wrap around to start from t0: here one has to be careful if t0/dt is not
          ! exactly an integer, assume nn > 0
          ! note: for nn == 0, nothing to wrap as field(1:npts2,j) = field(1:npts2,j)
          if (nn > 0) then
            dtmp(1:nn) = field(npts2-nn+1:npts2,j)
            field(nn+1:npts2,j) = field(1:npts2-nn,j)
            field(1:nn,j) = dtmp(1:nn)
          else if (nn < 0) then
            dtmp(1:nn) = field(1:nn,j)
            field(1:npts-nn,j) = field(nn+1:npts,j)
            field(npts-nn+1:npts,j) = dtmp(1:nn)
          endif
        enddo

        if (.not. compute_traction) then
          !! store undersampled version of velocity  FK solution
          tmp_t1(:) = field(:,1)*cos(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,1)*sin(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,2)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          displ(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,3)*cos(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,3)*sin(phi)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(:) = field(:,4)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          accel(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

        else
          !! compute traction
          do lpts = 1, NF_FOR_STORING
            sigma_rr = field(lpts,1)
            sigma_rt = 0.0
            sigma_rz = field(lpts,2)
            sigma_zz = field(lpts,3)
            sigma_tt = bdlambdamu(ipt)*(sigma_rr+sigma_zz)
            sigma_tz = 0.0

            Txx_tmp = sigma_rr * cos(phi) * cos(phi) + sigma_tt * sin(phi) * sin(phi)
            Txy_tmp = cos(phi) * sin(phi) * (sigma_rr - sigma_tt)
            Txz_tmp = sigma_rz * cos(phi)
            Tyy_tmp = sigma_rr * sin(phi) * sin(phi) + sigma_tt * cos(phi) * cos(phi)
            Tyz_tmp = sigma_rz * sin(phi)
            Tzz_tmp = sigma_zz

            !! store directly the traction
            traction(1,ipt,lpts) = Txx_tmp*nmx(ipt) +  Txy_tmp*nmy(ipt) +  Txz_tmp*nmz(ipt)
            traction(2,ipt,lpts) = Txy_tmp*nmx(ipt) +  Tyy_tmp*nmy(ipt) +  Tyz_tmp*nmz(ipt)
            traction(3,ipt,lpts) = Txz_tmp*nmx(ipt) +  Tyz_tmp*nmy(ipt) +  Tzz_tmp*nmz(ipt)
          enddo

          !! store undersamped version of tractions FK solution
          tmp_t1(1:NF_FOR_STORING) = traction(1,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(1,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(1:NF_FOR_STORING) = traction(2,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(2,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)

          tmp_t1(1:NF_FOR_STORING) = traction(3,ipt,1:NF_FOR_STORING)
          call compute_spline_coef_to_store(tmp_t1, npts2, tmp_t2, tmp_c)
          traction(3,ipt,1:NF_FOR_STORING) = tmp_t2(1:NF_FOR_STORING)
        endif

        ! user output
        if (myrank == 0 .and. npt > 1000) then
          if (mod(ipt,(npt/10)) == 0) then
            write(IMAIN,*) '  done ',ipt/(npt/10)*10,'% points out of ',npt
            call flush_IMAIN()
          endif
        endif
      !enddo
    enddo
  endif

  ! taper
  if (USE_TAPERED_BEGINNING) then
    ! check if taper length is reasonable compared to wavefield storage traces
    if (NF_FOR_STORING > 2 * taper_nlength) then
      do i = 1,taper_nlength
        ! cosine taper, otherwise using a constant (1.0) instead
        taper = (1.0 - cos(PI*(i-1)/taper_nlength)) * 0.5        ! between [0,1[
        if (.not. compute_traction) then
          ! tapers traces
          displ(:,:,i) = taper * displ(:,:,i)
          accel(:,:,i) = taper * accel(:,:,i)
        else
          traction(:,:,i) = taper * traction(:,:,i)
        endif
      enddo
    endif
  endif

  ! free temporary arrays
  deallocate(fvec,coeff, field_f, field, dtmp)
  deallocate(tmp_f1, tmp_f2, tmp_f3, tmp_t1, tmp_t2, tmp_t3)
  deallocate(tmp_c)

  ! user output
  if (myrank == 0) then
    write(IMAIN,*)
    write(IMAIN,*) "  FK computing passed "
    write(IMAIN,*)
    call flush_IMAIN()
  endif

  end subroutine FK

!
!-------------------------------------------------------------------------------------------------
!

  subroutine compute_N_Rayleigh(alpha, beta, mu, H, nlayer, om, ray_p, height, N_mat)

  ! assumes that height = 0 is the bottom interface

  use fk_injection, only: CUSTOM_REAL,myrank

  implicit none

  ! precision for complex
  integer, parameter :: CUSTOM_CMPLX = 8

  ! input
  integer,                                       intent(in)   :: nlayer
  real(kind=CUSTOM_REAL),     dimension(nlayer), intent(in)   :: alpha, beta, mu, H
  real(kind=CUSTOM_REAL),                        intent(in)   :: om,ray_p,height

  ! output
  complex(kind=CUSTOM_CMPLX), dimension(4,4),    intent(inout) :: N_mat(4,4)

  ! local vars
  integer                                         :: i, j, ilayer
  complex(kind=CUSTOM_CMPLX), dimension(nlayer)   :: eta_alpha, eta_beta, nu_al, nu_be
  complex(kind=CUSTOM_CMPLX), dimension(4,4)      :: E_mat, G_mat, P_layer
  complex(kind=CUSTOM_CMPLX)                      :: xa, ya, xb, yb
  complex(kind=CUSTOM_CMPLX)                      :: ca, sa, cb, sb, c1, c2
  real(kind=CUSTOM_CMPLX),    dimension(nlayer)   :: gamma0, gamma1
  real(kind=CUSTOM_CMPLX),    dimension(nlayer)   :: hh
  real(kind=CUSTOM_CMPLX)                         :: g1, mul, two_mul, g1_sq
  real(kind=CUSTOM_CMPLX)                         :: alphal, betal

  if (nlayer < 1) stop 'nlayer has to be larger than or equal to 1'

! see: Tong et al. (2014),
!      High-resolution seismic array imaging based on an SEM-FK hybrid method,
!      GJI, 197, 369-395.
! details in the appendix

  ! note: vertical incident (p=0) is not handled in Tong et al. explanations.
  !       here, it limits p to a very small value to handle the calculations
  if (abs(ray_p) < 1.e-15) stop 'Invalid ray parameter p (cannot be zero) in compute_N_Rayleigh() routine'

  ! vertical wavenumbers
  ! pre-computes factors
  do i = 1,nlayer
    ! vp and vs
    alphal = alpha(i)  ! vp
    betal = beta(i)    ! vs

    ! safety check: zero shear velocity case not handled yet
    if (abs(betal) < 1.e-15) stop 'Invalid shear velocity in compute_N_Rayleigh() routine'

    ! P
    ! see (A5): E_23 = -i nu_p / k = -i omega sqrt(1/alpha^2 - p^2) / k
    !           factor eta_alpha = -i sqrt(1/alpha^2 - p^2)
    !                            = -i sqrt( (1/alpha + p) * (1/alpha - p) )
    !                            = -i sqrt(1/alpha + p) * sqrt(1/alpha - p)
    !org: eta_alpha(i) = -cmplx(0,1) * sqrt(1.0/alpha(i) + ray_p) * sqrt(1.0/alpha(i) - ray_p)
    eta_alpha(i) = -cmplx(0,1) * sqrt( 1.0 / alphal**2 - ray_p**2 )  ! i*vertical slowness, purely imaginary
    ! note: here factor nu_al = -i nu_p = -i omega sqrt(1/alpha^2 - p^2)
    !                                   = omega (-i sqrt(1/alpha^2 - p^2)
    !                                   = omega (eta_alpha)
    nu_al(i) = om * eta_alpha(i) ! i * vertical wavenumber

    ! SV
    ! see (A5): E_11 = -i nu_s / k = -i omega sqrt(1/beta^2 - p^2) / k
    !           factor eta_beta = -i sqrt(1/beta^2 - p^2)
    !                           = -i sqrt( (1/beta + p) * (1/beta - p) )
    !                           = -i sqrt(1/beta + p) * sqrt(1/beta - p)
    !org: eta_beta(i) = -cmplx(0,1) * sqrt(1.0/beta(i) + ray_p) * sqrt(1.0/beta(i) - ray_p)
    eta_beta(i) = -cmplx(0,1) * sqrt( 1.0 / betal**2 - ray_p**2 )

    ! note: here factor nu_be = -i nu_s = -i omega sqrt(1/beta^2 - p^2)
    !                                   = omega (-i sqrt(1/beta^2 - p^2)
    !                                   = omega (eta_beta)
    nu_be(i) = om * eta_beta(i) ! i * vertical wavenumber

    ! auxiliary variables
    gamma0(i) = 2.0 * betal**2 * ray_p**2
    gamma1(i) = 1.0 - 1.0/gamma0(i)
  enddo

  ! initializes matrix
  E_mat(:,:) = (0.0,0.0)

  ! Tong et al. (2014), appendix (A10) E_0:
  ! note: E_mat is not omega dependent
  !
  ! (A5): E_11 = -i nu_s / k
  !            = -i omega * sqrt(1/beta^2 - p^2) / ( p * omega)   ,with p = k/omega -> k = p * omega
  !            = -i sqrt(1/beta^2 - p^2) / p
  !            = eta_beta / p
  E_mat(1,1) =  eta_beta(nlayer) / ray_p
  E_mat(1,2) = -E_mat(1,1)
  E_mat(1,3) = (1.0,0.0)
  E_mat(1,4) = (1.0,0.0)

  ! (A5): E_23 = -i nu_p / k
  !            = -i omega * sqrt(1/alpha^2 - p^2) / (p * omega)     ,with p = k/omega -> k = p * omega
  !            = -i sqrt(1/alpha^2 - p^2) / p
  !            = eta_alpha / p
  E_mat(2,1) = (1.0,0.0)
  E_mat(2,2) = (1.0,0.0)
  E_mat(2,3) =  eta_alpha(nlayer) / ray_p
  E_mat(2,4) = -E_mat(2,3)

  ! pre-computed factor for half-space (layer with index nlayer)
  mul = mu(nlayer)
  ! 2 mu
  two_mul = 2.0 * mul

  ! note: wavenumber k is defined as p = k / omega -> k = p * omega
  !       for frequency omega==0, wavenumber k becomes zero and thus a factor 1/k becomes undefined.
  !       to avoid such behavior, the factor k in the expressions for E below will be cancelled out.
  !       together with the multiplication by propagation matrix P, where elements can have a factor k, this should be ok.
  !       unfortunately, the original paper by Tong et al. doesn't mention such a case and assumes k is non-zero.

  ! (A5): E_31 = 2 k mu gamma_1
  !            = 2 p omega mu gamma_1  ,with wavenumber k: from ray p = k / omega -> k = p * omega
  !org: E_mat(3,1) = 2.0 * mu(nlayer) * gamma1(nlayer)               ! takes out factor k
  E_mat(3,1) = two_mul * gamma1(nlayer)
  E_mat(3,2) = E_mat(3,1)

  ! (A5): E_33 = - 2 i mu nu_p
  !            = 2 mu (-i) omega sqrt(1/alpha^2 - p^2)
  !            = 2 mu omega (-i sqrt(1/alpha^2 - p^2))
  !            = 2 mu omega (eta_alpha)
  !            or
  !            = 2 mu (eta_alpha) k / p     ,with p = k/omega -> omega = k / p
  !org: E_mat(3,3) = 2.0 * mu(nlayer) * eta_alpha(nlayer) / ray_p    ! takes out factor k
  E_mat(3,3) = two_mul * eta_alpha(nlayer) / ray_p
  E_mat(3,4) = -E_mat(3,3)

  ! (A5): E_41 = - 2 i mu nu_s
  !            = 2 mu (-i) omega sqrt(1/beta^2 - p^2)
  !            = 2 mu omega (-i sqrt(1/beta^2 - p^2))
  !            = 2 mu omega (eta_beta)
  !            or
  !            = 2 mu (eta_beta) k / p      ,with p = k/omega -> omega = k / p
  !org: E_mat(4,1) = 2.0 * mu(nlayer) * eta_beta(nlayer) / ray_p     ! takes out factor k
  E_mat(4,1) = two_mul * eta_beta(nlayer) / ray_p
  E_mat(4,2) = -E_mat(4,1)

  ! (A5): E_43 = 2 k mu gamma_1
  !            = E_31 = E_32
  E_mat(4,3) = E_mat(3,1)
  E_mat(4,4) = E_mat(3,1)

  if (height > sum(H(1:nlayer-1))) then
    print *,'FK error: rank ',myrank
    print *,'  Z point is located in the air above the surface rather than in the solid!'
    print *,'  current z :', height, ' max z allowed : ',  sum(H(1:nlayer-1))
    stop 'FK invalid height'
  endif

  ! figure out the location z with respect to layer stack
  if (height <= 0.0) then
    ! in lower half space
    G_mat(:,:) = (0.0,0.0)
    ! incident, up-going S-wave
    ! (A5): Gamma_11 = e^(-i nu_s z) = e^( (-i nu_s) * z ) = e^(nu_be * z)
    G_mat(1,1) = exp(nu_be(nlayer) * height)
    ! reflected, down-going S-wave
    ! (A5): Gamma_22 = e^(i nu_s z)  = e^( -(-i nu_s) * z ) = e^(-nu_be * z)
    G_mat(2,2) = exp(-nu_be(nlayer) * height)
    ! incident, up-going P-wave
    ! (A5): Gamma_33 = e^(-i nu_p z) = e^( (-i nu_p) * z ) = e^(nu_al * z)
    G_mat(3,3) = exp(nu_al(nlayer) * height)
    ! reflected, down-going P-wave
    ! (A5): Gamma_44 = e^(i nu_p z) = e^( -(-i nu_p) * z ) = e^(-nu_al * z)
    G_mat(4,4) = exp(-nu_al(nlayer) * height)

    ! resulting matrix
    N_mat = matmul(E_mat,G_mat)

  else
    ! in layers
    ! determines layer in which the point (given by height) lies
    ! note: indexing assumes that last layer (nlayer) being the bottom, lower halfspace,
    !       and the first layer (1) being at the top surface
    hh(:) = H(:)
    ilayer = nlayer
    do j = nlayer-1 , 1 , -1
      if (height <= sum(H(j:nlayer-1))) then
        ilayer = j; exit
      endif
    enddo

    ! updates point's layer thicknesses
    hh(ilayer+1:nlayer-1) = H(ilayer+1:nlayer-1)
    hh(ilayer) = height - sum(H(ilayer+1:nlayer-1))

    if (hh(ilayer) < 0.0) then
      print *,'Error: rank ',myrank,' has invalid point height ',hh(ilayer),' at layer ',ilayer
      stop 'Error setting layer thickness'
    endif

    !debug
    !print *,'debug: height ',height,'layer ',ilayer,nlayer,'H',H(:),'sum',sum(H(ilayer:nlayer-1)),'h',hh(:)

    ! compute propagation matrices
    N_mat(:,:) = E_mat(:,:)

    do j = nlayer-1, ilayer, -1
      ! matrix variables
      ! C_alpha = cos(nu_p h) = cos( omega sqrt(1/alpha^2 - p^2) h )
      ! S_alpha = -sin(nu_p h) = -sin( omega sqrt(1/alpha^2 - p^2) h )
      ! with nu_p h = omega sqrt(1/alpha^2 - p^2) h
      !
      ! note: there might be some sign conflict and confusion between sin and sinh in the definition after (A9) of Tong et al.
      !       instead of S_alpha = -sin(nu_p h) as stated in the paper, here sa becomes [i sin(nu_p h)] as imaginary number.
      !
      c1 = nu_al(j) * hh(j)
      ! cos(nu_p h) = [ e^(i nu_p h) + e^(-i nu_p h) ] / 2
      !           = [ e^(-nu_al * h) + e^(nu_al * h) ] / 2
      ca = (exp(c1) + exp(-c1))/2.0
      ! sin(nu_p h) = [ e^(i nu_p h) - e^(-i nu_p h) ] / 2i
      !             = [ e^(-nu_al * h) - e^(nu_al * h) ] / 2i
      !             = i [ e^(nu_al * h) - e^(-nu_al * h) ] / 2
      sa = (exp(c1) - exp(-c1))/2.0     ! imaginary part

      ! X_alpha = - i nu_p S_alpha / ( omega p)
      !         = -i omega sqrt(1/alpha^2 - p^2) S_alpha / (omega p )
      !         = [ -i sqrt(1/alpha^2 - p^2) ] S_alpha / p
      !         = eta_alpha S_alpha / p
      xa = eta_alpha(j) * sa / ray_p

      ! Y_alpha = i omega  p S_alpha / nu_p
      !         = p S_alpha i omega / ( omega sqrt(1/alpha^2 - p^2) )
      !         = p S_alpha i / ( sqrt(1/alpha^2 - p^2) )
      !         = p S_alpha 1 / (-i sqrt(1/alpha^2 - p^2) )
      !         = p S_alpha / eta_alpha
      ya = ray_p * sa / eta_alpha(j)

      ! C_beta = cos(nu_s h) = cos( omega sqrt(1/beta^2 - p^2) h )
      ! S_beta = -sin(nu_s h) = -sin( omega sqrt(1/beta^2 - p^2) h )
      ! with nu_s h = omega sqrt(1/beta^2 - p^2) h
      !
      ! note: for sb, see same remark as above for sa
      c2 = nu_be(j) * hh(j)
      cb = (exp(c2) + exp(-c2))/2.0  ! cos(nu_s h)
      sb = (exp(c2) - exp(-c2))/2.0  ! sin(nu_s h) imaginary part

      ! X_beta = - i nu_s S_beta / ( omega p)
      ! Y_beta = i omega  p S_beta / nu_s
      xb = eta_beta(j) * sb / ray_p
      yb = ray_p * sb / eta_beta(j)

      ! layer factors
      g1 = gamma1(j)
      mul = mu(j)
      ! pre-computed factors
      ! gamma1^2
      g1_sq = g1 * g1
      ! 2 mu
      two_mul = 2.0 * mul ! note: leaving out factor k, only 2 mu

      ! Tong et al. (2014), appendix (A8)
      ! propagation matrix P_n
      P_layer(1,1) = ca - g1*cb
      P_layer(1,2) = xb - g1*ya
      !org: P_layer(1,3) = (ya - xb)/(2*mul)          ! misses factor 1/k
      !     P_layer(1,4) = (cb - ca)/(2*mul)          ! misses factor 1/k
      P_layer(1,3) = (ya - xb) / two_mul
      P_layer(1,4) = (cb - ca) / two_mul

      P_layer(2,1) = xa - g1*yb
      P_layer(2,2) = cb - g1*ca
      !org: P_layer(2,3) = (ca - cb)/(2*mul)          ! misses factor 1/k
      !     P_layer(2,4) = (yb - xa)/(2*mul)          ! misses factor 1/k
      P_layer(2,3) = (ca - cb) / two_mul
      P_layer(2,4) = (yb - xa) / two_mul

      !org: P_layer(3,1) = 2*mul * (xa - g1**2 * yb)  ! misses factor k
      !     P_layer(3,2) = 2*mul * g1 * (cb - ca)     ! misses factor k
      P_layer(3,1) = two_mul * (xa - g1_sq * yb)
      P_layer(3,2) = two_mul * g1 * (cb - ca)

      P_layer(3,3) = ca - g1*cb
      P_layer(3,4) = g1*yb - xa

      !org: P_layer(4,1) = 2*mul * g1 * (ca - cb)     ! misses factor k
      !     P_layer(4,2) = 2*mul * (xb - g1**2 * ya)  ! misses factor k
      P_layer(4,1) = two_mul * g1 * (ca - cb)
      P_layer(4,2) = two_mul * (xb - g1_sq * ya)
      P_layer(4,3) = g1*ya - xb
      P_layer(4,4) = cb - g1*ca

      !debug
      !if (myrank == 0) print *,'debug: j,g1,g1_sq,mul,two_mul,xa,xb,ya,yb,ca,cb,ray_p,om', &
      !                                 j,g1,g1_sq,mul,two_mul,xa,xb,ya,yb,ca,cb,ray_p,om
      !if (myrank == 0) print *,'debug: j,P_layer',j,P_layer(:,:)

      ! resulting matrix
      N_mat = gamma0(j) * matmul(P_layer,N_mat)
    enddo
  endif

  ! debug
  !if (myrank == 0) then
  !  print *,'debug: N_mat '
  !  do j = 1,4
  !    print *,N_mat(:,j)
  !  enddo
  !endif
  !stop

  end subroutine compute_N_Rayleigh

!
!-------------------------------------------------------------------------------------------------
!

  subroutine FFT(npow,xi,zign,dtt,mpow)

! Fourier transform
! This inputs AND outputs a complex function.
! The convention is FFT --> e^(-iwt)
! numerical factor for Plancherel theorem: planch_fac = dble(NPT * dt * dt)

  use fk_injection, only: CUSTOM_REAL

  implicit none

  integer, parameter :: CUSTOM_CMPLX = 8

  integer,intent(in) :: npow

  real(kind=CUSTOM_REAL),intent(in) :: zign,dtt

  complex(kind=CUSTOM_CMPLX),dimension(*),intent(inout) :: xi

!! DK DK here is the hardwired maximum size of the array
!! DK DK Aug 2016: if this routine is called many times (for different mesh points at which the SEM is coupled with FK)
!! DK DK Aug 2016: this should be moved to the calling program and precomputed once and for all
  real(kind=CUSTOM_REAL),intent(in) :: mpow(30)

  ! local parameters
  integer :: lblock,k,FK,jh,ii,istart
  integer :: l,iblock,nblock,i,lbhalf,j,lx
  complex(kind=CUSTOM_CMPLX) :: wk, hold, q
  real(kind=CUSTOM_REAL) :: flx,inv_of_flx,v
  ! PI = acos(-1.d0)
  real(kind=CUSTOM_REAL), parameter :: TWO_PI = 2.0_CUSTOM_REAL * acos(-1.d0)

!! DK DK added this sanity check
  if (npow > 30) stop 'error: the FK FTT routine has an hardwired maximum of 30 levels'
!! DK DK in any case the line below imposes a maximum of 31, otherwise the integer 2**n will overflow

  lx = 2**npow

  do l = 1,npow

    nblock = 2**(l-1)
    lblock = lx/nblock
    lbhalf = lblock/2

    k = 0

    do iblock = 1,nblock

      FK = k
      flx = lx

      v = zign * TWO_PI * FK / flx         ! Fourier convention

      ! - sign: MATLAB convention: forward e^{-i om t}
      ! + sign: engineering convention: forward e^{i om t}
      wk = cmplx(cos(v),-sin(v))   ! sign change to -sin(v) or sin(v)
      istart = lblock*(iblock-1)

      do i = 1,lbhalf
        j  = istart+i
        jh = j+lbhalf
        q = xi(jh)*wk
        xi(jh) = xi(j)-q
        xi(j)  = xi(j)+q
      enddo

      do i = 2,npow
        ii = i
        if (k < mpow(i)) goto 4
        k = k-mpow(i)
      enddo

    4 k = k+mpow(ii)

    enddo
  enddo

  k = 0

  do j = 1,lx
    if (k < j) goto 5

    hold = xi(j)
    xi(j) = xi(k+1)
    xi(k+1) = hold

5   do i = 1,npow
      ii = i
      if (k < mpow(i)) goto 7
      k = k-mpow(i)
    enddo

7   k = k+mpow(ii)
  enddo

  ! final steps deal with dt factors
  if (zign > 0.) then
    ! FORWARD FFT
    xi(1:lx) = xi(1:lx) * dtt    ! multiplication by dt

  else
    ! REVERSE FFT
    flx = flx*dtt
    inv_of_flx = 1._CUSTOM_REAL / flx

!! DK DK Aug 2016: changed to multiplication by the precomputed inverse to make the routine faster
!       xi(1:lx) = xi(1:lx) / flx         ! division by dt
    xi(1:lx) = xi(1:lx) * inv_of_flx  ! division by dt

  endif

  end subroutine FFT

!
!-------------------------------------------------------------------------------------------------
!

  subroutine FFTinv(npow,s,zign,dtt,r,mpow)

! inverse Fourier transform -- calls FFT

  use fk_injection, only: CUSTOM_REAL

  implicit none

  integer, parameter :: CUSTOM_CMPLX = 8

  integer,intent(in) :: npow
  real(kind=CUSTOM_REAL),intent(in)  :: dtt,zign

  complex(kind=CUSTOM_CMPLX), intent(inout) :: s(*)
  real(kind=CUSTOM_REAL), intent(out) :: r(*)   ! note that this is real, not double precision

!! DK DK here is the hardwired maximum size of the array
!! DK DK Aug 2016: if this routine is called many times (for different mesh points at which the SEM is coupled with FK)
!! DK DK Aug 2016: this should be moved to the calling program and precomputed once and for all
  real(kind=CUSTOM_REAL),intent(in) :: mpow(30)

  ! local parameters
  integer :: nsmp, nhalf

  nsmp = 2**npow
  nhalf = nsmp/2

  call rspec(s,nhalf)   ! restructuring
  call FFT(npow,s,zign,dtt,mpow)    ! Fourier transform

  r(1:nsmp) = real(s(1:nsmp))     ! take the real part

  end subroutine FFTinv

!
!-------------------------------------------------------------------------------------------------
!

  subroutine rspec(s,np2)

  implicit none

  integer, parameter :: CUSTOM_CMPLX = 8

  complex(kind=CUSTOM_CMPLX),intent(inout) :: s(*)
  integer, intent(in) :: np2

  ! local parameters
  integer :: n,n1,i

  n = 2*np2
  n1 = np2+1

  s(n1) = 0.0
  s(1)  = cmplx(real(s(1)),0.0)

  do i = 1,np2
    s(np2+i) = conjg(s(np2+2-i))
  enddo

  end subroutine rspec

!
!-------------------------------------------------------------------------------------------------
!

  subroutine find_size_of_working_arrays(deltat, freq_sampling_fk, tmax_fk, NF_FOR_STORING, &
                                         NF_FOR_FFT, NPOW_FOR_INTERP, NP_RESAMP, DF_FK)

  use fk_injection, only: CUSTOM_REAL, NSTEP

  implicit none
  real(kind=CUSTOM_REAL),intent(in)    :: deltat,freq_sampling_fk
  real(kind=CUSTOM_REAL),intent(inout) :: tmax_fk
  real(kind=CUSTOM_REAL),intent(inout) :: DF_FK
  integer,               intent(inout) :: NF_FOR_STORING, NF_FOR_FFT, NPOW_FOR_INTERP, NP_RESAMP
  ! local parameter
  real(kind=CUSTOM_REAL)               :: df, dt_min_fk, Frq_ech_Fk
  real(kind=CUSTOM_REAL)               :: tmax_samp, tmax_use

  ! sampling frequency to store fk solution
  Frq_ech_Fk = freq_sampling_fk

  ! sampling time step to store fk solution
  dt_min_fk = 1.0 /  Frq_ech_Fk

  ! compute resampling rate
  NP_RESAMP  = floor(dt_min_fk / deltat)

  ! checks sampling rate
  if (NP_RESAMP == 0) NP_RESAMP = 1

  ! update dt for fk with respect to integer np_resampling
  dt_min_fk = NP_RESAMP * deltat  !! this is the time step sampling for FK storage

  !! time window lengths
  ! maximum simulation time length would be:
  !   tmax_simulation = NSTEP * deltat
  ! FK signal trace is symmetric after inverse FFT, thus NF_FOR_STORING must match at least match NSTEP * 2 with resampling rate.
  ! maximum time length with respect to simulation NSTEP and resampling rate:
  tmax_samp = (2*NSTEP/NP_RESAMP + 1) * dt_min_fk

  ! take user defined window length as initial default
  tmax_use = tmax_fk

  ! limits window length to actual simulation length
  if (tmax_use > tmax_samp) tmax_use = tmax_samp

  ! compute number of time steps to store
  NF_FOR_STORING  = ceiling( tmax_use / dt_min_fk)

  ! in power of two
  NF_FOR_STORING  =   ceiling(log(real(NF_FOR_STORING))/log(2.))

  ! multiply by 2 in order to do an inverse FFT
  NF_FOR_FFT      =   2**(NF_FOR_STORING+1)

  NPOW_FOR_INTERP =   NF_FOR_STORING+1
  NF_FOR_STORING  =   2**NF_FOR_STORING

  ! now we have this new time window
  tmax_fk = dt_min_fk * (NF_FOR_FFT - 1)

  ! step in frequency for fk
  df = 1.0 / tmax_fk
  DF_FK = df

  !debug
  !print *,'debug: tmax ',tmax_fk,tmax_samp,tmax_use,'np_resamp',NP_RESAMP,'NSTEP',NSTEP,2*NSTEP/NP_RESAMP, &
  !                      'NF',NF_FOR_STORING,ceiling( tmax_use / dt_min_fk)

  end subroutine find_size_of_working_arrays


!
!-------------------------------------------------------------------------------------------------
!

!! #################  INTERPOLATION ROUTINES IN TIME DOMAIN ######################################

!! compute and store spline coefficients

  subroutine compute_spline_coef_to_store(Sig, npts, spline_coeff, tmp_c)

  use fk_injection, only: CUSTOM_REAL

  implicit none

  integer,                                             intent(in)     :: npts
  real(kind=CUSTOM_REAL), dimension(npts),             intent(in)     :: Sig
  real(kind=CUSTOM_REAL), dimension(npts),             intent(inout)  :: spline_coeff
  double precision, dimension(npts),intent(out)                       :: tmp_c  ! temporary work array

  !! computation in double precision
  double precision,parameter                                          :: error = 1.d-24
  double precision,parameter                                          :: z1 = dsqrt(3.d0) - 2.d0
  double precision                                                    :: zn, sumc
  integer                                                             :: i, n_init

  ! Compute pole value
  tmp_c(:) = dble(Sig(:)) * (1.d0 - z1) * ( 1.d0 - 1.d0/z1)

  ! Initialisation causal filter
  n_init = ceiling(log(error)/log(abs(z1)))

  ! check limits: by default is n_init==42, for very short test simulations this might be larger than npts
  if (n_init > npts) n_init = npts

  sumc = tmp_c(1)
  zn = z1
  do i = 1,n_init
     sumc = sumc + zn * tmp_c(i)
     zn = zn * z1
  enddo
  tmp_c(1) = sumc

  ! Causal filter
  do i = 2,npts
     tmp_c(i) = tmp_c(i) + z1 * tmp_c(i-1)
  enddo

  ! Initialisation anti-causal filter
  tmp_c(npts) = ( z1 / (z1 - 1.d0) ) * tmp_c(npts)
  do i = npts-1,1,-1
     tmp_c(i) = z1 * (tmp_c(i+1) - tmp_c(i))
  enddo

  !! store spline coeff in CUSTOM_REAL precision
  spline_coeff(:) = tmp_c(:)

  end subroutine compute_spline_coef_to_store


!
!-------------------------------------------------------------------------------------------------
!

!! VM VM READING INPUT FILE FOR FK MODEL

  subroutine ReadFKModelInput()

  !use specfem_par
  !use specfem_par_coupling
  use fk_injection, only: CUSTOM_REAL, TINYVAL, alpha_FK, beta_FK, &
                          rho_FK, mu_FK, h_FK, phi_FK, theta_FK, &
                          nlayer, IMAIN, myrank, &
                          xx0, yy0, zz0, tt0, ff0, freq_sampling_fk, &
                          tmax_fk, amplitude_fk, Z_REF_for_FK, NSTEP, deltat, &
                          type_kpsv_fk, FKMODEL_FILE

  implicit none

  !real(kind=CUSTOM_REAL), intent(in) :: Xmin_box, Xmax_box, Ymin_box, Ymax_box, Zmin_box, Zmax_box
  integer                :: ioerr
  character(len=100)     :: keyword, keyvalue, line
  character(len=100)     :: keyword_tmp, incident_wave

  real(kind=CUSTOM_REAL) :: rho_layer, vp_layer, vs_layer, ztop_layer
  real(kind=CUSTOM_REAL) :: Radius_box, wave_length_at_bottom
  real(kind=CUSTOM_REAL), dimension(:), allocatable  :: rho_fk_input, vp_fk_input, vs_fk_input, ztop_fk_input
  integer,  dimension(:), allocatable  :: ilayer_fk_input
  integer  :: ilayer,ier
  !logical  :: position_of_wavefront_not_read

  !!--------------------------------------------------------------
  ! # model description :
  ! NLAYER   n # number of layers
  ! LAYER 1  rho, vp ,vs, ztop
  ! LAYER 2  rho, vp, vs, ztop
  ! ...
  ! LAYER n  rho, vp, vs, ztop  # homogenoeus half-space
  ! #
  ! # incident wave description:
  ! INCIDENT_WAVE  "p" or "sv"
  ! BACK_AZITUTH    bazi
  ! INCIDENCE       inc
  ! ORIGIN_WAVEFRONT xx0, yy0, zz0
  ! ORIGIN_TIME      tt0
  ! FREQUENCY_MAX    ff0
  ! FREQUENCY_SAMPLING freq_sampling_fk
  ! TIME_WINDOW      tmax_fk
  ! AMPLITUDE        amplitude_fk
  !!----------------------------------------------------------------

  !! set default values
  tt0 = 0.0                 ! origin time
  tmax_fk = 128.0           ! time window length

  ff0 = 0.1                 ! frequency maximum in Hz
  freq_sampling_fk = 10.0   ! frequency sampling rate in Hz
  amplitude_fk = 1.0        ! amplitude factor

  type_kpsv_fk = 1  ! 1 == P-wave / 2 == SV-wave

  !position_of_wavefront_not_read = .true.

  !! READING input file
  open(85,file=trim(FKMODEL_FILE))
  do
     read(85, fmt='(a100)',iostat=ioerr) line
     !call remove_begin_blanks(line)
     if (ioerr < 0) exit
     if (len(trim(line)) < 1 .or. line(1:1) == '#') cycle
     read(line,*) keyword, keyvalue

     select case(trim(keyword))
     case('NLAYER')
        read(line, *) keyword_tmp, nlayer

        allocate(alpha_FK(nlayer), beta_FK(nlayer), rho_FK(nlayer), mu_FK(nlayer), h_FK(nlayer),stat=ier)
        if (ier /= 0) call exit_MPI_without_rank('error allocating arrays 2226')
        alpha_FK(:) = 0._CUSTOM_REAL; beta_FK(:) = 0._CUSTOM_REAL; rho_FK(:) = 0._CUSTOM_REAL
        mu_FK(:) = 0._CUSTOM_REAL; h_FK(:) = 0._CUSTOM_REAL

        allocate(rho_fk_input(nlayer), &
                 vp_fk_input(nlayer), &
                 vs_fk_input(nlayer), &
                 ztop_fk_input(nlayer+1), &
                 ilayer_fk_input(nlayer+1),stat=ier)
        if (ier /= 0) call exit_MPI_without_rank('error allocating arrays 2227')
        rho_fk_input(:) = 0._CUSTOM_REAL
        vp_fk_input(:) = 0._CUSTOM_REAL
        vs_fk_input(:) = 0._CUSTOM_REAL
        ztop_fk_input(:) = 0._CUSTOM_REAL
        ilayer_fk_input(:) = -1

     case('LAYER')
        read(line, *) keyword_tmp, ilayer, rho_layer, vp_layer, vs_layer, ztop_layer

        ilayer_fk_input(ilayer) = ilayer
        rho_fk_input(ilayer) = rho_layer
        vp_fk_input(ilayer) = vp_layer
        vs_fk_input(ilayer) = vs_layer
        ztop_fk_input(ilayer) = ztop_layer

        ! acoustic case: FK for zero-shear velocity not handled, here we set it to a (very) small value
        if (abs(vs_fk_input(ilayer)) < TINYVAL) vs_fk_input(ilayer) = 1.e-5

     case('INCIDENT_WAVE')
         read(line,*)  keyword_tmp, incident_wave

         select case(trim(incident_wave))
            case ('p', 'P')
              type_kpsv_fk = 1
            case('sv','SV')
              type_kpsv_fk = 2
            case default
              type_kpsv_fk = 1
            end select

     case('BACK_AZIMUTH')
        read(line,*)  keyword_tmp, phi_FK
        phi_FK = - phi_FK - 90.0

     case('AZIMUTH')
        read(line,*)  keyword_tmp, phi_FK
        phi_FK = 90.0 - phi_FK

     case('TAKE_OFF')
        read(line,*)  keyword_tmp, theta_FK

     case('ORIGIN_WAVEFRONT')
         read(line,*)  keyword_tmp, xx0, yy0, zz0
         !position_of_wavefront_not_read = .false.

     case('ORIGIN_TIME')
         read(line,*)  keyword_tmp, tt0

     case('NSTEP')
         read(line,*) keyword_tmp, NSTEP
    
     case('deltat')
         read(line,*) keyword_tmp, deltat

     case('FREQUENCY_MAX')
        read(line,*)  keyword_tmp, ff0

     case('FREQUENCY_SAMPLING')
        read(line,*)  keyword_tmp, freq_sampling_fk

     case('TIME_WINDOW')
        read(line,*)  keyword_tmp, tmax_fk

      case('AMPLITUDE')
        read(line,*)  keyword_tmp, amplitude_fk

     end select
  !!------------------------------------------------------------------------------------------------------
  enddo

  if (allocated(ilayer_fk_input)) then

     ilayer_fk_input(nlayer+1) = ilayer_fk_input(nlayer)
     ztop_fk_input(nlayer+1) = ztop_fk_input(nlayer)

     ! Z coordinate reference for top of lower-halfspace (last layer input)
     Z_REF_for_FK = ztop_fk_input(nlayer)

     do ilayer = 1, nlayer
        alpha_FK(ilayer) = vp_fk_input(ilayer)
        beta_FK(ilayer) = vs_fk_input(ilayer)
        rho_FK(ilayer) = rho_fk_input(ilayer)

        mu_FK(ilayer) = rho_fk_input(ilayer) * vs_fk_input(ilayer)**2
        h_FK(ilayer) =  ztop_fk_input(ilayer) - ztop_fk_input(ilayer+1)

        ! checks if layer has values
        if (ilayer_fk_input(ilayer) == -1) then
           write(*,*) " ERROR READING FK INPUT FILE "
           write(*,*) " MISSING LAYER ", ilayer
           stop 'Missing layer in FK model'
        endif

        ! checks vp,rho are strictly positive
        if (alpha_FK(ilayer) <= 0.0_CUSTOM_REAL .or. rho_FK(ilayer) <= 0.0_CUSTOM_REAL) then
          print *,'Error: invalid elastic material for FK coupling in layer ',ilayer
          print *,'  vp = ',alpha_FK(ilayer),' vs = ',beta_FK(ilayer),' rho = ',rho_FK(ilayer)
          print *,'vp & rho must be strictly positive'
          stop 'Invalid material for FK coupling found in ReadFKModelInput() routine'
        endif

        ! checks if vs is strictly positive for SV coupling
        if (type_kpsv_fk == 2) then
          if (beta_FK(ilayer) <= 0.0_CUSTOM_REAL) then
            print *,'Error: invalid elastic material for FK coupling in layer ',ilayer
            print *,'  vp = ',alpha_FK(ilayer),' vs = ',beta_FK(ilayer),' rho = ',rho_FK(ilayer)
            print *,'vp, vs & rho must be strictly positive (in particular vs must be > 0) for SV incident wave'
            stop 'Invalid elastic material for FK coupling found in ReadFKModelInput() routine'
          endif
        endif

     enddo

     deallocate(ilayer_fk_input, rho_fk_input, vp_fk_input, vs_fk_input, ztop_fk_input)

  else

     write(*,*) " ERROR READING FK INPUT FILE "
     write(*,*) " NOT BE ABLE TO READ MODEL PROPERTIES "
     stop 'Error reading FK input file'

  endif

  !! compute position of wave front
  !if (position_of_wavefront_not_read) then
  !  ! sets center point of box
  !  xx0 = 0.5*(Xmin_box + Xmax_box)
  !  yy0 = 0.5*(Ymin_box + Ymax_box)

  !  Radius_box = sqrt( (Xmin_box - xx0)**2 + (Ymin_box - yy0)**2)

  !  if (type_kpsv_fk == 1) then
  !    ! P-wave
  !    wave_length_at_bottom = alpha_FK(nlayer) / ff0    ! vp
  !  else if (type_kpsv_fk == 2) then
  !    ! SV-wave
  !    wave_length_at_bottom = beta_FK(nlayer) / ff0     ! vs
  !  endif

  !  ! depth position below bottom
  !  zz0 = Zmin_box - Radius_box * sin ( abs(theta_FK) * (PI / 180.d0) )  &
  !         - 3.0 * wave_length_at_bottom * cos ( abs(theta_FK) * (PI / 180.d0) )
  !endif

  ! user output
  if (myrank == 0) then
  write(IMAIN,*)
  write(IMAIN,*) "**********************************************"
  write(IMAIN,*) "         USING FK INJECTION TECHNIQUE         "
  write(IMAIN,*) "**********************************************"
  write(IMAIN,*)
  write(IMAIN,*) "  Model : " , nlayer , " layers "
  write(IMAIN,*)
  do ilayer = 1, nlayer
     write(IMAIN,'(a9, i3, 3(a6,2x,f8.3), 3x, a9, f18.5 )') &
          "   layer ", ilayer, &
          " rho =",   rho_FK(ilayer), &
          " vp  =",   alpha_FK(ilayer), &
          " vs  =",   beta_FK(ilayer), &
          " Height =", h_FK(ilayer)
  enddo
  write(IMAIN,*)
  write(IMAIN,*) "  FK (azimuth) angle phi   = ",   phi_FK,'(deg)'
  write(IMAIN,*) "  FK  take-off angle theta = ", theta_FK,'(deg)'
  write(IMAIN,*)
  write(IMAIN,*) "  Origin wavefront point FK           : ", xx0, yy0, zz0
  write(IMAIN,*) "  Time shift  FK                      : ", tt0
  write(IMAIN,*) "  Time discretization in SEM          : ", deltat
  write(IMAIN,*) "  Number of steps in SEM              : ", NSTEP
  write(IMAIN,*) "  Z reference for FK routine          : ", Z_REF_for_FK
  write(IMAIN,*)
  write(IMAIN,*) "  Time window for FK computing        : ", tmax_fk
  write(IMAIN,*) "  Frequency max                       : ", ff0
  write(IMAIN,*) "  Frequency sampling rate             : ", freq_sampling_fk
  write(IMAIN,*) "  Amplitude factor                    : ", amplitude_fk
  write(IMAIN,*)
  !write(IMAIN,*) "  Model boundary box                  : Xmin/Xmax = ",Xmin_box,Xmax_box
  !write(IMAIN,*) "                                      : Ymin/Ymax = ",Ymin_box,Ymax_box
  !write(IMAIN,*) "                                      : Zmin/Zmax = ",Zmin_box,Zmax_box
  write(IMAIN,*)
  write(IMAIN,*) "  Type of incoming wave (1=P), (2=SV) : ",type_kpsv_fk
  write(IMAIN,*)
  call flush_IMAIN()
  endif

  end subroutine ReadFKModelInput
