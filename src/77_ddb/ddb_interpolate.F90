!{\src2tex{textfont=tt}}
!!****f* ABINIT/ddb_interpolate
!!
!! NAME
!! ddb_interpolate
!!
!! FUNCTION
!! Interpolate the ddb onto a fine set of q-points using
!! the interatomic force constants and write the result in a DDB file.
!!
!! COPYRIGHT
!! Copyright (C) 1999-2018 ABINIT group (GA)
!! This file is distributed under the terms of the
!! GNU General Public Licence, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!!
!! OUTPUT
!!
!! NOTES
!!
!! PARENTS
!!      anaddb
!!
!! CHILDREN
!!      d2cart_to_red,ddb_free,ddb_hdr_open_write,ddb_malloc,ddb_write_blok
!!      gtblk9,gtdyn9,outddbnc,wrtout
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"


subroutine ddb_interpolate(ifc, crystal, inp, ddb, ddb_hdr, &
!asrq0, &
&                          prefix, comm)


 use defs_basis
 use m_errors
 use m_xmpi
 use m_profiling_abi
 use m_ddb
 use m_ddb_hdr
 use m_ifc
 use m_nctk
#ifdef HAVE_NETCDF
 use netcdf
#endif

 use m_anaddb_dataset, only : anaddb_dataset_type
 use m_crystal,        only : crystal_t
 use m_io_tools,       only : get_unit   
 use m_fstrings,       only : strcat
 use m_dynmat,         only : gtdyn9, d2cart_to_red

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'ddb_interpolate'
 use interfaces_14_hidewrite
 use interfaces_72_response
!End of the abilint section

 implicit none

!Arguments -------------------------------
!scalars
 type(ifc_type),intent(in) :: ifc
 type(anaddb_dataset_type),target,intent(inout) :: inp
 type(crystal_t),intent(in) :: crystal
 type(ddb_type),intent(inout) :: ddb
 type(ddb_hdr_type),intent(inout) :: ddb_hdr
!type(asrq0_t),intent(inout) :: asrq0
 integer,intent(in) :: comm
 character(len=*),intent(in) :: prefix
!arrays

!Local variables -------------------------
!scalars
 integer,parameter :: master=0
 integer :: unddb
 integer :: nsym,natom,ntypat,mband,nqpt_fine
 integer :: msize,nsize,mpert,nblok,mtyp
 integer :: rftyp,choice
 integer :: ii,iblok,jblok,iqpt,ipert1,ipert2,idir1,idir2
 integer :: nprocs,my_rank
 character(len=500) :: msg
 character(len=fnlen) :: ddb_out_filename, ddb_out_nc_filename
 type(ddb_type) :: ddb_new
!arrays
 integer :: rfphon(4),rfelfd(4),rfstrs(4)
 integer,allocatable :: blkflg(:,:,:,:)
 real(dp) :: qpt(3), qptnrm(3), qpt_padded(3,3), qred(3)
 real(dp),allocatable :: d2cart(:,:,:,:,:),d2red(:,:,:,:,:)
 real(dp),pointer :: qpt_fine(:,:)

