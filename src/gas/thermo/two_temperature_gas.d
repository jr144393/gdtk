/**
 * thermo/two_temperature_gas.d
 *
 * Author: Rowan G.
 * History: 2021-03-15 -- first refactor from other pieces
 **/

module gas.thermo.two_temperature_gas;

import std.stdio;
import std.math;
import std.string;
import std.conv;
import util.lua;
import util.lua_service;
import nm.complex;
import nm.number;

import gas;
import gas.thermo.thermo_model;
import gas.thermo.cea_thermo_curves;

immutable double T_REF = 298.15; // K (based on CEA reference temperature value)

/**
 * The TwoTemperatureGasMixture class provides a model for thermodynamic behaviour
 * of a two-temperature gas mixture.
 *
 * The assumption in this model is that the translational and rotational energy modes
 * are described by one temperature (T_tr) and the vibrational and electronic energy
 * modes are described my a second temperature (T_ve). The first of these appears in
 * in the GasState as T, and the second as T_modes[0].
 *
 * This model is useful for air mixtures, nitrogen mixtures and carbon dioxide flows.
 * Do not confuse this two temperature model with specialised two temperature models
 * for argon and hydrogen/helium mixtures. In those, the partitioning of energy is
 * focussed on separating the electron as having a distinct temperature from the
 * heavy particles.
 */
class TwoTemperatureGasMixture : ThermodynamicModel {
public:

    this(lua_State *L, string[] speciesNames)
    {
        mNSpecies = to!int(speciesNames.length);
        mR.length = mNSpecies;
        mDel_hf.length = mNSpecies;
        mCpTR.length = mNSpecies;
        ms.length = mNSpecies;
        foreach (isp, spName; speciesNames) {
            if (spName == "e-") mElectronIdx = to!int(isp);
            lua_getglobal(L, "db");
            lua_getfield(L, -1, spName.toStringz);
            double m = getDouble(L, -1, "M");
            mR[isp] = R_universal/m;
            lua_getfield(L, -1, "thermoCoeffs");
            mCurves ~= new CEAThermoCurve(L, mR[isp]);
            lua_pop(L, 1);
            mDel_hf[isp] = mCurves[isp].eval_h(to!number(T_REF));
            string type = getString(L, -1, "type");
            switch (type) {
            case "electron":
                mCpTR[isp] = 0.0;
                break;
            case "atom" :
                mCpTR[isp] = (5./2.)*mR[isp];
                break;
            case "molecule":
                string molType = getString(L, -1, "molecule_type");
                mCpTR[isp] = (molType == "linear") ? (7./2.)*mR[isp] : (8./2.)*mR[isp];
                break;
            default:
                string msg = "TwoTemperatureGas: error trying to match particle type.\n";
                throw new Error(msg);
                
            }
            lua_pop(L, 1);
            lua_pop(L, 1);
        }
    }

    @nogc
    override void updateFromPT(GasState gs)
    {
        updateDensity(gs);
        gs.u = transRotEnergyMixture(gs);
        gs.u_modes[0] = vibElecEnergyMixture(gs, gs.T_modes[0]);
    }

