!{\src2tex{textfont=tt}}
!!****f* ABINIT/forstrnps
!! NAME
!! forstrnps
!!
!! FUNCTION
!! Compute nonlocal pseudopotential energy contribution to forces and/or stress tensor
!! as well as kinetic energy contribution to stress tensor.
!!
!! COPYRIGHT
!! Copyright (C) 1998-2018 ABINIT group (DCA, XG, GMR, AF, AR, MB, MT)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!!  cg(2,mcg)=wavefunctions (may be read from disk file)
!!  cprj(natom,mcprj*usecprj)=<p_lmn|Cnk> coefficients for each WF |Cnk> and each NL proj |p_lmn>
!!  ecut=cut-off energy for plane wave basis sphere (Ha)
!!  ecutsm=smearing energy for plane wave kinetic energy (Ha)
!!  effmass_free=effective mass for electrons (1. in common case)
!!  electronpositron <type(electronpositron_type)>=quantities for the electron-positron annihilation (optional argument)
!!  eigen(mband*nkpt*nsppol)=array for holding eigenvalues (hartree)
!!  fock <type(fock_type)>= quantities to calculate Fock exact exchange
!!  istwfk(nkpt)=input option parameter that describes the storage of wfs
!!  kg(3,mpw*mkmem)=reduced coordinates (integers) of G vecs in basis
!!  kpt(3,nkpt)=k points in reduced coordinates
!!  mband=maximum number of bands
!!  mcg=size of wave-functions array (cg) =mpw*nspinor*mband*mkmem*nsppol
!!  mcprj=size of projected wave-functions array (cprj) =nspinor*mband*mkmem*nsppol
!!  mgfft=maximum size of 1D FFTs
!!  mkmem=number of k points treated by this node.
!!  mpi_enreg=informations about MPI parallelization
!!  mpsang= 1+maximum angular momentum for nonlocal pseudopotentials
!!  mpw= maximum number of plane waves
!!  my_natom=number of atoms treated by current processor
!!  natom=number of atoms in cell.
!!  nband(nkpt)=number of bands at each k point
!!  nfft=number of FFT grid points
!!  ngfft(18)=contain all needed information about 3D FFT, see ~abinit/doc/variables/vargs.htm#ngfft
!!  nkpt=number of k points in Brillouin zone
!!  nloalg(3)=governs the choice of the algorithm for non-local operator.
!!  npwarr(nkpt)=number of planewaves in basis and boundary at each k
!!  nspden=Number of spin Density components
!!  nspinor=number of spinorial components of the wavefunctions
!!  nsppol=1 for unpolarized, 2 for spin-polarized
!!  nsym=number of elements in symmetry group
!!  ntypat=number of types of atoms
!!  nucdipmom(3,my_natom)= nuclear dipole moments
!!  occ(mband*nkpt*nsppol)=occupation numbers for each band over all k points
!!  optfor=1 if computation of forces is required
!!  paw_ij(my_natom*usepaw) <type(paw_ij_type)>=paw arrays given on (i,j) channels
!!  pawtab(ntypat*usepaw) <type(pawtab_type)>=paw tabulated starting data
!!  ph1d(2,3*(2*mgfft+1)*natom)=one-dimensional structure factor information
!!  psps <type(pseudopotential_type)>=variables related to pseudopotentials
!!  rprimd(3,3)=dimensional primitive translations in real space (bohr)
!!  stress_needed=1 if computation of stress tensor is required
!!  symrec(3,3,nsym)=symmetries in reciprocal space (dimensionless)
!!  typat(natom)=type of each atom
!!  usecprj=1 if cprj datastructure has been allocated
!!  use_gpu_cuda= 0 or 1 to know if we use cuda for nonlop call
!!  wtk(nkpt)=weight associated with each k point
!!  xred(3,natom)=reduced dimensionless atomic coordinates
!!  ylm(mpw*mkmem,mpsang*mpsang*useylm)= real spherical harmonics for each G and k point
!!  ylmgr(mpw*mkmem,3,mpsang*mpsang*useylm)= gradients of real spherical harmonics
!!
!! OUTPUT
!!  if (optfor==1)
!!   grnl(3*natom*optfor)=stores grads of nonlocal energy wrt atomic coordinates
!!  if (stress_needed==1)
!!   kinstr(6)=kinetic energy part of stress tensor (hartree/bohr^3)
!!   Store 6 unique components of symmetric 3x3 tensor in the order
!!   11, 22, 33, 32, 31, 21
!!   npsstr(6)=nonlocal pseudopotential energy part of stress tensor
!!    (hartree/bohr^3)
!!
!! PARENTS
!!      forstr
!!
!! CHILDREN
!!      bandfft_kpt_restoretabs,bandfft_kpt_savetabs,destroy_hamiltonian
!!      fock_getghc,init_hamiltonian,load_k_hamiltonian,load_spin_hamiltonian
!!      meanvalue_g,mkffnl,mkkpg,nonlop,pawcprj_alloc,pawcprj_free,pawcprj_get
!!      pawcprj_reorder,prep_bandfft_tabs,prep_nonlop,stresssym,timab,xmpi_sum
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine forstrnps(cg,cprj,ecut,ecutsm,effmass_free,eigen,electronpositron,fock,&
&  grnl,istwfk,kg,kinstr,npsstr,kpt,mband,mcg,mcprj,mgfft,mkmem,mpi_enreg,mpsang,&
&  mpw,my_natom,natom,nband,nfft,ngfft,nkpt,nloalg,npwarr,nspden,nspinor,nsppol,nsym,&
&  ntypat,nucdipmom,occ,optfor,paw_ij,pawtab,ph1d,psps,rprimd,&
&  stress_needed,symrec,typat,usecprj,usefock,use_gpu_cuda,wtk,xred,ylm,ylmgr)

 use defs_basis
 use defs_datatypes
 use defs_abitypes
 use m_profiling_abi
 use m_xmpi
 use m_errors
 use m_fock
 use m_hamiltonian,      only : init_hamiltonian,destroy_hamiltonian,load_spin_hamiltonian,&
