--Author: Samuel Dillon and Rowan Gollan
--Date: 9th of April
spFile = "C2H2-C2H4-model-gas.lua"
reacFile = "C2H2-C2H4-model-reactions-eilmer.lua"
outFile = "acetylene-ignition.dat"

tFinal = 3000e-6 -- s
pAtm = 101325
pInit = 0.6*101325 --Shock Mixture 25
Tlow = 1150.0 -- K
Thigh = 1750.0 -- K
dTemp = 100
molef = {C2H2=0.02, O2=0.025, Ar=0.955}

function max_slope(ts, ps)
   -- Look for max slope using central difference estimate of slope
   local tMax = ts[2]
   local maxSlope = (ps[3] - ps[1])/(ts[3] - ts[1])
   for i=3,#ts-1 do
      local slope = (ps[i+1] - ps[i-1])/(ts[i+1] - ts[i-1])
      if slope > maxSlope then
         maxSlope = slope
         tMax = ts[i]

      end
   end
   return tMax
end

function ignition_delay(T, gm, chemUpdate)
   -- As an ignition criterion, we are looking for the
   -- the maximum rate of change of pressure.
   -- We'll store pressure and time and then look for max slope.
   local Q = gm:createGasState()
   Q.p = pInit
   Q.T = T
   Q.massf = gm:molef2massf(molef)
   gm:updateThermoFromPT(Q)

   local t = 0.0
   local dt = 1.0e-8
   local dtSuggest = 1.0e-11
   local ts = {t}
   local ps = {pInit}
   while t <= tFinal do
      dtSuggest = chemUpdate:updateState(Q, dt, dtSuggest, gm)
      t = t + dt
      dt = dtSuggest
      gm:updateThermoFromRHOU(Q)
      ts[#ts+1] = t
      ps[#ps+1] = Q.p
   end
   return max_slope(ts, ps)
end

function main()
   local gm = GasModel:new{spFile}
   local chemUpdate = ChemistryUpdate:new{filename=reacFile, gasmodel=gm}

   local f = assert(io.open(outFile, 'w'))
   f:write('# 1:T(K)  2:t(s)\n')

   for T=Tlow,Thigh,dTemp do
      local tIg = ignition_delay(T, gm, chemUpdate)
      if tIg then
	 f:write(string.format("%20.12e %20.12e\n", T, tIg))
      else
	 print("No ignition at T= ", T)
      end
      print("T= ", T, " tIg= ", tIg)
   end
   f:close()

end

main()
