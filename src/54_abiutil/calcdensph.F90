!{\src2tex{textfont=tt}}
!!****f* ABINIT/calcdensph
!! NAME
!! calcdensph
!!
!! FUNCTION
!! Compute and print integral of total density inside spheres around atoms.
!!
!! COPYRIGHT
!! Copyright (C) 1998-2018 ABINIT group (MT,ILuk,MVer,EB,SPr)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt.
!!
!! INPUTS
!!  gmet(3,3)=reciprocal space metric tensor in bohr**-2
!!  mpi_enreg=information about MPI parallelization
!!  natom=number of atoms in cell.
!!  nfft=(effective) number of FFT grid points (for this processor)
!!  ngfft(18)=contain all needed information about 3D FFT, see ~abinit/doc/variables/vargs.htm#ngfft
!!  nspden=number of spin-density components
!!  ntypat=number of atom types
!!  nunit=number of the unit for writing
!!  ratsph(ntypat)=radius of spheres around atoms
!!  rhor(nfft,nspden)=array for electron density in electrons/bohr**3.
!!   (total in first half and spin-up in second half if nspden=2)
!!   (total in first comp. and magnetization in comp. 2 to 4 if nspden=4)
!!  rprimd(3,3)=dimensional primitive translations in real space (bohr)
!!  typat(natom)=type of each atom
!!  ucvol=unit cell volume in bohr**3
!!  xred(3,natom)=reduced dimensionless atomic coordinates
!!  prtopt = if 1, the default printing is on, otherwise special printing options  
!!
!! OUTPUT
!!  intgden(nspden, natom)=intgrated density (magnetization...) for each atom in a sphere of radius ratsph. Optional arg
!!  dentot(nspden)=integrated density (magnetization...) over full u.c. vol, optional argument
!!  Rest is printing
!!
!! PARENTS
!!      dfpt_scfcv,mag_constr,mag_constr_e,outscfcv
!!
!! CHILDREN
!!      timab,wrtout,xmpi_sum
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine calcdensph(gmet,mpi_enreg,natom,nfft,ngfft,nspden,ntypat,nunit,ratsph,rhor,rprimd,typat,ucvol,xred,&
&    prtopt,cplex,intgden,dentot)

 use defs_basis
 use defs_abitypes
 use m_profiling_abi
 use m_errors

 use m_xmpi, only : xmpi_sum

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'calcdensph'
 use interfaces_14_hidewrite
 use interfaces_18_timing
 use interfaces_32_util
!End of the abilint section

 implicit none

!Arguments ---------------------------------------------
!scalars
 integer,intent(in)        :: natom,nfft,nspden,ntypat,nunit
 real(dp),intent(in)       :: ucvol
 type(MPI_type),intent(in) :: mpi_enreg
 integer ,intent(in)       :: prtopt
 integer, intent(in)       :: cplex
!arrays
 integer,intent(in)  :: ngfft(18),typat(natom)
 real(dp),intent(in) :: gmet(3,3),ratsph(ntypat),rhor(cplex*nfft,nspden),rprimd(3,3)
 real(dp),intent(in) :: xred(3,natom)
!integer,intent(out),optional   :: atgridpts(nfft)
 real(dp),intent(out),optional  :: intgden(nspden,natom)
 real(dp),intent(out),optional  :: dentot(nspden)
!Local variables ------------------------------
!scalars
 integer,parameter :: ishift=5
 integer :: i1,i2,i3,iatom,ierr,ifft_local,ix,iy,iz,izloc,n1,n1a,n1b,n2,ifft
 integer :: n2a,n2b,n3,n3a,n3b,nd3,nfftot
 integer :: ii
!integer :: is,npts(natom) 
 integer :: cmplex_den,jfft
 real(dp),parameter :: delta=0.99_dp
 real(dp) :: difx,dify,difz,r2,r2atsph,rr1,rr2,rr3,rx,ry,rz
 real(dp) :: fsm, ratsm, ratsm2 
 real(dp) :: mag_coll   , mag_x, mag_y, mag_z ! EB
 real(dp) :: mag_coll_im, mag_x_im, mag_y_im, mag_z_im ! SPr
 real(dp) :: sum_mag, sum_mag_x,sum_mag_y,sum_mag_z,sum_rho_up,sum_rho_dn,sum_rho_tot ! EB
 real(dp) :: rho_tot, rho_tot_im