&                               load_k_hamiltonian,gs_hamiltonian_type,load_kprime_hamiltonian!,K_H_KPRIME
 use m_electronpositron, only : electronpositron_type,electronpositron_calctype
 use m_bandfft_kpt,      only : bandfft_kpt,bandfft_kpt_type,&
&                               bandfft_kpt_savetabs,bandfft_kpt_restoretabs
 use m_pawtab,           only : pawtab_type
 use m_paw_ij,           only : paw_ij_type
 use m_pawcprj,          only : pawcprj_type,pawcprj_alloc,pawcprj_free,pawcprj_get,pawcprj_reorder
use m_cgtools

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'forstrnps'
 use interfaces_18_timing
 use interfaces_32_util
 use interfaces_41_geometry
 use interfaces_53_spacepar
 use interfaces_66_nonlocal
 use interfaces_66_wfs
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 integer,intent(in) :: mband,mcg,mcprj,mgfft,mkmem,mpsang,mpw,my_natom,natom,nfft,nkpt
 integer,intent(in) :: nspden,nsppol,nspinor,nsym,ntypat,optfor,stress_needed
 integer,intent(in) :: usecprj,usefock,use_gpu_cuda
 real(dp),intent(in) :: ecut,ecutsm,effmass_free
 type(electronpositron_type),pointer :: electronpositron
 type(MPI_type),intent(inout) :: mpi_enreg
 type(pseudopotential_type),intent(in) :: psps
!arrays
 integer,intent(in) :: istwfk(nkpt),kg(3,mpw*mkmem),nband(nkpt*nsppol)
 integer,intent(in) :: ngfft(18),nloalg(3),npwarr(nkpt)
 integer,intent(in) :: symrec(3,3,nsym),typat(natom)
 real(dp),intent(in) :: cg(2,mcg)
 real(dp),intent(in) :: eigen(mband*nkpt*nsppol),kpt(3,nkpt),nucdipmom(3,my_natom)
 real(dp),intent(in) :: occ(mband*nkpt*nsppol),ph1d(2,3*(2*mgfft+1)*natom)
 real(dp),intent(in) :: rprimd(3,3),wtk(nkpt),xred(3,natom)
 real(dp),intent(in) :: ylm(mpw*mkmem,mpsang*mpsang*psps%useylm)
 real(dp),intent(in) :: ylmgr(mpw*mkmem,3,mpsang*mpsang*psps%useylm)
 real(dp),intent(out) :: grnl(3*natom*optfor),kinstr(6),npsstr(6)
 type(pawcprj_type),intent(inout) :: cprj(natom,mcprj*usecprj)
 type(paw_ij_type),intent(in) :: paw_ij(my_natom*psps%usepaw)
 type(pawtab_type),intent(in) :: pawtab(ntypat*psps%usepaw)
 type(fock_type),pointer, intent(inout) :: fock
