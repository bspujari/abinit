!{\src2tex{textfont=tt}}
!!****m* ABINIT/m_xgScalapack
!! NAME
!!  m_xgScalapack
!! 
!! FUNCTION 
!! 
!! COPYRIGHT
!!  Copyright (C) 2017 ABINIT group (J. Bieder)
!!  This file is distributed under the terms of the
!!  GNU General Public License, see ~abinit/COPYING
!!  or http://www.gnu.org/copyleft/gpl.txt .
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

module m_xgScalapack
  use defs_basis, only : std_err, std_out, dp
  use m_profiling_abi
  use m_xmpi 
  use m_errors
  use m_slk
  use m_xg

#ifdef HAVE_MPI2
 use mpi
#endif

  implicit none

#ifdef HAVE_MPI1
 include 'mpif.h'
#endif


  private

  integer, parameter :: M__SLK = 1
  integer, parameter :: M__ROW = 1
  integer, parameter :: M__COL = 2
  integer, parameter :: M__UNUSED = 4
  integer, parameter :: M__WORLD = 5
  integer, parameter :: M__NDATA = 5
  integer, parameter :: M__tim_init    = 1690
  integer, parameter :: M__tim_free    = 1691
  integer, parameter :: M__tim_heev    = 1692
  integer, parameter :: M__tim_hegv    = 1693
  integer, parameter :: M__tim_scatter = 1694

  integer, parameter, public :: SLK_AUTO = -1
  integer, parameter, public :: SLK_FORCED = 1
  integer, parameter, public :: SLK_DISABLED = 0
  integer, save :: M__CONFIG = SLK_AUTO

  type, public :: xgScalapack_t
    integer :: comms(M__NDATA)
    integer :: rank(M__NDATA)
    integer :: size(M__NDATA)
    integer :: coords(2)
    integer :: verbosity
    type(grid_scalapack) :: grid
  end type xgScalapack_t

  public :: xgScalapack_init
  public :: xgScalapack_free
  public :: xgScalapack_heev
  public :: xgScalapack_hegv
  public :: xgScalapack_config
  contains 
!!***

!!****f* m_xgScalapack/xgScalapack_init
!! NAME
!!  xgScalapack_init
!!
!! FUNCTION
!!  Init the scalapack communicator for next operations.
!!  If the comm has to many cpus, then take only a subgroup of this comm
!!
!! INPUTS
!!
!! OUTPUT
!!
!! PARENTS
!!      m_lobpcg2
!!
!! CHILDREN
!!      blacs_gridexit,mpi_comm_free,timab
!!
!! SOURCE
  subroutine  xgScalapack_init(xgScalapack,comm,maxDim,verbosity,usable)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_init'
 use interfaces_18_timing
!End of the abilint section

    type(xgScalapack_t), intent(inout) :: xgScalapack
    integer            , intent(in   ) :: comm
    integer            , intent(in   ) :: maxDim
    integer            , intent(in   ) :: verbosity
    logical            , intent(  out) :: usable
    double precision :: tsec(2)
#ifdef HAVE_LINALG_SCALAPACK
    integer :: maxProc
    integer :: nproc
    integer :: subgroup
    integer :: mycomm(2)
    integer :: ierr
    integer :: test_row
    integer :: test_col
#else
    ABI_UNUSED(comm)
    ABI_UNUSED(maxDim)
#endif

    call timab(M__tim_init,1,tsec)

    xgScalapack%comms = xmpi_comm_null
    xgScalapack%rank = xmpi_undefined_rank
    xgScalapack%verbosity = verbosity