! *********************************************************************


 ! Only master works for the time being
 nprocs = xmpi_comm_size(comm); my_rank = xmpi_comm_rank(comm)
 if (my_rank /= master) return

 ! ===================================
 ! Copy dimensions and allocate arrays
 ! ===================================

 write(msg, '(a,(80a),a,a,a,a)' ) ch10,('=',ii=1,80),ch10,ch10,' Treat the first list of vectors ',ch10
 call wrtout(std_out,msg,'COLL')
 call wrtout(ab_out,msg,'COLL')

 nullify(qpt_fine)
 nqpt_fine = inp%nph1l
 qpt_fine => inp%qph1l

 rftyp=inp%rfmeth

 nsym = Crystal%nsym
 natom = Crystal%natom
 ntypat = Crystal%ntypat

 mband = ddb_hdr%mband

 mtyp = max(ddb_hdr%mblktyp, 2)  ! Limited to 2nd derivatives of total energy
 ddb_hdr%mblktyp = mtyp

 mpert = natom + 6
 msize = 3 * mpert * 3 * mpert  !; if (mtyp==3) msize=msize*3*mpert
 nsize = 3 * mpert * 3 * mpert
 nblok = nqpt_fine

 ddb_new%nblok = nblok
 call ddb_malloc(ddb_new,msize,nblok,natom,ntypat) 
 ddb_new%flg = zero
 ddb_new%amu = ddb%amu
 ddb_new%typ = one
 ddb_new%qpt = zero
 ddb_new%nrm = one

 ABI_MALLOC(d2cart,(2,3,mpert,3,mpert))
 ABI_MALLOC(d2red,(2,3,mpert,3,mpert))
 ABI_MALLOC(blkflg,(3,mpert,3,mpert))

 blkflg = one

 rfphon(1:2)=1; rfelfd(1:2)=0; rfstrs(1:2)=0
 qpt_padded = zero

 ddb_out_filename = strcat(prefix, "_DDB")

 ddb_hdr%dscrpt = 'Interpolated DDB using interatomic force constants'
 ddb_hdr%nblok = nblok

 ! ================================================
 ! Interpolate the dynamical matrix at each q-point
 ! ================================================

 qptnrm = one

 do iqpt=1,nqpt_fine

   ! Initialisation of the phonon wavevector
   qpt(:)=qpt_fine(:,iqpt)

   if (inp%nph1l /= 0) qptnrm(1) = inp%qnrml1(iqpt)

   ! Look for the information in the DDB
   qpt_padded(:,1) = qpt
   call gtblk9(ddb,iblok,qpt_padded,qptnrm,rfphon,rfelfd,rfstrs,rftyp)

   if (iblok /= 0) then

     ! q-point is present in the ddb. No interpolation needed.

     !d2cart(:,1:msize) = ddb%val(:,:,iblok)
     d2cart(1,:,:,:,:) = reshape(ddb%val(1,:,iblok), &
&     shape = (/3,mpert,3,mpert/))                                                                          
     d2cart(2,:,:,:,:) = reshape(ddb%val(2,:,iblok), &
&     shape = (/3,mpert,3,mpert/))                                                                          
   else

     ! Get d2cart using the interatomic forces and the
     ! long-range coulomb interaction through Ewald summation
     call gtdyn9(ddb%acell,Ifc%atmfrc,Ifc%dielt,Ifc%dipdip,Ifc%dyewq0,d2cart, &
&     crystal%gmet,ddb%gprim,ddb%mpert,natom,Ifc%nrpt,qptnrm(1), &
&     qpt, crystal%rmet,ddb%rprim,Ifc%rpt,Ifc%trans,crystal%ucvol, &
&     Ifc%wghatm,crystal%xred,ifc%zeff)

   end if

   ! Eventually impose the acoustic sum rule based on previously calculated d2asr
   ! TODO: I think d2cart is of the wrong shape here
   !call asrq0_apply(asrq0, natom, ddb%mpert, ddb%msize, crystal%xcart, d2cart)

   ! Transform d2cart into reduced coordinates.
   call d2cart_to_red(d2cart,d2red,crystal%gprimd,crystal%rprimd,mpert, &
&   natom,ntypat,crystal%typat,crystal%ucvol,crystal%zion)


   ! Store the dynamical matrix into a block of the new ddb
   jblok = iqpt
   ddb_new%val(1,1:nsize,jblok) = reshape(d2red(1,:,:,:,:), &
&   shape = (/3*mpert*3*mpert/))                                                                          
   ddb_new%val(2,1:nsize,jblok) = reshape(d2red(2,:,:,:,:), &
&   shape = (/3*mpert*3*mpert/)) 

   ! Store the q-point
   ddb_new%qpt(1:3,jblok) = qpt
   ddb_new%nrm(1,jblok) = qptnrm(1)

   ! Set the flags
   ii=0
   do ipert2=1,mpert
     do idir2=1,3
       do ipert1=1,mpert
         do idir1=1,3
           ii=ii+1
           if (ipert1<=natom.and.ipert2<=natom) then
             ddb_new%flg(ii,jblok) = one
           end if
         end do
       end do
     end do
   end do

 end do ! iqpt

 ! Copy the flags for Gamma
 qpt_padded(:,1) = zero
 qptnrm = one
 call gtblk9(ddb,iblok,qpt_padded,qptnrm,rfphon,rfelfd,rfstrs,rftyp)
 call gtblk9(ddb_new,jblok,qpt_padded,qptnrm,rfphon,rfelfd,rfstrs,rftyp)

 if (iblok /= 0 .and. jblok /= 0) then

   ii=0
   do ipert2=1,mpert
     do idir2=1,3
       do ipert1=1,mpert
         do idir1=1,3
           ii=ii+1
           ddb_new%flg(ii,jblok) = ddb%flg(ii,iblok)
         end do
       end do
     end do
   end do

 end if


 ! =======================
 ! Write the new DDB files                           
 ! =======================

 if (my_rank == master) then

   unddb = get_unit()

   ! Write the DDB header
   call ddb_hdr_open_write(ddb_hdr, ddb_out_filename, unddb)

   ! Write the whole database
   call wrtout(std_out,' write the DDB ','COLL')
   choice=2
   do iblok=1,nblok
     call ddb_write_blok(ddb_new,iblok,choice,ddb_hdr%mband,mpert,msize,&
&     ddb_hdr%nkpt,unddb)
   end do

   ! Also write summary of bloks at the end
   write(unddb, '(/,a)' )' List of bloks and their characteristics '
   choice=3
   do iblok=1,nblok
     call ddb_write_blok(ddb_new,iblok,choice,ddb_hdr%mband,mpert,msize,&
&     ddb_hdr%nkpt,unddb)
   end do

   close (unddb)

#ifdef HAVE_NETCDF
   ! Write the DDB.nc files (one for each q-point)
   do jblok=1,nblok

     write(ddb_out_nc_filename,'(2a,i5.5,a)') trim(prefix),'_qpt_',jblok,'_DDB.nc'

     d2red(1,:,:,:,:) = reshape(ddb_new%val(1,1:nsize,jblok), &
&     shape = (/3,mpert,3,mpert/))                                                                          
     d2red(2,:,:,:,:) = reshape(ddb_new%val(2,1:nsize,jblok), &
&     shape = (/3,mpert,3,mpert/))                                                                          
     blkflg(:,:,:,:)  = reshape(ddb_new%flg(1:nsize,jblok), &
&     shape = (/3,mpert,3,mpert/))                                                                          

     do ii=1,3
       qred(ii) = ddb_new%qpt(ii,jblok) / ddb_new%nrm(1,jblok)
     end do

     call outddbnc(ddb_out_nc_filename,mpert,d2red,blkflg,qred,crystal)

   end do
#endif

 end if


 ! ===========
 ! Free memory
 ! ===========

 call ddb_free(ddb_new)
 ABI_FREE(d2cart)
 ABI_FREE(d2red)
 ABI_FREE(blkflg)

end subroutine ddb_interpolate
!!***