!Local variables-------------------------------
!scalars
 integer,parameter :: tim_rwwf=7
 integer :: bandpp,bdtot_index,choice,cpopt,dimffnl,dimffnl_str,iband,iband_cprj,iband_last,ibg,icg,ider,ider_str
 integer :: idir,idir_str,ierr,ii,ikg,ikpt,ilm,ipositron,ipw,ishift,isppol,istwf_k
 integer :: mband_cprj,me_distrb,my_ikpt,my_nspinor,nband_k,nband_cprj_k,ndat,nkpg
 integer :: nnlout,npw_k,paw_opt,signs,spaceComm
 integer :: tim_nonlop,tim_nonlop_prep,usecprj_local,use_ACE_old
 integer :: blocksize,iblock,iblocksize,ibs,nblockbd
 real(dp) :: ar,renorm_factor,dfsm,ecutsm_inv,fact_kin,fsm,htpisq,kgc1
 real(dp) :: kgc2,kgc3,kin,xx
 type(gs_hamiltonian_type) :: gs_hamk
 logical :: compute_gbound,usefock_loc
 character(len=500) :: msg
 type(fock_common_type),pointer :: fockcommon
!arrays
 integer,allocatable :: kg_k(:,:)
 real(dp) :: kpoint(3),nonlop_dum(1,1),rmet(3,3),tsec(2)
 real(dp),allocatable :: cwavef(:,:),enlout(:),ffnl_sav(:,:,:,:),ffnl_str(:,:,:,:)
 real(dp),allocatable :: ghc_dum(:,:),gprimd(:,:),kpg_k(:,:),kpg_k_sav(:,:)
 real(dp),allocatable :: kstr1(:),kstr2(:),kstr3(:),kstr4(:),kstr5(:),kstr6(:)
 real(dp),allocatable :: lambda(:),occblock(:),ph3d(:,:,:),ph3d_sav(:,:,:)
 real(dp),allocatable :: weight(:),ylm_k(:,:),ylmgr_k(:,:,:)
 real(dp),allocatable,target :: ffnl(:,:,:,:)
 type(bandfft_kpt_type),pointer :: my_bandfft_kpt => null()
 type(pawcprj_type),target,allocatable :: cwaveprj(:,:)
 type(pawcprj_type),pointer :: cwaveprj_idat(:,:)


!*************************************************************************

 call timab(920,1,tsec)
 call timab(921,1,tsec)

!Init mpicomm and me
 if(mpi_enreg%paral_kgb==1)then
   spaceComm=mpi_enreg%comm_kpt
   me_distrb=mpi_enreg%me_kpt
 else
!* In case of HF calculation
   if (mpi_enreg%paral_hf==1) then
     spaceComm=mpi_enreg%comm_kpt
     me_distrb=mpi_enreg%me_kpt
   else
     spaceComm=mpi_enreg%comm_cell
     me_distrb=mpi_enreg%me_cell
   end if
 end if

!Some constants
 ipositron=abs(electronpositron_calctype(electronpositron))
 my_nspinor=max(1,nspinor/mpi_enreg%nproc_spinor)
!Smearing of plane wave kinetic energy
 ecutsm_inv=zero;if( ecutsm>1.0d-20) ecutsm_inv=1/ecutsm
!htpisq is (1/2) (2 Pi) **2:
 htpisq=0.5_dp*(two_pi)**2

!Check that fock is present if want to use fock option
 compute_gbound=.false.
 usefock_loc = (usefock==1 .and. associated(fock))
!Arrays initializations
 grnl(:)=zero
 if (usefock_loc) then
   fockcommon =>fock%fock_common
   fockcommon%optfor=.false.
   fockcommon%optstr=.false.
   use_ACE_old=fockcommon%use_ACE
   fockcommon%use_ACE=0
   if (fockcommon%optfor) compute_gbound=.true.
 end if
 if (stress_needed==1) then
   kinstr(:)=zero;npsstr(:)=zero
   if (usefock_loc) then
     fockcommon%optstr=.TRUE.
     fockcommon%stress=zero
     compute_gbound=.true.
   end if
 end if
 
 usecprj_local=usecprj

 if ((usefock_loc).and.(psps%usepaw==1)) then
   usecprj_local=1
   if(optfor==1)then 
     fockcommon%optfor=.true.
     if (.not.allocated(fockcommon%forces_ikpt)) then
       ABI_ALLOCATE(fockcommon%forces_ikpt,(3,natom,mband))
     end if
     if (.not.allocated(fockcommon%forces)) then
       ABI_ALLOCATE(fockcommon%forces,(3,natom))
     end if
     fockcommon%forces=zero
     compute_gbound=.true.
   end if
 end if