#ifdef HAVE_LINALG_SCALAPACK

    nproc = xmpi_comm_size(comm)
    xgScalapack%comms(M__WORLD) = comm
    xgScalapack%rank(M__WORLD) = xmpi_comm_rank(comm)
    xgScalapack%size(M__WORLD) = nproc

    maxProc = (maxDim / 1000)+1 ! ( 1000 x 1000 matrice per MPI )
    if ( M__CONFIG > 0 .and. M__CONFIG <= nproc ) then
      maxProc = M__CONFIG
    end if

    if ( maxProc == 1 .or. M__CONFIG == SLK_DISABLED) then
      usable = .false.
      return
    else
      usable = .true.
    end if

    if ( xgScalapack%verbosity > 0 ) then
      write(std_out,*) " xgScalapack will use", maxProc, "/", nproc, "MPIs"
    end if

    if ( maxProc < nproc ) then
      if ( xgScalapack%rank(M__WORLD) < maxProc ) then
        subgroup = 0
        mycomm(1) = M__SLK
        mycomm(2) = M__UNUSED
      else
        subgroup = 1
        mycomm(1) = M__UNUSED
        mycomm(2) = M__SLK
      end if
       call MPI_Comm_split(comm, subgroup, xgScalapack%rank(M__WORLD), xgScalapack%comms(mycomm(1)),ierr)
       if ( ierr /= 0 ) then
         MSG_ERROR("Error splitting communicator")
       end if
       xgScalapack%comms(mycomm(2)) = xmpi_comm_null
       xgScalapack%rank(mycomm(1)) = xmpi_comm_rank(xgScalapack%comms(mycomm(1)))
       xgScalapack%rank(mycomm(2)) = xmpi_undefined_rank
       xgScalapack%size(mycomm(1)) = xmpi_comm_size(xgScalapack%comms(mycomm(1)))
       xgScalapack%size(mycomm(2)) = nproc - xgScalapack%size(mycomm(1))
    else 
       call MPI_Comm_dup(comm,xgScalapack%comms(M__SLK),ierr)
       if ( ierr /= 0 ) then
         MSG_ERROR("Error duplicating communicator")
       end if
       xgScalapack%rank(M__SLK) = xmpi_comm_rank(xgScalapack%comms(M__SLK))
       xgScalapack%size(M__SLK) = nproc
    end if

    if ( xgScalapack%comms(M__SLK) /= xmpi_comm_null ) then
      call build_grid_scalapack(xgScalapack%grid, xgScalapack%size(M__SLK), xgScalapack%comms(M__SLK))
      call BLACS_GridInfo(xgScalapack%grid%ictxt, &
        xgScalapack%grid%dims(M__ROW), xgScalapack%grid%dims(M__COL),&
        xgScalapack%coords(M__ROW), xgScalapack%coords(M__COL))

     !These values are the same as those computed by BLACS_GRIDINFO
     !except in the case where the myproc argument is not the local proc
      test_row = INT((xgScalapack%rank(M__SLK)) / xgScalapack%grid%dims(2))
      test_col = MOD((xgScalapack%rank(M__SLK)), xgScalapack%grid%dims(2))
      if ( test_row /= xgScalapack%coords(M__ROW) ) then
        MSG_WARNING("Row id mismatch")
      end if
      if ( test_col /= xgScalapack%coords(M__COL) ) then
        MSG_WARNING("Col id mismatch")
      end if
    end if

#else
    usable = .false.
#endif

    call timab(M__tim_init,2,tsec)

  end subroutine xgScalapack_init

  subroutine xgScalapack_config(myconfig)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_config'
!End of the abilint section

    integer, intent(in) :: myconfig
    if ( myconfig == SLK_AUTO) then
      M__CONFIG = myconfig
      MSG_COMMENT("xgScalapack in auto mode")
    else if ( myconfig == SLK_DISABLED) then
      M__CONFIG = myconfig
      MSG_COMMENT("xgScalapack disabled")
    else if ( myconfig > 0) then
      M__CONFIG = myconfig
      MSG_COMMENT("xgScalapack enabled")
    else
      MSG_WARNING("Bad value for xgScalapack config -> autodetection")
      M__CONFIG = SLK_AUTO
    end if 

  end subroutine xgScalapack_config

  function toProcessorScalapack(xgScalapack) result(processor)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'toProcessorScalapack'
!End of the abilint section

    type(xgScalapack_t), intent(in) :: xgScalapack
    type(processor_scalapack) :: processor

    processor%myproc = xgScalapack%rank(M__SLK)
    processor%comm = xgScalapack%comms(M__SLK)
    processor%coords = xgScalapack%coords
    processor%grid = xgScalapack%grid
  end function toProcessorScalapack

  !This is for testing purpose.
  !May not be optimal since I do not control old implementation but at least gives a reference.
  subroutine xgScalapack_heev(xgScalapack,matrixA,eigenvalues)
    use iso_c_binding

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_heev'
 use interfaces_18_timing
!End of the abilint section

    type(xgScalapack_t), intent(inout) :: xgScalapack
    type(xgBlock_t)    , intent(inout) :: matrixA
    type(xgBlock_t)    , intent(inout) :: eigenvalues