    @nogc
    override void updateFromRhoU(GasState gs)
    {
        // We can compute T by direct inversion since the Cp in 
        // in translation and rotation are fully excited,
        // and, as such, constant.
        number sumA = 0.0;
        number sumB = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            if (isp == mElectronIdx) continue;
            sumA += gs.massf[isp]*(mCpTR[isp]*T_REF - mDel_hf[isp]);
            sumB += gs.massf[isp]*(mCpTR[isp] - mR[isp]);
        }
        gs.T = (gs.u + sumA)/sumB;
        // Next, we can compute T_modes[0] by iteration.
        // We'll use a Newton method since the function
        // should vary smoothly at the polynomial breaks
        // given that we blend the coefficients in those regions.
        gs.T_modes[0] = vibElecTemperature(gs);
        // Now we can compute pressure from the perfect gas
        // equation of state.
        updatePressure(gs);
    }

    @nogc
    override void updateFromRhoT(GasState gs)
    {
        updatePressure(gs);
        gs.u = transRotEnergyMixture(gs);
        gs.u_modes[0] = vibElecEnergyMixture(gs, gs.T_modes[0]);
    }

    @nogc
    override void updateFromRhoP(GasState gs)
    {
        // In this method, we assume that T_modes[0] is set correctly
        // in addition to density and pressure.
        updateTemperatureFromRhoP(gs);
        gs.u = transRotEnergyMixture(gs);
        gs.u_modes[0] = vibElecEnergyMixture(gs, gs.T_modes[0]);
    }

    @nogc
    override void updateFromPS(GasState gs, number s)
    {
        throw new GasModelException("TwoTemperatureGas: updateFromPS() not implemented.");
    }

    @nogc
    override void updateFromHS(GasState gs, number h, number s)
    {
        throw new GasModelException("TwoTemperatureGas: updateFromHS() not implemented.");
    }

    @nogc
    override void updateSoundSpeed(GasState gs)
    {
        // We compute the frozen sound speed
        number gamma = dhdTConstP(gs)/dudTConstV(gs);
        gs.a = sqrt(gamma*gs.p/gs.rho);
    }

    @nogc
    override number dudTConstV(in GasState gs)
    {
        number Cv = 0.0;
        number Cv_tr_rot, Cv_vib;
        foreach (isp; 0 .. mNSpecies) {
            Cv_tr_rot = transRotCvPerSpecies(isp);
            Cv_vib = vibElecCvPerSpecies(gs.T_modes[0], isp);
            Cv += gs.massf[isp] * (Cv_tr_rot + Cv_vib);
        } 
        return Cv;
    }

    @nogc
    override number dhdTConstP(in GasState gs)
    {
        // Using the fact that internal structure specific heats
        // are equal, that is, Cp_vib = Cv_vib
        number Cp = 0.0;
        number Cp_vib;
        foreach (isp; 0 .. mNSpecies) {
            Cp_vib = vibElecCvPerSpecies(gs.T_modes[0], isp);
            Cp += gs.massf[isp] * (mCpTR[isp] + Cp_vib);
        }
        return Cp;
    }

    @nogc
    override number dpdrhoConstT(in GasState gs)
    {
        number sum = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            number T = (isp == mElectronIdx) ? gs.T_modes[0] : gs.T;
            sum += gs.massf[isp] * mR[isp] * T; 
        }
        return sum;
    }

    @nogc
    override number gasConstant(in GasState gs)
    {
        return mass_average(gs, mR);
    }

    @nogc
    override number internalEnergy(in GasState gs)
    {
        number u_tr = transRotEnergyMixture(gs);
        number u_ve = vibElecEnergyMixture(gs, gs.T_modes[0]);
        return u_tr + u_ve;
    }

    @nogc
    override number energyPerSpeciesInMode(in GasState gs, int isp, int imode)
    {
        if (imode == 0) {
            return vibElecEnergyPerSpecies(gs.T_modes[0], isp);
        }
        return transRotEnergyPerSpecies(gs.T, isp);
    }

    
    @nogc
    override number enthalpy(in GasState gs)
    {
        number u = transRotEnergyMixture(gs) + vibElecEnergyMixture(gs, gs.T_modes[0]);
        return u + gs.p/gs.rho;
    }

    @nogc
    override number enthalpyPerSpecies(in GasState gs, int isp)
    {
        number h_tr = mCpTR[isp]*(gs.T - T_REF) + mDel_hf[isp];
        number h_ve = vibElecEnergyPerSpecies(gs.T_modes[0], isp);
        return h_tr + h_ve;
    }

    @nogc
    override number enthalpyPerSpeciesInMode(in GasState gs, int isp, int imode)
    {
        if (imode == 0) {
            return vibElecEnergyPerSpecies(gs.T_modes[0], isp);
        }
        return mCpTR[isp]*(gs.T - T_REF) + mDel_hf[isp];
    }

    @nogc
    override number entropy(in GasState gs)
    {
        foreach ( isp; 0 .. mNSpecies ) {
            ms[isp] = mCurves[isp].eval_s(gs.T) - mR[isp]*log(gs.p/P_atm);
        }
        return mass_average(gs, ms);
    }

    @nogc
    override number entropyPerSpecies(in GasState gs, int isp)
    {
        return mCurves[isp].eval_s(gs.T);
    }
    

    @nogc
    number vibElecEnergyPerSpecies(number Tve, int isp)
    {
        // The electron possess energy only in translation.
        // We put this contribution in the electronic energy since
        // its translation is governed by the vibroelectronic temperature.
        if (isp == mElectronIdx) return (3./2.)* mR[isp] * Tve;
        // For heavy particles
        number h_at_Tve = mCurves[isp].eval_h(Tve);
        number h_ve = h_at_Tve - mCpTR[isp]*(Tve - T_REF) - mDel_hf[isp];
        return h_ve;
    }

    @nogc
    number vibElecEnergyMixture(in GasState gs, number Tve)
    {
        number e_ve = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            e_ve += gs.massf[isp] * vibElecEnergyPerSpecies(Tve, isp);
        }
        return e_ve;
    }
    
    