!Initialize Hamiltonian (k-independent terms)

 call init_hamiltonian(gs_hamk,psps,pawtab,nspinor,nsppol,nspden,natom,&
& typat,xred,nfft,mgfft,ngfft,rprimd,nloalg,usecprj=usecprj_local,&
& comm_atom=mpi_enreg%comm_atom,mpi_atmtab=mpi_enreg%my_atmtab,mpi_spintab=mpi_enreg%my_isppoltab,&
& paw_ij=paw_ij,ph1d=ph1d,electronpositron=electronpositron,fock=fock,&
& nucdipmom=nucdipmom,use_gpu_cuda=use_gpu_cuda)
 rmet = MATMUL(TRANSPOSE(rprimd),rprimd)
 call timab(921,2,tsec)

!need to reorder cprj=<p_lmn|Cnk> (from unsorted to atom-sorted)
 if (psps%usepaw==1.and.usecprj_local==1) then
   call pawcprj_reorder(cprj,gs_hamk%atindx)
 end if

!Common data for "nonlop" routine
 signs=1 ; idir=0  ; ishift=0 ; tim_nonlop=4 ; tim_nonlop_prep=12
 choice=2*optfor;if (stress_needed==1) choice=10*choice+3
 if (optfor==1.and.stress_needed==1)  ishift=6
 nnlout=max(1,6*stress_needed+3*natom*optfor)
 if (psps%usepaw==0) then
   paw_opt=0 ; cpopt=-1
 else
   paw_opt=2 ; cpopt=-1+3*usecprj_local
 end if

 call timab(921,2,tsec)

!LOOP OVER SPINS
 bdtot_index=0;ibg=0;icg=0
 do isppol=1,nsppol

!  Continue to initialize the Hamiltonian (PAW DIJ coefficients)
   call load_spin_hamiltonian(gs_hamk,isppol,with_nonlocal=.true.)
   if (usefock_loc) fockcommon%isppol=isppol

!  Loop over k points
   ikg=0
   do ikpt=1,nkpt
     if (usefock_loc) fockcommon%ikpt=ikpt
     nband_k=nband(ikpt+(isppol-1)*nkpt)
     istwf_k=istwfk(ikpt)
     npw_k=npwarr(ikpt)
     kpoint(:)=kpt(:,ikpt)

     if(proc_distrb_cycle(mpi_enreg%proc_distrb,ikpt,1,nband_k,isppol,me_distrb)) then
       bdtot_index=bdtot_index+nband_k
       cycle
     end if

     call timab(922,1,tsec)

!    Parallelism over FFT and/or bands: define sizes and tabs
     if (mpi_enreg%paral_kgb==1) then
       my_ikpt=mpi_enreg%my_kpttab(ikpt)
       nblockbd=nband_k/(mpi_enreg%nproc_band*mpi_enreg%bandpp)
       bandpp=mpi_enreg%bandpp
       my_bandfft_kpt => bandfft_kpt(my_ikpt)
     else
       my_ikpt=ikpt
       bandpp=mpi_enreg%bandpp
       nblockbd=nband_k/bandpp
     end if
     blocksize=nband_k/nblockbd
     mband_cprj=mband/mpi_enreg%nproc_band
     nband_cprj_k=nband_k/mpi_enreg%nproc_band

     ABI_ALLOCATE(cwavef,(2,npw_k*my_nspinor*blocksize))
     if (psps%usepaw==1.and.usecprj_local==1) then
       ABI_DATATYPE_ALLOCATE(cwaveprj,(natom,my_nspinor*bandpp))
       call pawcprj_alloc(cwaveprj,0,gs_hamk%dimcprj)
     else
       ABI_DATATYPE_ALLOCATE(cwaveprj,(0,0))
     end if

     if (stress_needed==1) then
       ABI_ALLOCATE(kstr1,(npw_k))
       ABI_ALLOCATE(kstr2,(npw_k))
       ABI_ALLOCATE(kstr3,(npw_k))
       ABI_ALLOCATE(kstr4,(npw_k))
       ABI_ALLOCATE(kstr5,(npw_k))
       ABI_ALLOCATE(kstr6,(npw_k))
     end if

     ABI_ALLOCATE(kg_k,(3,mpw))
!$OMP PARALLEL DO
     do ipw=1,npw_k
       kg_k(:,ipw)=kg(:,ipw+ikg)
     end do

     ABI_ALLOCATE(ylm_k,(npw_k,mpsang*mpsang*psps%useylm))
     if (stress_needed==1) then
       ABI_ALLOCATE(ylmgr_k,(npw_k,3,mpsang*mpsang*psps%useylm))
     else
       ABI_ALLOCATE(ylmgr_k,(0,0,0))
     end if
     if (psps%useylm==1) then