#ifdef HAVE_LINALG_SCALAPACK
    double precision, pointer :: matrix(:,:) !(cplex*nbli_global,nbco_global)
    double precision, pointer :: eigenvalues_tmp(:,:)
    double precision, pointer :: vector(:)
    double precision :: tsec(2)
    integer :: cplex
    integer :: istwf_k
    integer :: nbli_global, nbco_global
    type(c_ptr) :: cptr
#endif

#ifdef HAVE_LINALG_SCALAPACK
    call timab(M__tim_heev,1,tsec)

    ! Keep only working processors 
    if ( xgScalapack%comms(M__SLK) /= xmpi_comm_null ) then

      call xgBlock_getSize(eigenvalues,nbli_global,nbco_global)
      if ( cols(matrixA) /= nbli_global ) then
        MSG_ERROR("Number of eigen values differ from number of vectors")
      end if
  
      if ( space(matrixA) == SPACE_C ) then
        cplex = 2
        istwf_k = 1
      else
        cplex = 1
        istwf_k = 2
      endif
  
      call xgBlock_getSize(matrixA,nbli_global,nbco_global)
  
      call xgBlock_reverseMap(matrixA,matrix,nbli_global,nbco_global)
      call xgBlock_reverseMap(eigenvalues,eigenvalues_tmp,nbco_global,1)
      cptr = c_loc(eigenvalues_tmp)
      call c_f_pointer(cptr,vector,(/ nbco_global /))
  
      call compute_eigen1(xgScalapack%comms(M__SLK), &
        toProcessorScalapack(xgScalapack), &
        cplex,nbli_global,nbco_global,matrix,vector,istwf_k)

    end if

    call timab(M__tim_heev,2,tsec)

    call xgScalapack_scatter(xgScalapack,matrixA)
    call xgScalapack_scatter(xgScalapack,eigenvalues)
    call xmpi_barrier(xgScalapack%comms(M__WORLD))
#else
   MSG_ERROR("ScaLAPACK support not available")
   ABI_UNUSED(xgScalapack%verbosity)
   ABI_UNUSED(matrixA%normal)
   ABI_UNUSED(eigenvalues%normal)
#endif

  end subroutine xgScalapack_heev

  !This is for testing purpose.
  !May not be optimal since I do not control old implementation but at least gives a reference.
  subroutine xgScalapack_hegv(xgScalapack,matrixA,matrixB,eigenvalues)
    use iso_c_binding

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_hegv'
 use interfaces_18_timing
!End of the abilint section

    type(xgScalapack_t), intent(inout) :: xgScalapack
    type(xgBlock_t)    , intent(inout) :: matrixA
    type(xgBlock_t)    , intent(inout) :: matrixB
    type(xgBlock_t)    , intent(inout) :: eigenvalues
#ifdef HAVE_LINALG_SCALAPACK
    double precision, pointer :: matrix1(:,:) !(cplex*nbli_global,nbco_global)
    double precision, pointer :: matrix2(:,:) !(cplex*nbli_global,nbco_global)
    double precision, pointer :: eigenvalues_tmp(:,:)
    double precision, pointer :: vector(:)
    double precision :: tsec(2)
    integer :: cplex
    integer :: istwf_k
    integer :: nbli_global, nbco_global
    type(c_ptr) :: cptr
#endif

#ifdef HAVE_LINALG_SCALAPACK
    call timab(M__tim_hegv,1,tsec)

    ! Keep only working processors 
    if ( xgScalapack%comms(M__SLK) /= xmpi_comm_null ) then

      call xgBlock_getSize(eigenvalues,nbli_global,nbco_global)
      if ( cols(matrixA) /= cols(matrixB) ) then
        MSG_ERROR("Matrix A and B don't have the same number of vectors")
      end if

      if ( cols(matrixA) /= nbli_global ) then
        MSG_ERROR("Number of eigen values differ from number of vectors")
      end if

      if ( space(matrixA) == SPACE_C ) then
        cplex = 2
        istwf_k = 1
      else
        cplex = 1
        istwf_k = 2
      endif

      call xgBlock_getSize(matrixA,nbli_global,nbco_global)

      call xgBlock_reverseMap(matrixA,matrix1,nbli_global,nbco_global)
      call xgBlock_reverseMap(matrixB,matrix2,nbli_global,nbco_global)
      call xgBlock_reverseMap(eigenvalues,eigenvalues_tmp,nbco_global,1)
      cptr = c_loc(eigenvalues_tmp)
      call c_f_pointer(cptr,vector,(/ nbco_global /))

      call compute_eigen2(xgScalapack%comms(M__SLK), &
        toProcessorScalapack(xgScalapack), &
        cplex,nbli_global,nbco_global,matrix1,matrix2,vector,istwf_k)
    end if

    call timab(M__tim_hegv,2,tsec)

    call xgScalapack_scatter(xgScalapack,matrixA)
    call xgScalapack_scatter(xgScalapack,eigenvalues)
    call xmpi_barrier(xgScalapack%comms(M__WORLD))