private:
    double[] mR;
    number[] ms;
    double[] mCpTR;
    number[] mDel_hf;
    CEAThermoCurve[] mCurves;
    int mNSpecies;
    int mElectronIdx = -1; // Set to this in case never set in neutrals-only simulations

    @nogc
    void updateDensity(GasState gs)
    {
        number denom = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            number T = (isp == mElectronIdx) ? gs.T_modes[0] : gs.T;
            denom += gs.massf[isp] * mR[isp] * T;
        }
        gs.rho = gs.p/denom;
    }

    @nogc
    void updatePressure(GasState gs)
    {
        gs.p = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            number T = (isp == mElectronIdx) ? gs.T_modes[0] : gs.T;
            gs.p += gs.rho * gs.massf[isp] * mR[isp] * T;
        }
        // Also set electron pressure, while we're computing pressures.
        if (mElectronIdx != -1) {
            gs.p_e = gs.rho * gs.massf[mElectronIdx] * mR[mElectronIdx] * gs.T_modes[0];
        }
    }

    @nogc
    void updateTemperatureFromRhoP(GasState gs)
    {
        // This assumes the T_modes[0] is known, and we're only trying to determine T
        number pHeavy = gs.p;
        pHeavy -= gs.rho * gs.massf[mElectronIdx] * mR[mElectronIdx] * gs.T_modes[0];
        number denom = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            if (isp == mElectronIdx) continue;
            denom += gs.rho * gs.massf[isp] * mR[isp];
        }
        gs.T = pHeavy/denom;
    }

    @nogc
    number transRotEnergyPerSpecies(number T, int isp)
    {
        if (isp == mElectronIdx) return to!number(0.0);
        number h = mCpTR[isp] * (T - T_REF) + mDel_hf[isp];
        number e = h - mR[isp]*T;
        return e;
    }
    
    @nogc
    number transRotEnergyMixture(in GasState gs)
    {
        number e = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            if (isp == mElectronIdx) continue;
            e += gs.massf[isp] * transRotEnergyPerSpecies(gs.T, isp);
        }
        return e;
    }

    @nogc
    number vibElecCvPerSpecies(number Tve, int isp)
    {
        // electron as special case
        if (isp == mElectronIdx) return to!number((3./2.)*mR[isp]);

        // all other heavy species
        // Why Cp and not Cv?
        // We are computing an "internal" Cv here, the Cv_ve.
        // For internal energy storage Cv_int = Cp_int,
        // so we can make the calculation using Cp relations.
        return mCurves[isp].eval_Cp(Tve) - mCpTR[isp];
    }

    @nogc
    number vibElecCvMixture(in GasState gs, number Tve)
    {
        // Why pass in Tve, when we could dip into gs.T_modes[0]?
        // There are time when we'd like to use a value for Tve other
        // than T_modes[0]. For example, if we want to compute this
        // value when in thermal equilibrium, we can pass in Tve = gs.T.
        number Cv_ve = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            Cv_ve += gs.massf[isp] * vibElecCvPerSpecies(Tve, isp);
        }
        return Cv_ve;
    }

    @nogc
    number transRotCvPerSpecies(int isp)
    {
        // special case for electrons
        if (isp == mElectronIdx) return to!number(0.0);
        // all other heavy species
        return to!number(mCpTR[isp] - mR[isp]);
    }

    @nogc
    number transRotCvMixture(in GasState gs)
    {
        number Cv_tr = 0.0;
        foreach (isp; 0 .. mNSpecies) {
            Cv_tr += gs.massf[isp] * transRotCvPerSpecies(isp);
        }
        return Cv_tr;
    }

    version(complex_numbers) {
    // For the complex numbers version of the code we need
    // a Newton's method with a fixed number of iterations.
    // An explanation can be found in:
    //     Efficient Construction of Discrete Adjoint Operators on Unstructured Grids
    //     by Using Complex Variables, pg. 10, Nielsen et al., AIAA Journal, 2006.
    @nogc
    number vibElecTemperature(in GasState gs)
    {
        int MAX_ITERATIONS = 10;

        // Take the supplied T_modes[0] as the initial guess.
        number T_guess = gs.T_modes[0];
        number f_guess = vibElecEnergyMixture(gs, T_guess) - gs.u_modes[0];

        // Begin iterating.
        int count = 0;
        number Cv, dT;
        foreach (iter; 0 .. MAX_ITERATIONS) {
            Cv = vibElecCvMixture(gs, T_guess);
            dT = -f_guess/Cv;
            T_guess += dT;
            f_guess = vibElecEnergyMixture(gs, T_guess) - gs.u_modes[0];
            count++;
        }
        return T_guess;
    }
    } else {
    @nogc
    number vibElecTemperature(in GasState gs)
    {
        int MAX_ITERATIONS = 20;
        // We'll keep adjusting our temperature estimate
        // until it is less than TOL.
        double TOL = 1.0e-6;

        // Take the supplied T_modes[0] as the initial guess.
        number T_guess = gs.T_modes[0];
        number f_guess = vibElecEnergyMixture(gs, T_guess) - gs.u_modes[0];
        // Before iterating, check if the supplied guess is
        // good enough. Define good enough as 1/100th of a Joule.
        double E_TOL = 0.01;
        if (fabs(f_guess) < E_TOL) {
            // Given temperature is good enough.
            return gs.T_modes[0];
        }

        // Begin iterating.
        int count = 0;
        number Cv, dT;
        foreach (iter; 0 .. MAX_ITERATIONS) {
            Cv = vibElecCvMixture(gs, T_guess);
            dT = -f_guess/Cv;
            T_guess += dT;
            if (fabs(dT) < TOL) {
                break;
            }
            f_guess = vibElecEnergyMixture(gs, T_guess) - gs.u_modes[0];
            count++;
        }

        if (count == MAX_ITERATIONS) {
            string msg = "The 'vibTemperature' function failed to converge.\n";
            debug {
                msg ~= format("The final value for Tvib was: %12.6f\n", T_guess);
                msg ~= "The supplied GasState was:\n";
                msg ~= gs.toString() ~ "\n";
            }
            throw new GasModelException(msg);
        }

        return T_guess;
    }
    }
}

version(two_temperature_gas_test) {
    int main() {
        import util.msg_service;

        FloatingPointControl fpctrl;
        // Enable hardware exceptions for division by zero, overflow to infinity,
        // invalid operations, and uninitialized floating-point variables.
        // Copied from https://dlang.org/library/std/math/floating_point_control.html
        fpctrl.enableExceptions(FloatingPointControl.severeExceptions);

        auto L = init_lua_State();
        doLuaFile(L, "sample-data/five-species-air.lua");
        string[] speciesNames;
        getArrayOfStrings(L, "species", speciesNames);
        auto tm = new TwoTemperatureGasMixture(L, speciesNames);
        lua_close(L);
        auto gs = new GasState(5, 1);

        gs.p = 1.0e6;
        gs.T = 2000.0;
        gs.T_modes[0] = gs.T;
        gs.massf = [to!number(0.2), to!number(0.2), to!number(0.2), to!number(0.2), to!number(0.2)];
        tm.updateFromPT(gs);
        assert(approxEqualNumbers(to!number(11801825.6), gs.u + gs.u_modes[0], 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(to!number(1.2840117), gs.rho, 1.0e-6), failedUnitTest());

        return 0;
    }
}

    