! real(dp) :: rho_up,rho_dn,rho_tot !EB 
 logical   :: grid_found
 character(len=500) :: message
!arrays
 integer, ABI_CONTIGUOUS pointer :: fftn3_distrib(:),ffti3_local(:)
 real(dp) :: intgden_(nspden,natom),tsec(2)

! *************************************************************************

 n1=ngfft(1);n2=ngfft(2);n3=ngfft(3);nd3=n3/mpi_enreg%nproc_fft
 nfftot=n1*n2*n3
 intgden_=zero

 ratsm = zero
 if(present(intgden)) then

   ratsm = 0.05_dp ! default value for the smearing region radius - may become input variable later

 end if

!Get the distrib associated with this fft_grid
 grid_found=.false.

 if(n2 == mpi_enreg%distribfft%n2_coarse ) then

   if(n3== size(mpi_enreg%distribfft%tab_fftdp3_distrib)) then

     fftn3_distrib => mpi_enreg%distribfft%tab_fftdp3_distrib
     ffti3_local => mpi_enreg%distribfft%tab_fftdp3_local
     grid_found=.true.

   end if

 end if

 if(n2 == mpi_enreg%distribfft%n2_fine ) then

   if(n3 == size(mpi_enreg%distribfft%tab_fftdp3dg_distrib)) then

     fftn3_distrib => mpi_enreg%distribfft%tab_fftdp3dg_distrib
     ffti3_local => mpi_enreg%distribfft%tab_fftdp3dg_local
     grid_found = .true.

   end if

 end if
 if(.not.(grid_found)) then

   MSG_BUG("Unable to find an allocated distrib for this fft grid")

 end if

!Loop over atoms
!-------------------------------------------
 ii=0

 do iatom=1,natom

   !if (present(atgridpts)) then
   !  npts(iatom)=0           !SPr: initialize the number of grid points within atomic sphere around atom i
   !  ii=ii+1                 !SPr: initialize running index for constructing an array of grid point indexes
   !end if                    !     within atomic spheres

!  Define a "box" around the atom
   r2atsph=1.0000001_dp*ratsph(typat(iatom))**2
   rr1=sqrt(r2atsph*gmet(1,1))
   rr2=sqrt(r2atsph*gmet(2,2))
   rr3=sqrt(r2atsph*gmet(3,3))

   n1a=int((xred(1,iatom)-rr1+ishift)*n1+delta)-ishift*n1
   n1b=int((xred(1,iatom)+rr1+ishift)*n1      )-ishift*n1
   n2a=int((xred(2,iatom)-rr2+ishift)*n2+delta)-ishift*n2
   n2b=int((xred(2,iatom)+rr2+ishift)*n2      )-ishift*n2
   n3a=int((xred(3,iatom)-rr3+ishift)*n3+delta)-ishift*n3
   n3b=int((xred(3,iatom)+rr3+ishift)*n3      )-ishift*n3

   ratsm2 = (2*ratsph(typat(iatom))-ratsm)*ratsm 

   do i3=n3a,n3b
     iz=mod(i3+ishift*n3,n3)

     if(fftn3_distrib(iz+1)==mpi_enreg%me_fft) then

       izloc = ffti3_local(iz+1) - 1
       difz=dble(i3)/dble(n3)-xred(3,iatom)
       do i2=n2a,n2b
         iy=mod(i2+ishift*n2,n2)
         dify=dble(i2)/dble(n2)-xred(2,iatom)
         do i1=n1a,n1b
           ix=mod(i1+ishift*n1,n1)

           difx=dble(i1)/dble(n1)-xred(1,iatom)
           rx=difx*rprimd(1,1)+dify*rprimd(1,2)+difz*rprimd(1,3)
           ry=difx*rprimd(2,1)+dify*rprimd(2,2)+difz*rprimd(2,3)
           rz=difx*rprimd(3,1)+dify*rprimd(3,2)+difz*rprimd(3,3)
           r2=rx**2+ry**2+rz**2


