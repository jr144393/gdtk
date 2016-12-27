! ideal_air_fortran.f
! Ideal-air gas model for use in the CFD codes, via the IdealAirProxy class.
!
! Author: Peter J. and Rowan G.
! Version: 2016-12-27: initial cut, to explore the mixed-language build.
!
! For connecting to the Eilmer flow solver, we meet part way
! by building a C interface to all of the procedures and functions
! that will be called by the D code.
!
! Compile with
! $ gfortran -c -ffree-form ideal_air_fortran.f
!
! It's been more than 30 years since last doing any Fortran programming
! and the code below will reflect that lack of practice.
!
module ideal_air_fortran
  use iso_c_binding
  contains

subroutine iaf_init() bind(C, name='iaf_init')
  !
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  !
  real(kind=8) prandtl
  common /iaf_trans/ prandtl
  !
  ! Thermodynamic constants
  Runiv = 8.31451 ! Universal gas constant in J/(mol.K) -- Tipler (1991)
  mMass = 0.02896 ! molecular mass in kg/mol
  Rgas = Runiv/mMass ! gas constant J/kg/K
  gamma = 1.4 ! ratio of specific heats
  Cv = Rgas/(gamma-1.0) ! specific heat capacity for constant volume, J/kg/K
  Cp = Rgas*gamma/(gamma-1.0) ! specific heat capacity for constant pressure, J/kg/K
  !
  ! Reference values for entropy
  s1 = 0.0 ! reference entropy, J/kg/K
  T1 = 298.15 ! reference temperature for entropy calculation, K
  p1 = 101.325e3 ! reference pressure for entropy calculation, Pa
  !
  ! Molecular transport coefficent constants.
  ! Viscosity parameters
  ! FIX-ME by filling in
  !
  ! Thermal conductivity
  ! FIX-ME by filling in
end subroutine iaf_init

integer(c_int) function iaf_n_species() result (n) bind(C, name='iaf_n_species')
  n = 1
  return
end function iaf_n_species

integer(c_int) function iaf_n_modes() result (n) bind(C, name='iaf_n_modes')
  n = 0
  return
end function iaf_n_modes

real(c_double) function iaf_mol_mass(i) result (mm) bind(C, name='iaf_mol_mass')
  integer(c_int), VALUE :: i
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  mm = mMass ! We have only the one species in this model.
end function iaf_mol_mass
	
subroutine update_thermo_from_pT(p, Ttr, rho, u, massf) bind(C, name='iaf_update_thermo_from_pT')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  rho = p/(Ttr*Rgas)
  u = Cv*Ttr
end subroutine update_thermo_from_pT
	
subroutine update_thermo_from_rhoe(p, Ttr, rho, u, massf) bind(C, name='iaf_update_thermo_from_rhoe')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  Ttr = u/Cv
  p = rho*Rgas*Ttr
end subroutine update_thermo_from_rhoe
	
subroutine update_thermo_from_rhoT(p, Ttr, rho, u, massf) bind(C, name='iaf_update_thermo_from_rhoT')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  p = rho*Rgas*Ttr
  u = Cv*Ttr
end subroutine update_thermo_from_rhoT
	
subroutine update_thermo_from_rhop(p, Ttr, rho, u, massf) bind(C, name='iaf_update_thermo_from_rhop')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  Ttr = p/(rho*Rgas)
  u = Cv*Ttr
end subroutine update_thermo_from_rhop
	
subroutine update_thermo_from_ps(p, Ttr, rho, u, massf, s) bind(C, name='iaf_update_thermo_from_ps')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(c_double) :: s
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  Ttr = T1 * exp((1.0/Cp)*((s - s1) + Rgas * log(p/p1)))
  call update_thermo_from_pT(p, Ttr, rho, u, massf)
end subroutine update_thermo_from_ps
	
subroutine update_thermo_from_hs(p, Ttr, rho, u, massf, h, s) bind(C, name='iaf_update_thermo_from_hs')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(c_double) :: h
  real(c_double) :: s
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  Ttr = h/Cp
  p = p1 * exp((1.0/Rgas)*(s1 - s + Cp*log(Ttr/T1)))
  call update_thermo_from_pT(p, Ttr, rho, u, massf)
end subroutine update_thermo_from_hs
	
subroutine update_sound_speed(p, Ttr, rho, u, massf, a) bind(C, name='iaf_update_sound_speed')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(c_double) :: a
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  a = sqrt(gamma*Rgas*Ttr)
end subroutine update_sound_speed
	
subroutine update_trans_coeffs(p, Ttr, rho, u, massf, mu, k) bind(C, name='iaf_update_trans_coeffs')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(c_double) :: rho
  real(c_double) :: u
  real(c_double) :: massf(*)
  real(c_double) :: mu
  real(c_double) :: k
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  mu = 1.84691e-05 ! FIX-ME dummy value for unit test
  k = 0.0262449 ! FIX-ME dummy value for unit test
end subroutine update_trans_coeffs

real(c_double) function get_Cv() result (val) bind(C, name='iaf_get_Cv')
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  val = Cv
  return
end function get_Cv

real(c_double) function get_Cp() result (val) bind(C, name='iaf_get_Cp')
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  val = Cp
  return
end function get_Cp

real(c_double) function get_Rgas() result (val) bind(C, name='iaf_get_Rgas')
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  val = Rgas
  return
end function get_Rgas

real(c_double) function entropy(p, Ttr) result (val) bind(C, name='iaf_entropy')
  real(c_double) :: p
  real(c_double) :: Ttr
  real(kind=8) Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  common /iaf_thermo/ Runiv, mMass, Rgas, gamma, Cv, Cp, s1, T1, p1
  val = s1 + Cp * log(Ttr/T1) - Rgas * log(p/p1)
  return
end function entropy

end module ideal_air_fortran