#else
   MSG_ERROR("ScaLAPACK support not available")
   ABI_UNUSED(xgScalapack%verbosity)
   ABI_UNUSED(matrixA%normal)
   ABI_UNUSED(matrixB%normal)
   ABI_UNUSED(eigenvalues%normal)
#endif

  end subroutine xgScalapack_hegv


  subroutine xgScalapack_scatter(xgScalapack,matrix)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_scatter'
 use interfaces_18_timing
!End of the abilint section

    type(xgScalapack_t), intent(in   ) :: xgScalapack
    type(xgBlock_t)    , intent(inout) :: matrix
    double precision, pointer :: tab(:,:)
    double precision :: tsec(2)
    integer :: cols, rows
    integer :: ierr,req
    integer :: sendto, receivefrom
    integer :: lap

    call timab(M__tim_scatter,1,tsec)

    call xgBlock_getSize(matrix,rows,cols)
    call xgBlock_reverseMap(matrix,tab,rows,cols)

    if ( xgScalapack%comms(M__SLK) /= xmpi_comm_null ) then 
      lap = 1
      sendto = xgScalapack%rank(M__WORLD) + lap*xgScalapack%size(M__SLK)
      do while ( sendto < xgScalapack%size(M__WORLD) ) 
        !call xmpi_send(tab,sendto,sendto,xgScalapack%comms(M__WORLD),ierr)
        call xmpi_isend(tab,sendto,sendto,xgScalapack%comms(M__WORLD),req,ierr)
        if ( ierr /= 0 ) then
          MSG_ERROR("Error sending data")
        end if
        lap = lap+1
        sendto = xgScalapack%rank(M__WORLD) + lap*xgScalapack%size(M__SLK)
      end do
    else if ( xgScalapack%comms(M__UNUSED) /= xmpi_comm_null ) then
      receivefrom = MODULO(xgScalapack%rank(M__WORLD), xgScalapack%size(M__SLK))
      if ( receivefrom >= 0 ) then
        !call xmpi_recv(tab,receivefrom,xgScalapack%rank(M__WORLD),xgScalapack%comms(M__WORLD),ierr)
        call xmpi_irecv(tab,receivefrom,xgScalapack%rank(M__WORLD),xgScalapack%comms(M__WORLD),req,ierr)
        if ( ierr /= 0 ) then
          MSG_ERROR("Error receiving data")
        end if
      end if
    else
      MSG_BUG("Error scattering data")
    end if

    call timab(M__tim_scatter,2,tsec)

  end subroutine xgScalapack_scatter


  subroutine  xgScalapack_free(xgScalapack)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xgScalapack_free'
 use interfaces_18_timing
!End of the abilint section

    type(xgScalapack_t), intent(inout) :: xgScalapack
    double precision :: tsec(2)
#ifdef HAVE_LINALG_SCALAPACK
    integer :: ierr
#endif

    call timab(M__tim_free,1,tsec)
#ifdef HAVE_LINALG_SCALAPACK
    if ( xgScalapack%comms(M__SLK) /= xmpi_comm_null ) then
      call BLACS_GridExit(xgScalapack%grid%ictxt)
      call MPI_Comm_free(xgScalapack%comms(M__SLK),ierr)
    end if
    if ( xgScalapack%comms(M__UNUSED) /= xmpi_comm_null ) then
      call MPI_Comm_free(xgScalapack%comms(M__UNUSED),ierr)
    end if 
#else
    ABI_UNUSED(xgScalapack%verbosity)
#endif
    call timab(M__tim_free,2,tsec)

  end subroutine xgScalapack_free

end module m_xgScalapack
!!***