!$OMP PARALLEL DO COLLAPSE(2)
       do ilm=1,mpsang*mpsang
         do ipw=1,npw_k
           ylm_k(ipw,ilm)=ylm(ipw+ikg,ilm)
         end do
       end do
       if (stress_needed==1) then
!$OMP PARALLEL DO COLLAPSE(2)
         do ilm=1,mpsang*mpsang
           do ii=1,3
             do ipw=1,npw_k
               ylmgr_k(ipw,ii,ilm)=ylmgr(ipw+ikg,ii,ilm)
             end do
           end do
         end do
       end if
     end if

!    Prepare kinetic contribution to stress tensor (Warning : the symmetry
!    has not been broken, like in mkkin.f or kpg3.f . It should be, in order to be coherent).
     if (stress_needed==1) then
       ABI_ALLOCATE(gprimd,(3,3))
       gprimd=gs_hamk%gprimd
!$OMP PARALLEL DO PRIVATE(fact_kin,ipw,kgc1,kgc2,kgc3,kin,xx,fsm,dfsm) &
!$OMP&SHARED(ecut,ecutsm,ecutsm_inv,gs_hamk,htpisq,kg_k,kpoint,kstr1,kstr2,kstr3,kstr4,kstr5,kstr6,npw_k)
       do ipw=1,npw_k
!        Compute Cartesian coordinates of (k+G)
         kgc1=gprimd(1,1)*(kpoint(1)+kg_k(1,ipw))+&
&         gprimd(1,2)*(kpoint(2)+kg_k(2,ipw))+&
&         gprimd(1,3)*(kpoint(3)+kg_k(3,ipw))
         kgc2=gprimd(2,1)*(kpoint(1)+kg_k(1,ipw))+&
&         gprimd(2,2)*(kpoint(2)+kg_k(2,ipw))+&
&         gprimd(2,3)*(kpoint(3)+kg_k(3,ipw))
         kgc3=gprimd(3,1)*(kpoint(1)+kg_k(1,ipw))+&
&         gprimd(3,2)*(kpoint(2)+kg_k(2,ipw))+&
&         gprimd(3,3)*(kpoint(3)+kg_k(3,ipw))
         kin=htpisq* ( kgc1**2 + kgc2**2 + kgc3**2 )
         fact_kin=1.0_dp
         if(kin>ecut-ecutsm)then
           if(kin>ecut)then
             fact_kin=0.0_dp
           else
!            See the routine mkkin.f, for the smearing procedure
             xx=(ecut-kin)*ecutsm_inv
!            This kinetic cutoff smoothing function and its xx derivatives
!            were produced with Mathematica and the fortran code has been
!            numerically checked against Mathematica.
             fsm=1.0_dp/(xx**2*(3+xx*(1+xx*(-6+3*xx))))
             dfsm=-3.0_dp*(-1+xx)**2*xx*(2+5*xx)*fsm**2
!            d2fsm=6.0_dp*xx**2*(9+xx*(8+xx*(-52+xx*(-3+xx*(137+xx*&
!            &                         (-144+45*xx))))))*fsm**3
             fact_kin=fsm+kin*(-ecutsm_inv)*dfsm
           end if
         end if
         kstr1(ipw)=fact_kin*kgc1*kgc1
         kstr2(ipw)=fact_kin*kgc2*kgc2
         kstr3(ipw)=fact_kin*kgc3*kgc3
         kstr4(ipw)=fact_kin*kgc3*kgc2
         kstr5(ipw)=fact_kin*kgc3*kgc1
         kstr6(ipw)=fact_kin*kgc2*kgc1
       end do ! ipw
       ABI_DEALLOCATE(gprimd)
     end if

!    Compute (k+G) vectors
     nkpg=3*nloalg(3)
     ABI_ALLOCATE(kpg_k,(npw_k,nkpg))
     if (nkpg>0) then
       call mkkpg(kg_k,kpg_k,kpoint,nkpg,npw_k)
     end if

