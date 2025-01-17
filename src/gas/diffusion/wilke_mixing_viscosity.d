/**
 * wilke_mixing_visc.d
 * Implements Wilke's mixing rule to compute the
 * viscosity a mixture of gases. The notation follows
 * that used by White (2006).
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

module gas.diffusion.wilke_mixing_viscosity;

import std.math;
import nm.complex;
import nm.number;
import util.msg_service;

import gas.gas_model;
import gas.gas_state;
import gas.diffusion.viscosity;

class WilkeMixingViscosity : Viscosity {
public:
    this(in Viscosity[] vms, in double[] mol_masses)
    in {
        assert(vms.length == mol_masses.length,
               brokenPreCondition("vms.length and mol_masses.length", __LINE__, __FILE__));
    }
    do {
        foreach (v; vms) {
            _vms ~= v.dup;
        }
        _mol_masses = mol_masses.dup;
        _x.length = _mol_masses.length;
        _mu.length = _mol_masses.length;
        _phi.length = _mol_masses.length;
        foreach (ref p; _phi) {
            p.length = _mol_masses.length;
        }
    }
    this(in WilkeMixingViscosity src) {
        foreach (v; src._vms) {
            _vms ~= v.dup;
        }
        _mol_masses = src._mol_masses.dup;
        _x.length = _mol_masses.length;
        _mu.length = _mol_masses.length;
        _phi.length = _mol_masses.length;
        foreach (ref p; _phi) {
            p.length = _mol_masses.length;
        }
    }
    override WilkeMixingViscosity dup() const {
        return new WilkeMixingViscosity(this);
    }

    override number eval(in GasState Q) {

        // 1. Evaluate the mole fractions
        massf2molef(Q.massf, _mol_masses, _x);
        // 2. Calculate the component viscosities
        for ( auto i = 0; i < Q.massf.length; ++i ) {
            _mu[i] =  _vms[i].eval(Q);
        }
        // 3. Calculate interaction potentials
        for ( auto i = 0; i < Q.massf.length; ++i ) {
            for ( auto j = 0; j < Q.massf.length; ++j ) {
                number numer = pow((1.0 + sqrt(_mu[i]/_mu[j])*pow(_mol_masses[j]/_mol_masses[i], 0.25)), 2.0);
                number denom = sqrt(8.0 + 8.0*_mol_masses[i]/_mol_masses[j]);
                _phi[i][j] = numer/denom;
            }
        }
        // 4. Apply mixing formula
        number sum;
        number mu = 0.0;
        for ( auto i = 0; i < Q.massf.length; ++i ) {
            if ( _x[i] < SMALL_MOLE_FRACTION ) continue;
            sum = 0.0;
            for ( auto j = 0; j < Q.massf.length; ++j ) {
                if ( _x[j] < SMALL_MOLE_FRACTION ) continue;
                sum += _x[j]*_phi[i][j];
            }
            mu += _mu[i]*_x[i]/sum;
        }
        return mu;
    }

private:
    Viscosity[] _vms; // component viscosity models
    double[] _mol_masses; // component molecular weights
    // Working array space
    number[] _x;
    number[] _mu;
    number[][] _phi;
}

version(wilke_mixing_viscosity_test) {
    int main() {
        import gas.diffusion.sutherland_viscosity;
        // Placeholder test. Redo with CEA curves.
        number T = 300.0;
        auto vm_N2 = new SutherlandViscosity(273.0, 1.663e-5, 107.0);
        auto vm_O2 = new SutherlandViscosity(273.0, 1.919e-5, 139.0);
        auto vm = new WilkeMixingViscosity([vm_N2, vm_O2], [28.0e-3, 32.0e-3]);

        auto gd = GasState(2, 0);
        gd.T = T;
        gd.massf[0] = 0.8;
        gd.massf[1] = 0.2;
        vm.update_viscosity(gd);
        assert(isClose(1.84005e-05, gd.mu, 1.0e-4, 0.0), failedUnitTest());

        return 0;
    }
}

