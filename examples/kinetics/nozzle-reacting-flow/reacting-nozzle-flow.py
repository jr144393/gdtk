# reacting-nozzle-flow.py
#
# Combustion in a supersonic stream of variable cross-section.
#
# The constant area case is set up to approximate the Bittker-Scullin case 3,
# as used by Fabian Zander in the hydrogen-combustion test case. 
#
# PJ 2019-12-05 adaption of the constant-area case to variable area.
#
# Run with the commands:
# $ prep-gas combusting-species.inp h2-o2-n2-9sp.lua
# $ prep-chem h2-o2-n2-9sp.lua Bittker-Scullin.lua h2-o2-n2-9sp-18r.lua
# $ python3 reacting-nozzle-flow.py
#
#------------------------------------------------------------------
from eilmer.gas import GasModel, GasState, ThermochemicalReactor

def duct_area(x):
    if 0:
        # Constant-area
        return 1.0
    else:
        # Expanding duct.
        return 1.0 + x

# Things that we'll make use of shortly.
sample_header = "# x(m) A(m**2) rho(kg/m**3) p(Pa) T(degK) e(J/kg) v(m/s) " + \
                "massf_OH massf_H2O dt_suggest(s)"

def sample_data(x, area, v, gas, dt_suggest):
    return "%g %g %g %g %g %g %g %g %g %g " % \
        (x, area, gas.rho, gas.p, gas.T, gas.u, v,
         gas.massf[gas.gmodel.species_names.index("OH")],
         gas.massf[gas.gmodel.species_names.index("H2O")],
         dt_suggest)

def eos_derivatives(gas0, gmodel, tol=0.0001):
    # Finite difference evaluation, assuming that gas0 is valid state already.
    gas1 = GasState(gmodel)
    gas1.copy_values(gas0)
    p0 = gas0.p; rho0 = gas0.rho; u0 = gas0.u
    #
    drho = rho0 * tol; gas1.rho = rho0 + drho
    gas1.update_thermo_from_rhou()
    dpdrho = (gas1.p - p0)/drho
    #
    gas1.rho = rho0; du = u0 * tol; gas1.u = u0 + du
    gas1.update_thermo_from_rhou()
    dpdu = (gas1.p - p0)/du
    #
    return dpdrho, dpdu

#------------------------------------------------------------------
# Start the main script...
debug = False
print("# Reacting nozzle flow.")
print(sample_header)

# Gas model setup
gmodel = GasModel("h2-o2-n2-9sp.lua")
nsp = gmodel.n_species
nmodes = gmodel.n_modes
if debug: print("nsp=", nsp, " nmodes=", nmodes, " gmodel=", gmodel)

print("# Gas properties at the start of the pipe.")
gas0 = GasState(gmodel)
gas0.p = 96.87e3 # Pa
x = 0.0 # m  (inlet of duct)
area = duct_area(x)
v = 4551.73 # m/s
gas0.T = 1559.0 # degree K
gas0.molef = {"O2":0.1480, "N2":0.5562, "H2":0.2958}
gas0.update_thermo_from_pT()
dt_suggest = 1.0e-8  # suggested starting time-step for chemistry updater
print(sample_data(x, area, v, gas0, dt_suggest))

print("# Start reactions...")
reactor = ThermochemicalReactor(gmodel, "h2-o2-n2-9sp-18r.lua") 
t = 0 # time is in seconds
t_final = 22.0e-6
t_inc = 0.05e-6
nsteps = int(t_final / t_inc)
for j in range(1, nsteps+1):
    # At the start of the step...
    rho = gas0.rho; T = gas0.T; p = gas0.p; u = gas0.u
    #
    # Do the chemical increment.
    gas1 = GasState(gmodel) # make the new one as a clone
    gas1.copy_values(gas0)
    dt_suggest = reactor.update_state(gas1, t_inc, dt_suggest)
    gas1.update_thermo_from_rhou()
    #
    du_chem = gas1.u - u
    dp_chem = gas1.p - p
    if debug: print("# du_chem=", du_chem, "dp_chem=", dp_chem)
    #
    # Update the independent variables for the end point of this step.
    # Simple, Euler update for the spatial stepper.
    t1 = t + t_inc
    x1 = x + v*t_inc
    area1 = duct_area(x1)
    #
    # Do the gas-dynamic accommodation after the chemical change.
    darea = area1 - area
    etot = u + 0.5*v*v
    dfdr, dfdu = eos_derivatives(gas1, gmodel)
    if debug: print("# dfdr=", dfdr, "dfdu=", dfdu)
    # Linear solve to get the accommodation increments.
    #   [v*A,      rho*A,          0.0, 0.0    ]   [drho  ]   [-rho*v*dA       ]
    #   [0.0,      rho*v,          1.0, 0.0    ] * [dv    ] = [-dp_chem        ]
    #   [v*etot*A, (rho*etot+p)*A, 0.0, rho*v*A]   [dp_gda]   [-rho*v*A*du_chem]
    #   [dfdr,     0.0,           -1.0, dfdu   ]   [du_gda]   [0.0             ]
    #
    # Compute the accommodation increments using expressions from Maxima.
    denom = area*(rho*rho*v*v - dfdr*rho*rho - dfdu*p)
    drho = (area*(dp_chem - du_chem*dfdu)*rho*rho - darea*rho**3*v*v) / denom
    dv = (area*(du_chem*dfdu - dp_chem)*rho +
          darea*(dfdr*rho*rho + dfdu*p))*v / denom
    dp_gda = -((darea*dfdr*rho**3 + area*dfdu*du_chem*rho*rho + darea*dfdu*p*rho)*v*v
               - area*dfdr*dp_chem*rho*rho - area*dfdu*dp_chem*p) / denom
    du_gda = -(area*(du_chem*rho*rho*v*v - du_chem*dfdr*rho*rho - dp_chem*p)
               + darea*p*rho*v*v) / denom
    if debug: 
        print("# drho=", drho, "dv=", dv, "dp_gda=", dp_gda, "du_gda=", du_gda)
        print("# residuals=", v*area*drho + rho*area*dv + rho*v*darea,
              rho*v*dv + (dp_gda + dp_chem),
              v*etot*drho*area + (rho*etot+p)*area*dv +
              rho*v*area*(du_gda + du_chem) + v*(rho*etot+p)*darea,
              dfdr*drho - dp_gda + dfdu*du_gda)
    # Add the accommodation increments.
    gas1.rho = gas0.rho + drho
    v1 = v + dv
    p1_check = gas1.p + dp_gda
    gas1.u = gas1.u + du_gda
    gas1.update_thermo_from_rhou()
    if debug:
        print("# At new point for step ", j, ": gas1.p=", gas1.p,
              "p1_check=", p1_check, 
              "rel_error=", abs(gas1.p-p1_check)/p1_check)
    # Have now finished the chemical and gas-dynamic update.
    print(sample_data(x1, area1, v1, gas1, dt_suggest))
    # House-keeping for the next step.
    v = v1; t = t1; x = x1; area = area1
    gas0.copy_values(gas1) # gas0 will be used in the next iteration
print("# Done.")