!    Compute nonlocal form factors ffnl at all (k+G)
     ider=0;idir=0;dimffnl=1
     if (stress_needed==1) then
       ider=1;dimffnl=2+2*psps%useylm
     end if
     ABI_ALLOCATE(ffnl,(npw_k,dimffnl,psps%lmnmax,ntypat))
     call mkffnl(psps%dimekb,dimffnl,psps%ekb,ffnl,psps%ffspl,gs_hamk%gmet,gs_hamk%gprimd,&
&     ider,idir,psps%indlmn,kg_k,kpg_k,kpoint,psps%lmnmax,psps%lnmax,psps%mpsang,psps%mqgrid_ff,&
&     nkpg,npw_k,ntypat,psps%pspso,psps%qgrid_ff,rmet,psps%usepaw,psps%useylm,ylm_k,ylmgr_k)
     if ((stress_needed==1).and.(usefock_loc).and.(psps%usepaw==1))then
       ider_str=1; dimffnl_str=7;idir_str=-7
       ABI_ALLOCATE(ffnl_str,(npw_k,dimffnl_str,psps%lmnmax,ntypat))
       call mkffnl(psps%dimekb,dimffnl_str,psps%ekb,ffnl_str,psps%ffspl,gs_hamk%gmet,gs_hamk%gprimd,&
&       ider_str,idir_str,psps%indlmn,kg_k,kpg_k,kpoint,psps%lmnmax,psps%lnmax,psps%mpsang,psps%mqgrid_ff,&
&       nkpg,npw_k,ntypat,psps%pspso,psps%qgrid_ff,rmet,psps%usepaw,psps%useylm,ylm_k,ylmgr_k)
     end if

!    Load k-dependent part in the Hamiltonian datastructure
!     - Compute 3D phase factors
!     - Prepare various tabs in case of band-FFT parallelism
!     - Load k-dependent quantities in the Hamiltonian
     ABI_ALLOCATE(ph3d,(2,npw_k,gs_hamk%matblk))
     call load_k_hamiltonian(gs_hamk,kpt_k=kpoint,istwf_k=istwf_k,npw_k=npw_k,&
&     kg_k=kg_k,kpg_k=kpg_k,ffnl_k=ffnl,ph3d_k=ph3d,compute_gbound=compute_gbound,compute_ph3d=.true.)

!    Load band-FFT tabs (transposed k-dependent arrays)
     if (mpi_enreg%paral_kgb==1) then
       call bandfft_kpt_savetabs(my_bandfft_kpt,ffnl=ffnl_sav,ph3d=ph3d_sav,kpg=kpg_k_sav)
       call prep_bandfft_tabs(gs_hamk,ikpt,mkmem,mpi_enreg)
       call load_k_hamiltonian(gs_hamk,npw_fft_k=my_bandfft_kpt%ndatarecv, &
&       kg_k     =my_bandfft_kpt%kg_k_gather, &
&       kpg_k    =my_bandfft_kpt%kpg_k_gather, &
       ffnl_k   =my_bandfft_kpt%ffnl_gather, &
       ph3d_k   =my_bandfft_kpt%ph3d_gather,compute_gbound=compute_gbound)
     end if

     call timab(922,2,tsec)

!    Loop over (blocks of) bands; accumulate forces and/or stresses
!    The following is now wrong. In sequential, nblockbd=nband_k/bandpp
!    blocksize= bandpp (JB 2016/04/16)
!    Note that in sequential mode iblock=iband, nblockbd=nband_k and blocksize=1
     ABI_ALLOCATE(lambda,(blocksize))
     ABI_ALLOCATE(occblock,(blocksize))
     ABI_ALLOCATE(weight,(blocksize))
     ABI_ALLOCATE(enlout,(nnlout*blocksize))
     occblock=zero;weight=zero;enlout(:)=zero
     if (usefock_loc) then
       if (fockcommon%optstr) then
         ABI_ALLOCATE(fockcommon%stress_ikpt,(6,nband_k))
         fockcommon%stress_ikpt=zero
       end if
     end if
     if ((usefock_loc).and.(psps%usepaw==1)) then
       if (fockcommon%optfor) then
         fockcommon%forces_ikpt=zero
       end if
     end if

     do iblock=1,nblockbd

       iband=(iblock-1)*blocksize+1;iband_last=min(iband+blocksize-1,nband_k)
       iband_cprj=(iblock-1)*bandpp+1
       if(proc_distrb_cycle(mpi_enreg%proc_distrb,ikpt,iband,iband_last,isppol,me_distrb)) cycle

!      Select occupied bandsddk
       occblock(:)=occ(1+(iblock-1)*blocksize+bdtot_index:iblock*blocksize+bdtot_index)
       if( abs(maxval(occblock))>=tol8 ) then
         call timab(923,1,tsec)
         weight(:)=wtk(ikpt)*occblock(:)

!        gs_hamk%ffnl_k is changed in fock_getghc, so that it is necessary to restore it when stresses are to be calculated.
         if ((stress_needed==1).and.(usefock_loc).and.(psps%usepaw==1))then
           call load_k_hamiltonian(gs_hamk,ffnl_k=ffnl)
         end if