!          Identify the fft indexes of the rectangular grid around the atom
           if(r2 > r2atsph) then
             cycle
           end if

           fsm = radsmear(r2, r2atsph, ratsm2)

           ifft_local=1+ix+n1*(iy+n2*izloc)

           !if(present(atgridpts)) then
           !  ii=ii+1                     
           !  atgridpts(ii)=ifft_local    !SPr: save grid point index (dbg: to check whether ifft_local is a valid "global" index )
           !end if

           if(nspden==1) then
!            intgden_(1,iatom)= integral of total density
             intgden_(1,iatom)=intgden_(1,iatom)+fsm*rhor(ifft_local,1)
           elseif(nspden==2) then
!            intgden_(1,iatom)= integral of up density
!            intgden_(2,iatom)= integral of dn density
             intgden_(1,iatom)=intgden_(1,iatom)+fsm*rhor(ifft_local,2)
             intgden_(2,iatom)=intgden_(2,iatom)+fsm*rhor(ifft_local,1)-rhor(ifft_local,2)
           else
!            intgden_(1,iatom)= integral of total density
!            intgden_(2,iatom)= integral of magnetization, x-component
!            intgden_(3,iatom)= integral of magnetization, y-component
!            intgden_(4,iatom)= integral of magnetization, z-component
             intgden_(1,iatom)=intgden_(1,iatom)+fsm*rhor(ifft_local,1)
             intgden_(2,iatom)=intgden_(2,iatom)+fsm*rhor(ifft_local,2)
             intgden_(3,iatom)=intgden_(3,iatom)+fsm*rhor(ifft_local,3)
             intgden_(4,iatom)=intgden_(4,iatom)+fsm*rhor(ifft_local,4)
           end if

         end do
       end do
     end if
   end do

   intgden_(:,iatom)=intgden_(:,iatom)*ucvol/dble(nfftot)

   !if (present(atgridpts)) then
   !  npts(iatom)=ii-1
   !  do is=1,iatom-1,1
   !    npts(iatom)=npts(iatom)-npts(is)-1
   !  end do
   !  atgridpts(ii-npts(iatom))=npts(iatom)    !SPr: save number of grid points around atom i
   !end if
   

!  End loop over atoms
!  -------------------------------------------
   
 end do

! EB  - Compute magnetization of the whole cell
! SPr - in case of complex density array set cmplex_den to one
 cmplex_den=0

 if(cplex==2) then

   cmplex_den=1

 end if

 if(nspden==2) then
   mag_coll=zero
   mag_coll_im=zero
   rho_tot=zero
   rho_tot_im=zero
   do ifft=1,nfft
     jfft=(cmplex_den+1)*ifft
!    rho_up=rho_up+rhor(ifft,2)
!    rho_dn=rho_dn+(rhor(ifft,2)-rhor(ifft,1))
     rho_tot=rho_tot+rhor(jfft-cmplex_den,1)             ! real parts of density and magnetization
     mag_coll=mag_coll+2*rhor(jfft-cmplex_den,2)-rhor(jfft-cmplex_den,1)

     rho_tot_im=rho_tot_im+rhor(jfft,1)                  ! imaginary parts of density and magnetization
     mag_coll_im=mag_coll_im+2*rhor(jfft,2)-rhor(jfft,1) ! in case of real array both are equal to corresponding real parts
   end do
   mag_coll=mag_coll*ucvol/dble(nfftot)
   rho_tot =rho_tot *ucvol/dble(nfftot)

   mag_coll_im=mag_coll_im*ucvol/dble(nfftot)
   rho_tot_im =rho_tot_im *ucvol/dble(nfftot)
