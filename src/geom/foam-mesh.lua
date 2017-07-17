-- foam-mesh.lua
-- Lua helper definitions for the D program: foam-mesh
--
-- Authors: Rowan G., Ingo J., and Peter J.
-- Date: 2017-07-03

-- Global settings
turbulence_model = "none" -- Options are: "S-A" and "k-epsilon"
axisymmetric = true
dtheta = 0.2
dz = 0.2

faceMap = {
   north=0,
   east=1,
   south=2,
   west=3,
   top=4,
   bottom=5
}

function checkAllowedNames(myTable, allowedNames)
   local setOfNames = {}
   local namesOk = true
   for i,name in ipairs(allowedNames) do
      setOfNames[name] = true
   end
   for k,v in pairs(myTable) do
      if not setOfNames[k] then
	 print("Warning: Invalid name: ", k)
	 namesOk = false
      end
   end
   return namesOk
end

-- Allowed boundary label prefixes
bndryLabelPrefixes = {"w-", -- for walls
                      "i-", -- for inlets
		      "o-", -- for outlets
		      "s-", -- for symmetry
		      "p-", -- for patches
}

function checkBndryLabels(bndryList)
   for k,v in pairs(bndryList) do
      local labelOK = false
      for _,allowedPrefix in ipairs(bndryLabelPrefixes) do
	 pattern = string.gsub(allowedPrefix, "%-", "%%%-")
	 i, j = string.find(v, pattern)
	 if (i == 1) then
	    labelOK = true
	 end
      end
      -- If labelOK is still false at end, then this particular
      -- label was badly formed.
      if not labelOK then
	 print(string.format("The boundary label '%s' is not allowed.", v))
	 print("Allowed label names start with the following prefixes:")
	 for _,allowedPrefix in ipairs(bndryLabelPrefixes) do
	    print(allowedPrefix)
	 end
	 os.exit(1)
      end
   end
end
	      
-- Storage for global collection of boundary labels
globalBndryLabels = {}

-- Storage for FoamBlock objects
blks = {}