!        Load contribution from n,k
         cwavef(:,1:npw_k*my_nspinor*blocksize)=&
&         cg(:,1+(iblock-1)*npw_k*my_nspinor*blocksize+icg:iblock*npw_k*my_nspinor*blocksize+icg)
         if (psps%usepaw==1.and.usecprj_local==1) then
           call pawcprj_get(gs_hamk%atindx1,cwaveprj,cprj,natom,iband_cprj,ibg,ikpt,0,isppol,&
&           mband_cprj,mkmem,natom,bandpp,nband_cprj_k,my_nspinor,nsppol,0,&
&           mpicomm=mpi_enreg%comm_kpt,proc_distrb=mpi_enreg%proc_distrb)
         end if

         call timab(923,2,tsec)
         call timab(926,1,tsec)

         lambda(1:blocksize)= eigen(1+(iblock-1)*blocksize+bdtot_index:iblock*blocksize+bdtot_index)
         if (mpi_enreg%paral_kgb/=1) then
           call nonlop(choice,cpopt,cwaveprj,enlout,gs_hamk,idir,lambda,mpi_enreg,blocksize,nnlout,&
&           paw_opt,signs,nonlop_dum,tim_nonlop,cwavef,cwavef)
         else
           call prep_nonlop(choice,cpopt,cwaveprj,enlout,gs_hamk,idir,lambda,blocksize,&
&           mpi_enreg,nnlout,paw_opt,signs,nonlop_dum,tim_nonlop_prep,cwavef,cwavef)
         end if
         if ((stress_needed==1).and.(usefock_loc).and.(psps%usepaw==1))then
           call load_k_hamiltonian(gs_hamk,ffnl_k=ffnl_str)
         end if
         call timab(926,2,tsec)

!        Accumulate non-local contributions from n,k
         if (optfor==1) then
           do iblocksize=1,blocksize
             ibs=nnlout*(iblocksize-1)
             grnl(1:3*natom)=grnl(1:3*natom)+weight(iblocksize)*enlout(ibs+1+ishift:ibs+3*natom+ishift)
           end do
         end if
         if (stress_needed==1) then
           do iblocksize=1,blocksize
             ibs=nnlout*(iblocksize-1)
             npsstr(1:6)=npsstr(1:6) + weight(iblocksize)*enlout(ibs+1:ibs+6)
           end do
         end if

