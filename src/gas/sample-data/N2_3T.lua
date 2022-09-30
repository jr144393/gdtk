-- Auto-generated by prep-gas on: 04-Jan-2022 12:03:18

model = 'CompositeGas'
species = {'N2', }

physical_model = 'three-temperature-gas'

db = {}
db['N2'] = {}
db['N2'].type = 'molecule'
db['N2'].molecule_type = 'linear'
db['N2'].vib_data = {
  model = 'harmonic',
  theta_v = 3393.44
}
db['N2'].electronic_levels = {
  model = 'two-level',
  Te = {0.0, 50203.66},
  g = {1, 3}
}
db['N2'].atomicConstituents = { N=2, }
db['N2'].charge = 0
db['N2'].M = 2.80134000e-02
db['N2'].Hf = 0.00000000e+00
db['N2'].M = 2.80134000e-02
db['N2'].sigma = 3.62100000
db['N2'].epsilon = 97.53000000
db['N2'].Lewis = 1.15200000
db['N2'].thermoCoeffs = {
  origin = 'CEA',
  nsegments = 3, 
  T_break_points = { 200.00, 1000.00, 6000.00, 20000.00, },
  T_blend_ranges = { 400.0, 1000.0, },
  segment0 = {
    2.210371497e+04,
   -3.818461820e+02,
    6.082738360e+00,
   -8.530914410e-03,
    1.384646189e-05,
   -9.625793620e-09,
    2.519705809e-12,
    7.108460860e+02,
   -1.076003744e+01,
  },
  segment1 = {
    5.877124060e+05,
   -2.239249073e+03,
    6.066949220e+00,
   -6.139685500e-04,
    1.491806679e-07,
   -1.923105485e-11,
    1.061954386e-15,
    1.283210415e+04,
   -1.586640027e+01,
  },
  segment2 = {
    8.310139160e+08,
   -6.420733540e+05,
    2.020264635e+02,
   -3.065092046e-02,
    2.486903333e-06,
   -9.705954110e-11,
    1.437538881e-15,
    4.938707040e+06,
   -1.672099740e+03,
  },
}