-- Class definition
FoamBlock = {}
function FoamBlock:new(o)
   o = o or {}
   local flag = checkAllowedNames(o, {"grid", "bndry_labels"})
   assert(flag, "Invalid name for item supplied to FoamBlock:new().")
   setmetatable(o, self)
   self.__index = self
   -- Make a record of this block for later use when writing out.
   o.id = #(blks)
   blks[#(blks)+1] = o
   if (o.grid == nil) then
      error("A 'grid' object must be supplied to FoamBlock:new().")
   end
   if (o.grid:get_dimensions() ~= 2) then
      errMsg = "The 'grid' object supplied to FoamBlock:new() must be a 2D grid.\n"
      error(errMsg)
   end
   if (o.grid:get_type() ~= "structured_grid") then
      errMsg = "The 'grid' object supplied to FoamBlock:new() must be a structured grid.\n"
      error(errMsg)
   end
   -- Construct a slab or wedge, as appropriate
   if (axisymmetric) then
      newGrid = o.grid:makeWedgeGrid{dtheta=dtheta, symmetric=true}
   else
      newGrid = o.grid:makeSlabGrid{dz=dz}
   end
   -- and then convert to unstructured
   o.ugrid = UnstructuredGrid:new{sgrid=newGrid}

   -- Now look over the boundary labels.
   checkBndryLabels(o.bndry_labels)
   -- Add "top", "bottom" labels
   if (axisymmetric) then
      o.bndry_labels.top = "wedge-front"
      o.bndry_labels.bottom = "wedge-rear"
   else
      o.bndry_labels.top = "empty"
      o.bndry_labels.bottom = "empty"
   end
   -- Populate the unset bndry_labels with the internal defaults
   for _,face in ipairs({"north", "east", "south", "west"}) do
      o.bndry_labels[face] = o.bndry_labels[face] or "unassigned"
   end
   -- Add the unique boundary labels to the global collection
   for _,bl in pairs(o.bndry_labels) do
      globalBndryLabels[bl] = true
   end
   return o
end

function amendTags(grid, blks)
   nBoundaries = grid:get_nboundaries()
   for iBndry=0,nBoundaries-1 do
      origTag = grid:get_boundaryset_tag(iBndry)
      newTag = string.format("%s-%04d", origTag, math.floor(iBndry/6))
      grid:set_boundaryset_tag(iBndry, newTag)
   end
end

function runCollapseEdges()
   -- A 2-step process:
   -- 1. Place the collapseDict file in place.
   dgdDir = os.getenv("DGD")
   collapseDictFile = string.format("%s/share/foamMesh-templates/collapseDict", dgdDir)
   retVal = os.execute("test -d system")
   if retVal ~= 0 then
      os.execute("mkdir system")
   end
   cmd = string.format("cp %s system/", collapseDictFile)
   os.execute(cmd)
   -- 2. Run the collapeEdges command   
   cmd = "collapseEdges -overwrite"
   os.execute(cmd)
end

function writePatchDict(grid, blks)
   retVal = os.execute("test -d system")
   if retVal ~= 0 then
      os.execute("mkdir system")
   end
   fname = "system/createPatchDict"

   f = assert(io.open(fname, 'w'))
   f:write(string.format("// Auto-generated by foamMesh on %s\n", os.date("%d-%b-%Y at %X")))
   f:write("\n")
   f:write("FoamFile\n")
   f:write("{\n")
   f:write("    version     2.0;\n")
   f:write("    format      ascii;\n")
   f:write("    class       dictionary;\n")
   f:write("    object      createPatchDict;\n")
   f:write("}\n")
   f:write("\n")
   f:write("pointSync false;\n")
   f:write("\n")
   f:write("patches\n")
   f:write("(\n")
   for label,_ in pairs(globalBndryLabels) do
      bType = "patch"
      if label == "empty" then
	 bType = "empty"
      end
      if label == "wedge-front" or label == "wedge-rear" then
	 bType = "wedge"
      end
      if label == "unassigned" then
	 bType = "unassigned"
      end
      labelPrefix = string.sub(label, 1, 2)
      if labelPrefix == "w-" then
	 bType = "wall"
      end
      if labelPrefix == "i-" then
	 -- [TODO:IJ] Please check.
	 bType = "patch"
      end
      if labelPrefix == "o-" then
	 -- [TODO:IJ] Please check.
	 bType = "patch"
      end
      if labelPrefix == "s-" then
	 bType = "symmetry"
      end
      if labelPrefix == "p-" then
	 bType = "patch"
      end
      f:write("    {\n")
      f:write(string.format("        name %s;\n", label))
      f:write("        patchInfo\n")
      f:write("        {\n")
      f:write(string.format("            type  %s;\n", bType))
      f:write("        }\n")
      f:write("        constructFrom patches;\n")
      f:write("        patches (\n")
      for ib, blk in ipairs(blks) do
	 for bndry, bndryLabel in pairs(blk.bndry_labels) do
	    if (bndryLabel == label) then
	       iBndry = 6*(ib-1) + faceMap[bndry]
	       tag = grid:get_boundaryset_tag(iBndry)
	       f:write(string.format("            %s \n", tag))
	    end
	 end
      end
      f:write("        );\n")
      f:write("    }\n")
   end
   f:write(");\n")
   f:close()
end

function writeNoughtDir()
   -- Check if 0 exists.
   retVal = os.execute("test -d 0")
   if retVal == 0 then
      -- 0/ already exists.
      -- We don't want to override this, so we'll place the template
      -- files in 0_temp
      dirName = "0_temp"
   else
      -- 0/ does not exist
      -- So we'll create it and place template files in there.
      dirName = "0"
   end
   retVal = os.execute("test -d "..dirName)
   if retVal ~= 0 then
      os.execute("mkdir "..dirName)
   end
   -- Now copy required template files in place.
   foamTmpltDir = os.getenv("DGD").."/share/foamMesh-templates"
   filesToCopy = {"p", "U"}
   if turbulence_model == "S-A" then
      filesToCopy[#filesToCopy+1] = "nut"
      filesToCopy[#filesToCopy+1] = "nuTilda"
   end
   if turbulence_model == "k-epsilon" then
      filesToCopy[#filesToCopy+1] = "k"
      filesToCopy[#filesToCopy+1] = "epsilon"
   end
   for _,f in ipairs(filesToCopy) do
      cmd = string.format("cp %s/%s %s/", foamTmpltDir, f, dirName)
      os.execute(cmd)
   end
end

function writeMesh()
   if #blks > 1 then
      print("foamMesh only works on the first block presently.")
   end
   if (vrbLvl >= 1) then
      print("Writing out grid into 'polyMesh/'")
   end
   blks[1].ugrid:writeOpenFoamPolyMesh("constant")
end

function runRenumberMesh()
   os.execute("renumberMesh -overwrite")
end

function main(verbosityLevel)
   vrbLvl = verbosityLevel
   amendTags(blks[1].ugrid)
   writeMesh()
   if (axisymmetric) then
      runCollapseEdges()
   end
   writePatchDict(blks[1].ugrid, blks)
   writeNoughtDir()
   runRenumberMesh()
end   

