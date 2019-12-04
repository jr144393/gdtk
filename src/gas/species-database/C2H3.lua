db.C2H3 = {}
db.C2H3.atomicConstituents = {C=2,H=3,}
db.C2H3.charge = 0
db.C2H3.M = {
   value = 27.045220e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'Periodic table'
}
db.C2H3.gamma = {
   value = 1.2408e00,
   units = 'non-dimensional',
   description = 'ratio of specific heats at 300.0K',
   reference = 'evaluated using Cp/R from Chemkin-II coefficients'
}
db.C2H3.sigma = {
   value = 4.100,
   units = 'Angstrom',
   description = 'Lennard-Jones potential distance',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.C2H3.epsilon = {
   value = 209.000,
   units = 'K',
   description = 'Lennard-Jones potential well depth.',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.C2H3.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2,
   T_break_points = {200.0, 1000.0, 3500.0},
   T_blend_ranges = {400.0},
   segment0 ={
      0,
      0,
      3.21246645E+00,
      1.51479162E-03,
      2.59209412E-05,
     -3.57657847E-08,
      1.47150873E-11,
      3.48598468E+04,
      8.51054025E+00,
   },
   segment1 = {
      0,
      0,
      3.01672400E+00,
      1.03302292E-02,
     -4.68082349E-06,
      1.01763288E-09,
     -8.62607041E-14,
      3.46128739E+04,
      7.78732378E+00,
   }
}
db.C2H3.ceaThermoCoeffs = {
   notes = 'NASA/TP—2002-211556',
   nsegments = 2,
   T_break_points = {200.0, 1000.0, 6000.0},
   T_blend_ranges = {400.0},
   segment0 = {
     -3.347897e+04,
      1.064104e+03,
     -6.403857e+00,
      3.934515e-02,
     -4.760046e-05,
      3.170071e-08,
     -8.633406e-12,
      3.039123e+04,
      5.809226e+01,
   },
   segment1 = {
      2.718080e+06,
     -1.030957e+04,
      1.836580e+01,
     -1.580131e-03,
      2.680595e-07,
     -2.439004e-11,
      9.209096e-16,
      9.765056e+04,
     -9.760087e+01
    }
}
db.C2H3.chemkinViscosity = {
   notes = 'Generated by species-generator.py',
   nsegments = 1, 
   segment0 ={
      T_lower = 200.000,
      T_upper = 3500.000,
      A = -2.528613897362e+01,
      B = 4.636835198248e+00,
      C = -5.132350983080e-01,
      D = 2.202694867379e-02,
   }
}
db.C2H3.chemkinThermCond = {
   notes = 'Generated by species-generator.py',
   nsegments = 1, 
   segment0 ={
      T_lower = 200.000,
      T_upper = 3500.000,
      A = -1.726898602161e+01,
      B = 3.149807052372e+00,
      C = -1.248614364768e-01,
      D = -2.248078033156e-03,
   }
}