!        Accumulate stress tensor kinetic contributions
         if (stress_needed==1) then
           call timab(924,1,tsec)
           do iblocksize=1,blocksize
             call meanvalue_g(ar,kstr1,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(1)=kinstr(1)+weight(iblocksize)*ar
             call meanvalue_g(ar,kstr2,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(2)=kinstr(2)+weight(iblocksize)*ar
             call meanvalue_g(ar,kstr3,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(3)=kinstr(3)+weight(iblocksize)*ar
             call meanvalue_g(ar,kstr4,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(4)=kinstr(4)+weight(iblocksize)*ar
             call meanvalue_g(ar,kstr5,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(5)=kinstr(5)+weight(iblocksize)*ar
             call meanvalue_g(ar,kstr6,0,istwf_k,mpi_enreg,npw_k,my_nspinor,&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),&
&             cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),0)
             kinstr(6)=kinstr(6)+weight(iblocksize)*ar
           end do
           call timab(924,2,tsec)
         end if

!        Accumulate stress tensor and forces for the Fock part
         if (usefock_loc) then
           if(fockcommon%optstr.or.fockcommon%optfor) then
             if (mpi_enreg%paral_kgb==1) then
               msg='forsrtnps: Paral_kgb is not yet implemented for fock stresses'
               MSG_BUG(msg)
             end if 
             ndat=mpi_enreg%bandpp
             if (gs_hamk%usepaw==0) cwaveprj_idat => cwaveprj
             ABI_ALLOCATE(ghc_dum,(0,0))
             do iblocksize=1,blocksize
               fockcommon%ieigen=(iblock-1)*blocksize+iblocksize
               fockcommon%iband=(iblock-1)*blocksize+iblocksize
               if (gs_hamk%usepaw==1) then
                 cwaveprj_idat => cwaveprj(:,(iblocksize-1)*my_nspinor+1:iblocksize*my_nspinor)
               end if
               call fock_getghc(cwavef(:,1+(iblocksize-1)*npw_k*my_nspinor:iblocksize*npw_k*my_nspinor),cwaveprj_idat,&
&               ghc_dum,gs_hamk,mpi_enreg)
               if (fockcommon%optstr) then
                 fockcommon%stress(:)=fockcommon%stress(:)+weight(iblocksize)*fockcommon%stress_ikpt(:,fockcommon%ieigen)
               end if
               if (fockcommon%optfor) then
                 fockcommon%forces(:,:)=fockcommon%forces(:,:)+weight(iblocksize)*fockcommon%forces_ikpt(:,:,fockcommon%ieigen)
               end if
             end do 
             ABI_DEALLOCATE(ghc_dum)
           end if
         end if
       end if

     end do ! End of loop on block of bands

!    Restore the bandfft tabs
     if (mpi_enreg%paral_kgb==1) then
       call bandfft_kpt_restoretabs(my_bandfft_kpt,ffnl=ffnl_sav,ph3d=ph3d_sav,kpg=kpg_k_sav)
     end if

!    Increment indexes
     bdtot_index=bdtot_index+nband_k
     if (mkmem/=0) then
       ibg=ibg+my_nspinor*nband_cprj_k
       icg=icg+npw_k*my_nspinor*nband_k
       ikg=ikg+npw_k
     end if

     if (usefock_loc) then
       if (fockcommon%optstr) then
         ABI_DEALLOCATE(fockcommon%stress_ikpt)
       end if
     end if

     if (psps%usepaw==1) then
       call pawcprj_free(cwaveprj)
     end if
     ABI_DATATYPE_DEALLOCATE(cwaveprj)
     ABI_DEALLOCATE(cwavef)

     ABI_DEALLOCATE(lambda)
     ABI_DEALLOCATE(occblock)
     ABI_DEALLOCATE(weight)
     ABI_DEALLOCATE(enlout)
     ABI_DEALLOCATE(ffnl)
     ABI_DEALLOCATE(kg_k)
     ABI_DEALLOCATE(kpg_k)
     ABI_DEALLOCATE(ylm_k)
     ABI_DEALLOCATE(ylmgr_k)
     ABI_DEALLOCATE(ph3d)
     if (stress_needed==1) then
       ABI_DEALLOCATE(kstr1)
       ABI_DEALLOCATE(kstr2)
       ABI_DEALLOCATE(kstr3)
       ABI_DEALLOCATE(kstr4)
       ABI_DEALLOCATE(kstr5)
       ABI_DEALLOCATE(kstr6)
     end if
     if ((stress_needed==1).and.(usefock_loc).and.(psps%usepaw==1))then
       ABI_DEALLOCATE(ffnl_str)
     end if

   end do ! End k point loop
 end do ! End loop over spins

!Stress is equal to dE/d_strain * (1/ucvol)
 npsstr(:)=npsstr(:)/gs_hamk%ucvol

!Parallel case: accumulate (n,k) contributions
 if (xmpi_paral==1) then
!  Forces
   if (optfor==1) then
     call timab(65,1,tsec)
     call xmpi_sum(grnl,spaceComm,ierr)
     call timab(65,2,tsec)
     if ((usefock_loc).and.(psps%usepaw==1)) then
       call xmpi_sum(fockcommon%forces,spaceComm,ierr)
     end if
   end if
!  Stresses
   if (stress_needed==1) then
     call timab(65,1,tsec)
     call xmpi_sum(kinstr,spaceComm,ierr)
     call xmpi_sum(npsstr,spaceComm,ierr)
     if ((usefock_loc).and.(fockcommon%optstr)) then
       call xmpi_sum(fockcommon%stress,spaceComm,ierr)
     end if
     call timab(65,2,tsec)
   end if
 end if

 call timab(925,1,tsec)

!Do final normalizations and symmetrizations of stress tensor contributions
 if (stress_needed==1) then
   renorm_factor=-(two_pi**2)/effmass_free/gs_hamk%ucvol
   kinstr(:)=kinstr(:)*renorm_factor
   if (nsym>1) then
     call stresssym(gs_hamk%gprimd,nsym,kinstr,symrec)
     call stresssym(gs_hamk%gprimd,nsym,npsstr,symrec)
     if ((usefock_loc).and.(fockcommon%optstr)) then
       call stresssym(gs_hamk%gprimd,nsym,fockcommon%stress,symrec)
     end if
   end if
 end if

!Need to reorder cprj=<p_lmn|Cnk> (from atom-sorted to unsorted)
 if (psps%usepaw==1.and.usecprj_local==1) then
   call pawcprj_reorder(cprj,gs_hamk%atindx1)
 end if

!Deallocate temporary space
 call destroy_hamiltonian(gs_hamk)
 if (usefock_loc) then
   fockcommon%use_ACE=use_ACE_old
 end if
 call timab(925,2,tsec)
 call timab(920,2,tsec)

end subroutine forstrnps
!!***