!  rho_up=rho_up*ucvol/dble(nfftot)
!  rho_dn=rho_dn*ucvol/dble(nfftot)
!  rho_tot=rho_tot*ucvol/dble(nfftot) 
 else if(nspden==4) then
   rho_tot=0
   rho_tot_im=0
   mag_x=0
   mag_y=0
   mag_z=0
   mag_x_im=0
   mag_y_im=0
   mag_z_im=0
   do ifft=1,nfft
     jfft=(cmplex_den+1)*ifft
     rho_tot=rho_tot+rhor(jfft-cmplex_den,1)
     mag_x=mag_x+rhor(jfft-cmplex_den,2)
     mag_y=mag_y+rhor(jfft-cmplex_den,3)
     mag_z=mag_z+rhor(jfft-cmplex_den,4)
     rho_tot_im=rho_tot_im+rhor(jfft,1)
     mag_x_im=mag_x_im+rhor(jfft,2)
     mag_y_im=mag_y_im+rhor(jfft,3)
     mag_z_im=mag_z_im+rhor(jfft,4)
   end do
   rho_tot=rho_tot*ucvol/dble(nfftot)
   mag_x=mag_x*ucvol/dble(nfftot)
   mag_y=mag_y*ucvol/dble(nfftot)
   mag_z=mag_z*ucvol/dble(nfftot)
   rho_tot_im=rho_tot_im*ucvol/dble(nfftot)
   mag_x_im=mag_x_im*ucvol/dble(nfftot)
   mag_y_im=mag_y_im*ucvol/dble(nfftot)
   mag_z_im=mag_z_im*ucvol/dble(nfftot)
 end if

!MPI parallelization
 if(mpi_enreg%nproc_fft>1)then
   call timab(48,1,tsec)
   call xmpi_sum(intgden_,mpi_enreg%comm_fft,ierr)
   call xmpi_sum(rho_tot,mpi_enreg%comm_fft,ierr)  ! EB
   call xmpi_sum(mag_coll,mpi_enreg%comm_fft,ierr) ! EB

   call xmpi_sum(rho_tot_im,mpi_enreg%comm_fft,ierr)  
   call xmpi_sum(mag_coll_im,mpi_enreg%comm_fft,ierr) 
!  call xmpi_sum(rho_up,mpi_enreg%comm_fft,ierr)  ! EB
!  call xmpi_sum(rho_dn,mpi_enreg%comm_fft,ierr)  ! EB
   call xmpi_sum(mag_x,mpi_enreg%comm_fft,ierr)    ! EB
   call xmpi_sum(mag_y,mpi_enreg%comm_fft,ierr)    ! EB
   call xmpi_sum(mag_z,mpi_enreg%comm_fft,ierr)    ! EB
   call xmpi_sum(mag_x_im,mpi_enreg%comm_fft,ierr)    ! EB
   call xmpi_sum(mag_y_im,mpi_enreg%comm_fft,ierr)    ! EB
   call xmpi_sum(mag_z_im,mpi_enreg%comm_fft,ierr)    ! EB
   call timab(48,2,tsec)
 end if

!Printing 
 sum_mag=zero
 sum_mag_x=zero
 sum_mag_y=zero
 sum_mag_z=zero
 sum_rho_up=zero
 sum_rho_dn=zero
 sum_rho_tot=zero

 if(prtopt==1) then

   if(nspden==1) then
     write(message, '(4a)' ) &
&     ' Integrated electronic density in atomic spheres:',ch10,&
&     ' ------------------------------------------------'
     call wrtout(nunit,message,'COLL')
     write(message, '(a)' ) ' Atom  Sphere_radius  Integrated_density'
     call wrtout(nunit,message,'COLL')
     do iatom=1,natom
       write(message, '(i5,f15.5,f20.8)' ) iatom,ratsph(typat(iatom)),intgden_(1,iatom)
       call wrtout(nunit,message,'COLL')
     end do
   elseif(nspden==2) then
     write(message, '(4a)' ) &
&     ' Integrated electronic and magnetization densities in atomic spheres:',ch10,&
&     ' ---------------------------------------------------------------------'
     call wrtout(nunit,message,'COLL')
     write(message, '(3a)' ) ' Note: Diff(up-dn) is a rough ',&
&     'approximation of local magnetic moment'
     call wrtout(nunit,message,'COLL')
     write(message, '(a)' ) ' Atom    Radius    up_density   dn_density  Total(up+dn)  Diff(up-dn)'
     call wrtout(nunit,message,'COLL')
     do iatom=1,natom
       write(message, '(i5,f10.5,2f13.6,a,f12.6,a,f12.6)' ) iatom,ratsph(typat(iatom)),intgden_(1,iatom),intgden_(2,iatom),&
