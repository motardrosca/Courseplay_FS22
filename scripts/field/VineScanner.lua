
--- This scanner is used to detect continues orchard fields.
--- Every line has to have the same direction.
---
--- TODO: Add an explicit check if the lines are part of a continues field.


---@class VineScanner
VineScanner = CpObject()
function VineScanner:init()
	self.startNode = nil
	self.lineEndNode = nil
	self.segments = {}
	self.leftSegments = {}
	self.rightSegments = {}
	self.debugChannel = CpDebug.DBG_COURSES
end

function VineScanner:setup()
	self.vineSystem = g_currentMission.vineSystem
end

function VineScanner:scan(node)
	--- Gets the closest vine node to start at.
	local startNode = self:getStartNodeFromRefNode(node)
	if startNode == nil then 
		return
	end
	DebugUtil.drawDebugNode(startNode,"startNode",nil,2.5)
	--- Gets all vine lines with the same direction.
	local lines = self:getLinesWithSameDirections(startNode)

	--- Separate this lines into columns relative to the start position into left and right side.
	local columnsLeft,columnsRight = self:separateIntoColumns(lines,startNode)
	--- Combines sections of the same lines.
	local newColumnsLeft,newColumnsRight = self:combineLines(columnsLeft,columnsRight,startNode)
	
	self:drawLines(newColumnsLeft)
	self:drawLines(newColumnsRight)
end

function VineScanner:generateCourse(columnsLeft,columnsRight)
	local inverted = true
	for i=#columnsRight,-1,1 do 

		inverted = not inverted
	end
	for i=1,#columnsLeft do 
		
		inverted = not inverted
	end
end

--- Are the directions equal ?
function VineScanner:equalDirection(dx,nx,dz,nz)
	return MathUtil.equalEpsilon(nx,-dx,0.01) and MathUtil.equalEpsilon(nz,-dz,0.01)
end

