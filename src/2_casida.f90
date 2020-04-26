include 'parse.f90'

module Eigenvalue
    use parse
    implicit none
contains

pure function calculateKx(C, e) result(Kx)
    real(8), dimension(nEH, nEH) :: Kx 
    real(8), intent(in), dimension(:,:) :: C
    real(8), intent(in), dimension(:) :: e
    integer :: i, a, j, b, ia, jb

    do ia = 1, nEH
        do jb = 1, nEH
            call one_to_two(ia, i, a)
            call one_to_two(jb, j, b)
            Kx(ia,jb) = sum(C(:,i) * C(:,j) * C(:,a) * C(:,b))
        end do
    end do
end function calculateKx

pure function calculateKd(C, e, WS, mode, omega) result(Kd)
    real(8), dimension(nEH, nEH) :: Kd
    real(8), intent(in), dimension(:,:) :: C
    real(8), intent(in), dimension(:,:) :: WS
    real(8), intent(in), dimension(:) :: e
    character(*), intent(in) :: mode
    real(8), intent(in), optional :: omega

    real(8) :: omega_0, EA, EB
    integer :: a, b, i, j, l, m, p, q, ia, jb

    Kd = 0
    select case (mode)
        case ('Hartree')
            Kd = 0
        case ('Hartree-Fock')
            do ia = 1, nEH
            do jb = 1, nEH
                call one_to_two(ia, i, a)
                call one_to_two(jb, j, b)
                Kd(ia,jb) = sum(C(:,i) * C(:,j) * C(:,a) * C(:,b))
            end do
            end do
        case default
            do ia = 1, nEH
            do jb = 1, nEH
                call one_to_two(ia, i, a)
                call one_to_two(jb, j, b)
                do l = 1, n
                do m = 1, n
                ! do p = 1, n
                ! do q = 1, n
                    ! Kd(ia,jb) = Kd(ia,jb) + C(l,a) * C(m,i) * C(p,b) * C(q,j) * W(l,m,p,q)
                ! end do
                ! end do
                    Kd(ia,jb) = Kd(ia,jb) + C(l,a) * C(m,i) * C(l,b) * C(m,j) * WS(l,m)
                end do
                end do
            end do
            end do
    end select
    if (mode == 'BSE_dynamic') then
        omega_0 = e(n/2+1) - e(n/2)
        do ia = 1, nEH
        do jb = 1, nEH
            call one_to_two(ia, i, a)
            call one_to_two(jb, j, b)
            EA = omega - (e(b) - e(i))
            EB = omega - (e(a) - e(j))
            Kd(ia,jb) = Kd(ia,jb) * (omega_0 / (omega_0 - EA) + omega_0 / (omega_0 - EB)) / 2
        end do
        end do
    end if
end function calculateKd

! pure function calculateG(omega, bandgap, e) result(G)
!     real(8), dimension(Nvir2, Nocc2, 2) :: G
!     real(8), intent(in), dimension(:) :: e
!     real(8), intent(in) :: omega, bandgap
!     integer :: a, b, i, j
!     do a = 1, Nvir
!         do b = 1, Nvir
!             do i = 1, Nocc
!                 do j = 1, Nocc
!                     G(j3(a,b),j2(i,j),1) = bandgap - omega - (e(Nocc+b) - e(i))
!                     G(j3(a,b),j2(i,j),2) = bandgap - omega - (e(Nocc+a) - e(j))
!                 end do
!             end do
!         end do
!     end do
! end function calculateG

! pure function recalculateKd(C, e, V, omega, bandgap) result(Kd)
!     real(8), dimension(nEH, nEH) :: Kd
!     real(8), intent(in), dimension(:,:) :: C, V
!     real(8), intent(in), dimension(:) :: e, omega
!     real(8), dimension(Nvir2, Nocc2, 2) :: G
!     real(8), dimension(N,1) :: vector
!     real(8), dimension(Nocc2,1) :: c2v
!     real(8), dimension(1,Nvir2) :: c3v
!     real(8), intent(in) :: bandgap
!     integer :: il

!     Kd = matmul(CC2T, CC3)
!     do il = 1, 2*nEH
!         G = calculateG(omega(il), bandgap, e)
!         vector = matmul(CC1, V(1:nEH,il:il))
!         c2v = matmul(CC2T, vector)
!         c3v = matmul(transpose(vector), CC3)
!         Kd = Kd + matmul(c2v, c3v) / G(:,:,1)
!         vector = matmul(CC1, V(nEH+1:2*nEH,il:il))
!         c2v = matmul(CC2T, vector)
!         c3v = matmul(transpose(vector), CC3)
!         Kd = Kd + matmul(c2v, c3v) / G(:,:,2)
!     end do
! end function recalculateKd