&       '  ',(intgden_(1,iatom)+intgden_(2,iatom)),' ',(intgden_(1,iatom)-intgden_(2,iatom))
       call wrtout(nunit,message,'COLL')
       ! Compute the sum of the magnetization 
       sum_mag=sum_mag+intgden_(1,iatom)-intgden_(2,iatom)
       sum_rho_up=sum_rho_up+intgden_(1,iatom)
       sum_rho_dn=sum_rho_dn+intgden_(2,iatom)
       sum_rho_tot=sum_rho_tot+intgden_(1,iatom)+intgden_(2,iatom)
     end do
     write(message, '(a)') ' ---------------------------------------------------------------------'
     call wrtout(nunit,message,'COLL')
     write(message, '(a,2f13.6,a,f12.6,a,f12.6)') '  Sum:         ', sum_rho_up,sum_rho_dn,'  ',sum_rho_tot,' ',sum_mag
     call wrtout(nunit,message,'COLL')
     write(message, '(a,f14.6)') ' Total magnetization (from the atomic spheres):       ', sum_mag
     call wrtout(nunit,message,'COLL')
     write(message, '(a,f14.6)') ' Total magnetization (exact up - dn):                 ', mag_coll
     call wrtout(nunit,message,'COLL')
   ! EB for testing purpose print rho_up, rho_dn and rho_tot
!    write(message, '(a,3f14.4,2i8)') ' rho_up, rho_dn, rho_tot, nfftot, nfft: ', rho_up,rho_dn,rho_tot,nfft,nfft
!   call wrtout(nunit,message,'COLL')   

   elseif(nspden==4) then

     write(message, '(4a)' ) &
&     ' Integrated electronic and magnetization densities in atomic spheres:',ch10,&
&     ' ---------------------------------------------------------------------'
     call wrtout(nunit,message,'COLL')
     write(message, '(3a)' ) ' Note:      this is a rough approximation of local magnetic moments'
     call wrtout(nunit,message,'COLL')
     write(message, '(a)' ) ' Atom   Radius      Total density     mag(x)      mag(y)      mag(z)  '
     call wrtout(nunit,message,'COLL')
     do iatom=1,natom
       write(message, '(i5,f10.5,f16.6,a,3f12.6)' ) iatom,ratsph(typat(iatom)),intgden_(1,iatom),'  ',(intgden_(ix,iatom),ix=2,4)
       call wrtout(nunit,message,'COLL')
       ! Compute the sum of the magnetization in x, y and z directions
       sum_mag_x=sum_mag_x+intgden_(2,iatom)
       sum_mag_y=sum_mag_y+intgden_(3,iatom)
       sum_mag_z=sum_mag_z+intgden_(4,iatom)
     end do
     write(message, '(a)') ' ---------------------------------------------------------------------'
     call wrtout(nunit,message,'COLL')
!    write(message, '(a,f12.6,f12.6,f12.6)') ' Total magnetization :           ', sum_mag_x,sum_mag_y,sum_mag_z
     write(message, '(a,f12.6,f12.6,f12.6)') ' Total magnetization (spheres)   ', sum_mag_x,sum_mag_y,sum_mag_z
     call wrtout(nunit,message,'COLL')
     write(message, '(a,f12.6,f12.6,f12.6)') ' Total magnetization (exact)     ', mag_x,mag_y,mag_z
     call wrtout(nunit,message,'COLL')
!    SPr for dfpt debug
!    write(message, '(a,f12.6)') ' Total density (exact)           ', rho_tot
!   call wrtout(nunit,message,'COLL')
   end if

 elseif(prtopt==-1) then

   write(message, '(2a)') ch10,' ------------------------------------------------------------------------'
   call wrtout(nunit,message,'COLL')

   if(nspden==1) then
     write(message, '(4a)' ) &
&     ' Fermi level charge density n_f:',ch10,&
&     ' ------------------------------------------------------------------------',ch10
   else
     write(message, '(4a)' ) &