--- Gets all lines with the same direction as the start node.
function VineScanner:getLinesWithSameDirections(startNode)
	local lines = {}
	local placeable = self.vineSystem.nodes[startNode]
	local width = placeable.spec_vine.width
	local dirX,_,dirZ = localDirectionToWorld(startNode,0,0,1)
	for segment,data in pairs(placeable.spec_vine.vineSegments) do 
		local xa,za = segment.x1,segment.z1
		local xb,zb = segment.x2,segment.z2
		local dx, dz = MathUtil.vector2Normalize(xb - xa, zb - za)
		if self:equalDirection(dirX,-dx,dirZ,-dz) then
			local xc,zc = xa,za
			xa,za = xb,zb
			xb,zb = xc,zc
			dx,dz = -dx,-dz
		end
		if self:equalDirection(dirX,dx,dirZ,dz) then
			local ya = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,xa,0,za)
			local yb = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,xb,0,zb)
		
			local line = {
				x1 = xa,
				x2 = xb,
				y1 = ya,
				y2 = yb,
				z1 = za,
				z2 = zb,
				dx = dx,
				dz = dz
			}
			table.insert(lines,line)
			local diff,_,_ = worldToLocal(startNode,line.x1,0,line.z1)
			self:debug("Found line with diff %d.",diff)
		end
	end
	self:debug("Found %d lines with the same direction.",#lines)
	return lines
end

--- Separate this lines into left (startNode -> max left) and right(startNode + 1 -> max right) columns.
function VineScanner:separateIntoColumns(lines,startNode)
	local placeable = self.vineSystem.nodes[startNode]
	local width = placeable.spec_vine.width
	local dirX,_,dirZ = localDirectionToWorld(startNode,0,0,1)
	local columnsLeft = {}
	local columnsRight = {}

	--- Left columns 
	local ix = 1
	while true do
		local nx = (ix-1)*width
		local x,_,z = localToWorld(startNode,nx,0,0) 
		local foundVine = false
		for i, line in pairs(lines) do 
		--	if MathUtil.hasRectangleLineIntersection2D(x1, z1, dirX1, dirZ1, dirX2, dirZ2, x3, z3, dirX3, dirZ3)
			if MathUtil.getCircleLineIntersection(x, z, 0.1,  line.x1, line.z1, line.x2, line.z2) then
				if columnsLeft[ix] == nil then 
					columnsLeft[ix] = {}
				end
				table.insert(columnsLeft[ix],line)
				foundVine = true
				self:debug("Found line at column %d.",ix)
			end
		end
		if not foundVine then 
			break
		end
		ix = ix + 1
	end
	self:debug("Found %d columns to the left.",#columnsLeft)
	--- Right columns 
	ix = 1
	while true do 	
		local nx = ix*(-width)
		local x,_,z = localToWorld(startNode,nx,0,0) 	
		local foundVine = false
		for i, line in pairs(lines) do 
			if MathUtil.getCircleLineIntersection(x, z, 0.1,  line.x1, line.z1, line.x2, line.z2) then
				if columnsRight[ix] == nil then 
					columnsRight[ix] = {}
				end
				table.insert(columnsRight[ix],line)
				foundVine = true
				self:debug("Found line at column %d.",ix)
			end
		end
		if not foundVine then 
			break
		end
		ix = ix + 1
	end
	self:debug("Found %d columns to the right.",#columnsRight)
	return columnsLeft,columnsRight
end

--- The generated lines are not continues and are separated into sections. 
--- Combine this sections here.
--- TODO: Check if the lines are part of the field.
function VineScanner:combineLines(columnsLeft,columnsRight,startNode)
	local placeable = self.vineSystem.nodes[startNode]
	local width = placeable.spec_vine.width
	local dirX,_,dirZ = localDirectionToWorld(startNode,0,0,1)
	local function sort(l1,l2)
		local _,_,z1 = worldToLocal(startNode,l1.x2,0,l1.z2)
		local _,_,z2 = worldToLocal(startNode,l2.x2,0,l2.z2)
		return z1 < z2
	end
	local newColumnsLeft = {}
	for i,lines in pairs(columnsLeft) do 
		table.sort(lines,sort)
		newColumnsLeft[i] = {
			x1 = lines[1].x2,
			x2 = lines[#lines].x1,
			y1 = lines[1].y2,
			y2 = lines[#lines].y1,
			z1 = lines[1].z2,
			z2 = lines[#lines].z1
		}
	end
	local newColumnsRight = {}
	for i,lines in pairs(columnsRight) do 
		table.sort(lines,sort)
		newColumnsRight[i] = {
			x1 = lines[1].x2,
			x2 = lines[#lines].x1,
			y1 = lines[1].y2,
			y2 = lines[#lines].y1,
			z1 = lines[1].z2,
			z2 = lines[#lines].z1
		}
	end
	return newColumnsLeft,newColumnsRight
end

function VineScanner:drawLines(lines)
	for i,line in pairs(lines) do 
		local x1,x2,y1,y2,z1,z2 = line.x1,line.x2,line.y1,line.y2,line.z1,line.z2
		drawDebugLine(x1, y1 + 2,z1, 1, 0, 0, x2, y2 + 2, z2, 0, 1, 0)
	end
end


--- Searches for the closest vine node to the reference node, as a start point.
function VineScanner:getStartNodeFromRefNode(refNode)
	local closestNode = nil
	local closestDistance = math.huge
	for node,data in pairs(self.vineSystem.nodes) do 
		local d = calcDistanceFrom(node,refNode)
		if d < closestDistance then 
			closestNode = node 
			closestDistance = d
		end
	end
	return closestNode
end

function VineScanner:draw(node)
	self:scan(node)
end

function VineScanner:debug(str,...)
	CpUtil.debugFormat(self.debugChannel,"VineScanner: "..str, ...)
end

function VineScanner:debugSparse(...)
	if g_updateLoopIndex % 100 == 0 then
        self:debug(...)
    end
end

g_vineScanner = VineScanner()