pure function prepareCasida(D, Kx, Kd) result(M)
    real(8), dimension(2*nEH, 2*nEH) :: M
    real(8), intent(in), dimension(:,:) :: D, Kx, Kd
    real(8), dimension(nEH, nEH) :: A, B

    A = D + 2 * Kx - Kd
    B = 2 * Kx - Kd
    M(1:nEH, 1:nEH) = A
    M(1:nEH, nEH+1:2*nEH) = B
    M(nEH+1:2*nEH, 1:nEH) = -B
    M(nEH+1:2*nEH, nEH+1:2*nEH) = -A
end function prepareCasida

subroutine Casida(M, omega, V)
    ! LAPACK eigensolver requires complex vector and matrix to store the real and imaginary part,
    ! but the imaginary part should be 0, so we discard it
    real(8), intent(in), dimension(:,:) :: M
    real(8), intent(out), dimension(:) :: omega
    real(8), intent(out), dimension(:,:), optional :: V
    complex(8), dimension(2*nEH, 2*nEH) :: M_c
    complex(8), dimension(2*nEH, 2*nEH) :: Vl_c, Vr_c
    complex(8), dimension(2*nEH) :: omega_c
    integer :: index, index_

    M_c = M
    call geev(M_c, omega_c, Vl_c, Vr_c)
    omega = real(omega_c)
    if (present(V)) V = abs(Vr_c)
    ! We check that the imaginary part should be very small
    ! print *, maxval(aimag(omega_c))
    ! Sort the eigenvalues
    do index = 1, 2 * nEH
        do index_ = 1, 2 * nEH - 1
            if (omega(index_) > omega(index_ + 1)) then
                omega(index_:index_+1) = omega(index_+1:index_:-1)
                if (present(V)) V(:,index_:index_+1) = V(:,index_+1:index_:-1)
            end if
        end do
    end do
end subroutine Casida

subroutine CasidaTDA(M, omega, V)
    real(8), intent(in), dimension(:,:) :: M
    real(8), intent(out), dimension(:) :: omega
    real(8), intent(out), dimension(:,:), optional :: V

    real(8), dimension(nEH, nEH) :: M_
    integer :: index, index_
    
    M_ = M(1:nEH,1:nEH)
    call syev(M_, omega(1:nEH))
    if (present(V)) then
        V = 0
        V(1:nEH,1:nEH) = M_
    end if
    do index = 1, nEH
        do index_ = 1, nEH - 1
            if (omega(index_) > omega(index_ + 1)) then
                omega(index_:index_+1) = omega(index_+1:index_:-1)
                if (present(V)) V(:,index_:index_+1) = V(:,index_+1:index_:-1)
            end if
        end do
    end do
end subroutine
end module Eigenvalue

program main
    use Eigenvalue
    implicit none
    ! Support calculation of four modes:
    ! Hartree, Hartree-Fock, BSE_static, BSE_dynamic
    character(*), parameter :: mode = 'BSE_dynamic'
    real(8), parameter :: tolerance = 1d-4
    real(8) :: bandgapLeft = 1.6d0, bandgapRight = 1.8d0, bandgap = 0
    real(8), dimension(2*nEH, 2*nEH) :: M, V
    real(8), dimension(2*nEH) :: omega
    real(8), dimension(nEH,nEH) :: D, Kx, Kd
    real(8), dimension(n,n,n,n) :: Q, W
    real(8), dimension(n,n) :: C, WS
    real(8), dimension(n) :: e

    call readOrbitals(C, e)
    D = calculateD(e)
    ! Q = calculateQ(C, e)
    ! W = calculateW(Q)
    WS = calculateWS(C, e)
    Kx = calculateKx(C, e)
    if (mode == 'BSE_dynamic') then
        ! Now, let f(ω) = lowestExcitation(M(ω)) - ω, we
        ! know that f(1.7) > 0, f(1.8) < 0, so we use bisection.
        do while (bandgapRight - bandgapLeft > tolerance)
            bandgap = (bandgapLeft + bandgapRight) / 2
            print *, bandgap
            Kd = calculateKd(C, e, WS, mode, bandgap)
            M = prepareCasida(D, Kx, Kd)
            call Casida(M, omega)
            if ((omega(nEH + 1) - bandgap) > 0) then
                bandgapLeft = bandgap
            else
                bandgapRight = bandgap
            end if
        end do
    else
        Kd = calculateKd(C, e, WS, mode)
        M = prepareCasida(D, Kx, Kd)
        call Casida(M, omega)
        bandgap = omega(nEH + 1)
    end if
    open(11, file='output/bse/casida_'//mode//'.dat')
    write(11, '(f10.5)') bandgap
    close(11)
end program