&     ' Fermi level charge density n_f and magnetization m_f:',ch10,&
&     ' ------------------------------------------------------------------------',ch10
   end if
   call wrtout(nunit,message,'COLL')

   if(cmplex_den==0) then
     write(message, '(a,f13.8)') '     n_f   = ',rho_tot
   else
     write(message, '(a,f13.8,a,f13.8)') '  Re[n_f]= ', rho_tot,"   Im[n_f]= ",rho_tot_im
   end if
   call wrtout(nunit,message,'COLL')
   if(nspden==2) then
     if(cmplex_den==0) then
       write(message, '(a,f13.8)') '     m_f    = ', mag_coll
     else
       write(message, '(a,f13.8,a,f13.8)') '  Re[m_f]= ', mag_coll,"   Im[m_f]= ",mag_coll_im
     end if
     call wrtout(nunit,message,'COLL')
   elseif (nspden==4) then
     write(message, '(a,f13.8)') '     mx_f  = ',mag_x
     call wrtout(nunit,message,'COLL')
     write(message, '(a,f13.8)') '     my_f  = ',mag_y
     call wrtout(nunit,message,'COLL')
     write(message, '(a,f13.8)') '     mz_f  = ',mag_z
     call wrtout(nunit,message,'COLL')
   end if

   write(message, '(3a)') ch10,' ------------------------------------------------------------------------',ch10
   call wrtout(nunit,message,'COLL')


 else   
 ! prtopt different from 1 and -1 (either 2,3 or 4)

   if(abs(rho_tot)<1.0d-10) then
     rho_tot=0
   end if

   write(message, '(2a)') ch10,' ------------------------------------------------------------------------'
   call wrtout(nunit,message,'COLL')

   if(nspden==1) then
     write(message, '(4a)' ) &
&     ' Integral of the first order density n^(1):',ch10,&
&     ' ------------------------------------------------------------------------',ch10
   else
     write(message, '(4a)' ) &
&     ' Integrals of the first order density n^(1) and magnetization m^(1):',ch10,&
&     ' ------------------------------------------------------------------------',ch10
   end if
   call wrtout(nunit,message,'COLL')

   if(cmplex_den==0) then
     write(message, '(a,e16.8)') '     n^(1)    = ', rho_tot
   else
     write(message, '(a,e16.8,a,e16.8)') '  Re[n^(1)] = ', rho_tot,"   Im[n^(1)] = ",rho_tot_im
   end if
   call wrtout(nunit,message,'COLL')

   if(nspden==2) then

     if(cmplex_den==0) then
       write(message, '(a,e16.8)') '     m^(1)    = ', mag_coll
     else
       write(message, '(a,e16.8,a,e16.8)') '  Re[m^(1)] = ', mag_coll,"   Im[m^(1)] = ",mag_coll_im
     end if
     call wrtout(nunit,message,'COLL')

   elseif (nspden==4) then
     if(cmplex_den==0) then
       write(message, '(a,e16.8)') '     mx^(1)   = ', mag_x
       call wrtout(nunit,message,'COLL')
       write(message, '(a,e16.8)') '     my^(1)   = ', mag_y
       call wrtout(nunit,message,'COLL')
       write(message, '(a,e16.8)') '     mz^(1)   = ', mag_z
       call wrtout(nunit,message,'COLL')
     else
       write(message, '(a,e16.8,a,e16.8)') '  Re[mx^(1)]= ',  mag_x, "   Im[mx^(1)]= ", mag_x_im
       call wrtout(nunit,message,'COLL')
       write(message, '(a,e16.8,a,e16.8)') '  Re[my^(1)]= ',  mag_y, "   Im[my^(1)]= ", mag_y_im
       call wrtout(nunit,message,'COLL')
       write(message, '(a,e16.8,a,e16.8)') '  Re[mz^(1)]= ',  mag_z, "   Im[mz^(1)]= ", mag_z_im
       call wrtout(nunit,message,'COLL')
     end if
   end if

   write(message, '(3a)') ch10,' ------------------------------------------------------------------------',ch10
   call wrtout(nunit,message,'COLL')

 end if 

 if(present(intgden)) then
   intgden = intgden_
 end if

 if(present(dentot)) then
   if(nspden==2) then
     dentot(1)=rho_tot
     dentot(2)=mag_coll
   elseif(nspden==4) then
     dentot(1)=rho_tot
     dentot(2)=mag_x
     dentot(3)=mag_y
     dentot(4)=mag_z
   end if
 end if 

end subroutine calcdensph
!!***
