/**
 * wilke_mixing_therm_cond.d
 * Implements Wilke's mixing rule to compute the
 * thermal conductivity of a mixture of gases.
 * The notation follows that used by White (2006).
 *
 * References:
 * Wilke, C.R. (1950)
 * A Viscosity Equation for Gas Mixtures.
 * Journal of Chemical Physics, 18:pp. 517--519
 *
 * White, F.M. (2006)
 * Viscous Fluid Flow, Third Edition
 * NcGraw Hill, New York
 * (see page 34)
 *
 * Author: Rowan G. and Peter J.
 * Version: 2014-09-08 -- initial cut
 */

module gas.diffusion.wilke_mixing_therm_cond;

import std.math;
import nm.complex;
import nm.number;
import util.msg_service;

import gas.gas_model;
import gas.gas_state;
import gas.diffusion.therm_cond;

class WilkeMixingThermCond : ThermalConductivity {
public:
    this(in ThermalConductivity[] tcms, in double[] mol_masses)
    in {
        assert(tcms.length == mol_masses.length,
               brokenPreCondition("tcms.length and mol_masses.length", __LINE__, __FILE__));
    }
    do {
        foreach (tcm; tcms) {
            _tcms ~= tcm.dup;
        }
        _mol_masses = mol_masses.dup;
        _x.length = _mol_masses.length;
        _k.length = _mol_masses.length;
        _phi.length = _mol_masses.length;
        foreach (ref p; _phi) {
            p.length = _mol_masses.length;
        }
    }
    this(in WilkeMixingThermCond src) {
        foreach (tcm; src._tcms) {
            _tcms ~= tcm.dup;
        }
        _mol_masses = src._mol_masses.dup;
        _x.length = _mol_masses.length;
        _k.length = _mol_masses.length;
        _phi.length = _mol_masses.length;
        foreach ( ref p; _phi) {
            p.length = _mol_masses.length;
        }
    }
    override WilkeMixingThermCond dup() const {
        return new WilkeMixingThermCond(this);
    }

    override number eval(ref const(GasState) Q, int imode) {
        // 1. Evaluate the mole fractions
        massf2molef(Q.massf, _mol_masses, _x);
        // 2. Calculate the component thermoconductivities
        for ( auto isp = 0; isp < Q.massf.length; ++isp ) {
            _k[isp] = _tcms[isp].eval(Q, -1);
        }
        // 3. Calculate interaction potentials
        for ( auto i = 0; i < Q.massf.length; ++i ) {
            for ( auto j = 0; j < Q.massf.length; ++j ) {
                number numer = pow((1.0 + sqrt(_k[i]/_k[j])*pow(_mol_masses[j]/_mol_masses[i], 0.25)), 2.0);
                number denom = sqrt(8.0 + 8.0*_mol_masses[i]/_mol_masses[j]);
                _phi[i][j] = numer/denom;
            }
        }
        // 4. Apply mixing formula
        number sum;
        number k = 0.0;
        for ( auto i = 0; i < Q.massf.length; ++i ) {
            if ( _x[i] < SMALL_MOLE_FRACTION ) continue;
            sum = 0.0;
            for ( auto j = 0; j < Q.massf.length; ++j ) {
                if ( _x[j] < SMALL_MOLE_FRACTION ) continue;
                sum += _x[j]*_phi[i][j];
            }
            k += _k[i]*_x[i]/sum;
        }
        return k;
    }

private:
    ThermalConductivity[] _tcms; // component viscosity models
    double[] _mol_masses; // component molecular weights
    // Working array space
    number[] _x;
    number[] _k;
    number[][] _phi;
}


version(wilke_mixing_therm_cond_test) {
    int main()
    {
        import std.stdio;
        import gas.diffusion.sutherland_therm_cond;
        // Placeholder test. Redo with CEA curves.
        number T = 300.0;
        auto tcm_N2 = new SutherlandThermCond(273.0, 0.0242, 150.0);
        auto tcm_O2 = new SutherlandThermCond(273.0, 0.0244, 240.0);
        auto tcm = new WilkeMixingThermCond([tcm_N2, tcm_O2], [28.0e-3, 32.0e-3]);

        auto gd = GasState(2, 0);
        gd.T = T;
        gd.massf[0] = 0.8;
        gd.massf[1] = 0.2;
        tcm.update_thermal_conductivity(gd);
        assert(isClose(0.0263063, gd.k, 1.0e-3), failedUnitTest());

        return 0;
    }
}

