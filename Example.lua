local Abilities = {}

--[[

This module handles VFX, SFX, Hitboxes on the client.
All status effects & damage are then authenticated on the server before being completed.
I use BridgeNetV2 to handle my networking, and usually remain at a stable 15 KB/s in a full server.
I use a client > server > client > server model
		Input > Authentication & replication > Visuals + Syncing > Authentication + Status/Damage
		
I apologise if this code doesn't give an example of my range of skills,
the "ZonitoCurves" module is the only module required below that I have made myself.
It uses CFrame Math & Metatables to efficiently move parts in a Bezier curve path. I use it for VFX.

]]

local workspace = workspace -- Localization

local ReplicatedS = game:GetService("ReplicatedStorage")
local Items = ReplicatedS:WaitForChild("ReplicatedItems")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Run = game:GetService("RunService")
local Tween = game:GetService("TweenService")
local VFX = Items.VFX
local Modules = Items.Modules
local camera = workspace.CurrentCamera

local ZC = require(Modules.Client.ZonitoCurves) -- Module I made for implementing bezier curves more efficiently
local Bridge = require(Modules.Shared.BridgeNet2) -- Networking module
local Cache = require(Modules.Shared.PartCache) -- Reducing part lag
local Boat = require(Modules.Client.BoatTween) -- More effective TweenService ( Tweening beams, trails, etc... )
local CamShaker = require(Modules.Client.CameraShaker) -- Impact cameraShake

local Client = Bridge.ClientBridge("Replication") -- Client > Server > Client model
-- I return to the server for damage & authentication

local Ignore = workspace.Ignore -- Ignore parts in this folder during hitboxes / raycasts / spatial queries

--// Functions

local function EmitAll(Attachment) -- Emit all particles in an instance using built-in Attributes.
	
	for _,v in Attachment:GetChildren() do

		if v:IsA("ParticleEmitter") then
			
			task.delay(v:GetAttribute("EmitDelay"),function()
				
				v:Emit(v:GetAttribute("EmitCount"))
				
			end)
			
		end
		
	end
	
end


local function removeTags(str) -- Handles richText in the Type() function
	str = str:gsub("<br%s*/>", "\n")
	return (str:gsub("<[^<>]->", ""))
end

local function Type(txt,newtext,t) -- Used for ability names
	task.spawn(function()
		txt.MaxVisibleGraphemes=0
		txt.Text=newtext
		local displayText = removeTags(txt.Text)
		local index = 0
		for first, last in utf8.graphemes(displayText) do 
			local grapheme = displayText:sub(first, last) 
			index += 1
			if grapheme ~= " " then
				txt.MaxVisibleGraphemes = index
				task.wait(t)
			end
		end
	end)
end

local function ToggleAll(Attachment,value) -- Toggle all particles inside an attachment(or part) to true / false
	
	for _,v in Attachment:GetDescendants() do

		if v:IsA("ParticleEmitter") then
			v.Enabled = value
		end
	end
	
end



local function PoisonHit(Projectile) -- Hit function
	
	local Hit = VFX.Poison.Hit:Clone()
	Hit.Position = Projectile.Position
	Hit.Parent=Ignore
	ToggleAll(Projectile.main,false)
	EmitAll(Hit.Attachment)
	task.delay(4,function() Hit:Destroy() Projectile:Destroy() end)
	
end

--// Abilities
function Abilities.perfectblocked(Result) -- Combat functions.

	local Position = Result[2][2]

	local blockedVFX = VFX.PerfectBlocked:Clone()

	blockedVFX.Position = Position

	EmitAll(blockedVFX.Attachment)

	task.delay(2.1,function()

		blockedVFX:Destroy()

	end)

end
function Abilities.blocked(Result)
	
	local Position = Result[2][2]
	
	local blockedVFX = VFX.Blocked:Clone()
	
	blockedVFX.Position = Position
	
	EmitAll(blockedVFX.Attachment)
	
	task.delay(2.1,function()
		
		blockedVFX:Destroy()
		
	end)
	
end

-- Ice

function Abilities.coldcut(Result)
	
	local Player = Result[1] -- Result is a table with all Info about the player who fired the remote, aswell as additional info the server inserts into the table during authentication
	local RootPart = Result[2][3]

	local Params = RaycastParams.new()
	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude

	local cframe = RootPart.CFrame * CFrame.new(Vector3.new(0,0,-5))
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(30,244,255)">Ice magic: </font></b><i><font color="rgb(170, 255, 255)">Cold cut!</font></i>',.02)

	task.delay(2,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	
	local Cold = VFX.Ice.ColdCut:Clone()
	
	Cold.CFrame = cframe
	Cold.Parent = Ignore
	
	EmitAll(Cold.Slice)

	local Hitbox = workspace:Raycast(RootPart.Position,RootPart.CFrame.LookVector*7,Params)
		
	if Hitbox then

		if Hitbox.Instance.Parent:FindFirstChild("Humanoid") then
					
			Hitbox.Instance.Parent.HumanoidRootPart.Anchored = true
			Cold.CFrame = Hitbox.Instance.Parent.Torso.CFrame
				
			if LocalPlayer == Player then
				
				Client:Fire({"Damage",Hitbox.Instance.Parent.Humanoid,15,"Frozen",RootPart.Parent})
					
			end
					
			task.delay(3.8,function()
						
				EmitAll(Cold.Explosion)
				Hitbox.Instance.Parent.HumanoidRootPart.Anchored = false
						
				if LocalPlayer == Player then

					Client:Fire({"Damage",Hitbox.Instance.Parent.Humanoid,20,"Frozen",RootPart.Parent})

				end
						
				task.wait(5)
						
				Cold:Destroy()
						
			end)

		end
				
	end

end

function Abilities.icywall(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	
	local Params = OverlapParams.new()
	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude
	
	local Params2 = RaycastParams.new()
	Params2.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params2.FilterType = Enum.RaycastFilterType.Exclude
	
	local cframe = RootPart.CFrame * CFrame.new(Vector3.new(0,0,-5))
	local ray = workspace:Raycast(cframe.Position,Vector3.new(0,-100,0),Params2)
	if not ray then return end -- There is no space infront of the player > don't spawn any VFX
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(30,244,255)">Ice magic: </font></b><i><font color="rgb(170, 255, 255)">Icy wall!</font></i>',.04)

	task.delay(2,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	
	local Wall = Items.VFX.Ice.Icewall:Clone()
	

	Wall.CFrame = cframe

	Wall.Parent = workspace
	
	for i = 0,10,1 do -- Individually activate VFX in the IceWall. I do this to create a sort of Loading effect
		
		for _,v in Wall:GetChildren() do
			
			if v.Name == tostring(i) then
				
				ToggleAll(v,true)
				
			end
			
		end
		
		task.wait(.05)
		
	end
	
	local con;
	local pastTick = 0
	con = Run.Heartbeat:Connect(function()
		
		if tick()-pastTick>.5 then
			
			local hit = {}
			
			local hb = workspace:GetPartsInPart(Wall,Params)
			
			if #hb~=0 then
				
				for _, v in hb do
					
					if not table.find(hit,v.Parent) and v.Parent:FindFirstChild("Humanoid") then
						
						table.insert(hit,v.Parent)
						Client:Fire({"Damage",v.Parent.Humanoid,0,"Frozen",RootPart.Parent}) -- Dealing 0 damage, but applying the Frozen status effect
						
					end
					
				end
				
			end
			
		end
		
	end)	

	task.delay(5,function()
		
		ToggleAll(Wall,false)
		con:Disconnect()
		task.wait(2.95)
		Wall:Destroy()
		
		
	end)
	
	
end

function Abilities.belowzero(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	
	local rParams = RaycastParams.new()

	rParams.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	rParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local Params = OverlapParams.new()

	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude

	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(30,244,255)">Ice magic: </font></b><i><font color="rgb(170, 255, 255)">Below zero!</font></i>',.02)

	task.delay(2,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	
	local floor = workspace:Raycast(RootPart.Position + Vector3.new(0,2,0),Vector3.new(0,-100,0),rParams)
	
	if floor then
		
		local floorPosition = floor.Position
		
		local iceVFX = VFX.bzero:Clone()
		
		iceVFX.Position = RootPart.Position
		iceVFX.Parent = Ignore
		
		task.delay(3,function() iceVFX:Destroy() end)
		
		EmitAll(iceVFX.Attachment)
		
		local hitbox = workspace:GetPartsInPart(iceVFX,Params)
		
		if #hitbox ~= 0 and LocalPlayer == Player then
			
			local hasbeenHit = {} -- Stopping hit characters from being hit more than once
			
			for _, v in hitbox do
				
				if v.Parent:FindFirstChild("Humanoid") and not table.find(hasbeenHit, v.Parent) then
					
					table.insert(hasbeenHit, v.Parent)
					
					Client:Fire({"Damage",v.Parent.Humanoid,25,"Frozen",RootPart.Parent}) -- Damaging hit characters and applying the Frozen status effect
					
				end
				
			end
			
		end
		
	end
	
	
end

function Abilities.dualicicles(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	local Params = OverlapParams.new()

	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude

	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(30,244,255)">Ice magic: </font></b><i><font color="rgb(170, 255, 255)">Dual icicles!</font></i>',.02)

	task.delay(2,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	
	local function IceHit(Projectile)
		
		
		Tween:Create(Projectile,TweenInfo.new(.6),{Size = Vector3.zero,Transparency = 1}):Play()
		local hit = workspace:GetPartBoundsInRadius(Projectile.Position,2.5,Params)
		EmitAll(Projectile.Attachment)
		if #hit ~= 0 then
			local hits = {}
			for _,v in hit do

				if v.Parent:FindFirstChild("Humanoid") and not table.find(hits,v.Parent) then

					table.insert(hits,v.Parent)
					print("hit", v.Name)
					Client:Fire({"Damage",v.Parent.Humanoid,10,"Frozen",RootPart.Parent})

				end

			end

		end
		task.delay(.25,function()
			
			Projectile.ParticleEmitter.Enabled = false
			
			task.wait(1.5)
			Projectile:Destroy()
			
		end)

	end
	

	local p = RaycastParams.new()
	p.FilterDescendantsInstances = {workspace.Map}
	p.FilterType = Enum.RaycastFilterType.Include
	
	local r = workspace:Raycast(Result[2][2]+Vector3.new(0,3,0),Vector3.new(0,-100,0),p)
	
	if r then
		
		local Floor = VFX.Ice.IceFloor:Clone()
		Floor.Position = r.Position
		Floor.Parent = Ignore
		task.delay(1.5,function()
			
			ToggleAll(Floor.Middle,false)
			Floor.a.Enabled = false
			Floor.b.Enabled = false
			
			task.wait(2)
			
			Floor:Destroy()
			
		end)

	end	
	
	
	for i = 1,2,1 do
		task.spawn(function()
			local IceShard = VFX.Ice["Ice Blast"]:Clone()


			IceShard.Position = Result[2][2] + Result[2][4][i][1]
			
			IceShard.Parent = Ignore
			
			IceShard.Spawn:Play()
			Tween:Create(IceShard,TweenInfo.new(.45),{Size = Vector3.new(0.775,0.775,3)}):Play()
			IceShard.CFrame = CFrame.lookAt(IceShard.Position,Result[2][2])
			task.wait(.44)

			ZC.CubicCurve2( -- Simple cubier bezier curve (3 keypoints)
				
				IceShard,
				IceShard.Position,
				Result[2][2], -- End position in the curve, sent through using BridgeNetV2
				0.05, -- Speed / intervals in the curve
				Vector3.new(math.random(-5,5),0,math.random(-5,5)),
				Vector3.new(math.random(-5,5),0,math.random(-5,5)),
				Vector3.new(math.random(-5,5),0,math.random(-5,5)),
				true,
				IceHit
				
			)
		end)
	end
	
end

-- Poison

function Abilities.poisonbreath(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	local Head = RootPart.Parent:FindFirstChild("Head")
	if not Head then return end -- Player is not alive, return end
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(170, 0, 255)">Poison magic: </font></b><i><font color="rgb(170, 85, 255)">Poison Breath!</font></i>',.01)

	
	task.delay(4,function()
		
		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)	
	
	task.wait(.1)
	
	local Breath = VFX.Poison.Breath:Clone()
	Breath.CFrame = Head.CFrame * CFrame.new(Vector3.new(0,0,-1))
	Breath.Parent = Ignore
	local Con;
	local Debounce = tick()-1 -- Time imbetween tick dmg
	local op = OverlapParams.new()
	op.FilterDescendantsInstances = {Ignore,RootPart.Parent}
	op.FilterType = Enum.RaycastFilterType.Exclude
	local hitbox = script.hitbox:Clone()
	hitbox.CFrame = (Head.CFrame * CFrame.new(Vector3.new(0,0,-8))) * CFrame.Angles(0,math.rad(180),0) -- Moving the hitbox into the same position + rotation as the vfx
	hitbox.Parent = Ignore
	if LocalPlayer == Player then
		Con = Run.Heartbeat:Connect(function()
			if tick()-Debounce < 1 or LocalPlayer ~= Player then return end
			Debounce = tick()
			local hit = {}
			local Hitbox = workspace:GetPartsInPart(hitbox,op)
			if #Hitbox ~= 0 then
				
				for _,v in Hitbox do
					
					if v.Parent:FindFirstChild("Humanoid") and not table.find(hit,v.Parent) then
						
						table.insert(hit,v.Parent)
						Client:Fire({"Damage",v.Parent.Humanoid,10,"Poison",RootPart.Parent})
						
					end
					
				end
				
			end
		
		end)
	end
	task.wait(3)
	ToggleAll(Breath.Main,false)
	hitbox:Destroy()
	task.delay(2.5,function()
		
		Breath:Destroy()
		
	end)
	if LocalPlayer == Player then
		Con:Disconnect()
	end
end

function Abilities.poisoncannon(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	
	local Params = RaycastParams.new()
	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude

	local pos1 = ReplicatedS.ReplicatedItems.MouseInfo:FindFirstChild(Player.Name).Value.Position
	local ray1 = workspace:Raycast(pos1+Vector3.new(0,3,0),Vector3.new(0,-100,0),Params)
	if not ray1 then return end
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(170, 0, 255)">Poison magic: </font></b><i><font color="rgb(170, 85, 255)">Poison Cannon!</font></i>',.05)

	
	task.delay(4,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	

	
	local Poisonblast = VFX.Poison.Blast:Clone()

	Poisonblast.Position = RootPart.Position + Vector3.new(0,20,0)
	Poisonblast.Parent = Ignore
	EmitAll(Poisonblast.Charging)
	local connection;
	
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	
	connection = Run.Heartbeat:Connect(function()
		
		Poisonblast.Position = RootPart.Position + Vector3.new(0,20,0)
		
	end)
	task.wait(2)
	connection:Disconnect()
	local pos = ReplicatedS.ReplicatedItems.MouseInfo:FindFirstChild(Player.Name).Value.Position
	
	Poisonblast.A.Enabled = true
	Poisonblast.B.Enabled = true
	
	local Start = tick() -- Time keeping
	
	connection = Run.Heartbeat:Connect(function(deltaTime)
		
		if tick()-Start >= 5 then connection:Disconnect() Poisonblast:Destroy() end

		Poisonblast.CFrame = CFrame.lookAt(Poisonblast.Position,pos)
		Poisonblast.CFrame = (Poisonblast.CFrame + Poisonblast.CFrame.LookVector * deltaTime * 150) -- deltaTime to ensure equal speed across platforms
		
		local rayHitbox = workspace:Raycast(Poisonblast.Position,Poisonblast.CFrame.LookVector*1,rayParams)
		
		if rayHitbox then -- Poison hit something
			
			connection:Disconnect() -- Stop the connection (stopping movement)
			
			ToggleAll(Poisonblast.Main,false)
			EmitAll(Poisonblast.Explode)

			local hitppl = {}
			local AttackHitbox = workspace:GetPartBoundsInRadius(Poisonblast.Position,6,overlapParams)
			if #AttackHitbox ~= 0 then
				for _,v in AttackHitbox do

					if v.Parent:FindFirstChild("Humanoid") and v.Parent:FindFirstChild("Attributes") and not table.find(hitppl,v.Parent) then

						table.insert(hitppl,v.Parent)

						if LocalPlayer == Player then

							Client:Fire({"Damage",v.Parent.Humanoid,35,"Poison",RootPart.Parent}) -- Firing damage remote. I perform checks on the server to maintain security. The "Poison" applies a Poison status effect to the hit character.

						end

					end

				end
			end
			
		end
		
		local Hitbox = workspace:GetPartsInPart(Poisonblast,overlapParams) -- Spatial query hitbox
		
		if #Hitbox ~= 0 then
			
			connection:Disconnect()
			ToggleAll(Poisonblast.Main,false) -- Toggling off the constant effects & emitting the Impact particles
			EmitAll(Poisonblast.Explode)
			
			local hitppl = {}
			local AttackHitbox = workspace:GetPartBoundsInRadius(Poisonblast.Position,6,overlapParams)
			if #AttackHitbox ~= 0 then
				for _,v in AttackHitbox do
					
					if v.Parent:FindFirstChild("Humanoid") and v.Parent:FindFirstChild("Attributes") and not table.find(hitppl,v.Parent) then
						
						table.insert(hitppl,v.Parent)
						
						if LocalPlayer == Player then
							
							Client:Fire({"Damage",v.Parent.Humanoid,35,"Poison",RootPart.Parent}) -- Firing damage remote. I perform checks on the server to maintain security. The "Poison" applies a Poison status effect to the hit character.
							
						end
						
					end
					
				end
			end
		end
		
		
	end)
	
	
end

function Abilities.poisonbarrage(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	local Params = RaycastParams.new()
	
	Params.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	Params.FilterType = Enum.RaycastFilterType.Exclude
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(170, 0, 255)">Poison magic: </font></b><i><font color="rgb(170, 85, 255)">Poisoned pellets!</font></i>',.03)
	
	task.delay(2,function()
		
		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()
		
	end)
	
	for i = 1,7,1 do
	
		local Poisonprojectile = VFX.Poison.Projectile:Clone()
		Poisonprojectile.Position = RootPart.Position + Result[2][4][i][1]
		
			task.spawn(function()
				
				local Purple = Poisonprojectile
				Purple.Trail.Enabled = false
				Purple.Parent = Ignore
				Purple.Spawn:Play()
				local overlapParams = OverlapParams.new()
				overlapParams.FilterDescendantsInstances = {RootPart.Parent,Ignore}
				overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			
			local overlapParams2 = RaycastParams.new()
			overlapParams2.FilterDescendantsInstances = {RootPart.Parent,Ignore}
			overlapParams2.FilterType = Enum.RaycastFilterType.Exclude
			
				local con;
				con = Run.Heartbeat:Connect(function()
					
					Purple.Position = RootPart.Position + Result[2][4][i][1]
					
				end)
				task.wait(1)
				local position = ReplicatedS.ReplicatedItems.MouseInfo:FindFirstChild(Player.Name).Value.Position

				con:Disconnect()
				Purple.Trail.Enabled = true
				Purple.main.Dark.LockedToPart = false
				
				local Start = tick()
				
				con = Run.Heartbeat:Connect(function(deltaTime)
					if tick()-Start >= 4 then con:Disconnect() Purple:Destroy() end

					Purple.CFrame = CFrame.lookAt(Purple.Position,position)
					Purple.CFrame = (Purple.CFrame + Purple.CFrame.LookVector * deltaTime * 100)
				
					local rayHitbox = workspace:Raycast(Purple.Position, Purple.CFrame.LookVector*1, overlapParams2)

					if rayHitbox then
					local hitppl = {}
					local AttackHitbox = workspace:GetPartBoundsInRadius(Purple.Position,3,overlapParams)
					if #AttackHitbox ~= 0 then
						for _,v in AttackHitbox do

							if v.Parent:FindFirstChild("Humanoid") and v.Parent:FindFirstChild("Attributes") and not table.find(hitppl,v.Parent) then

								table.insert(hitppl,v.Parent)

								if not v.Parent:FindFirstChild("DamageHighlight") then

									local highlight = Instance.new("Highlight")
									highlight.Name = "DamageHighlight"
									highlight.OutlineTransparency=1
									highlight.FillTransparency=1
									highlight.FillColor = Color3.new(0.666667, 0.333333, 1)
									highlight.Parent = v.Parent
									Tween:Create(highlight,TweenInfo.new(.2,Enum.EasingStyle.Sine,Enum.EasingDirection.In,0,true),{FillTransparency = .15}):Play()
									task.delay(2.1,function()

										highlight:Destroy()

									end)
								end

								if LocalPlayer == Player then
									Client:Fire({"Damage",v.Parent.Humanoid,5,"Poison",RootPart.Parent})
								end

							end

						end
					end

					con:Disconnect()
					ToggleAll(Purple.main,false)
					EmitAll(Purple.ex)
					task.wait(3)
					Purple:Destroy()



				end
				
					local hitbox = workspace:GetPartsInPart(Purple,overlapParams)
					if #hitbox~=0 then
						
						--[[if (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()) and LocalPlayer:DistanceFromCharacter(Purple.Position)<80 then
							--Purple.Impact:Play()
							--camShake:Shake(camShake.Presets.Bump)
						end]]
						
					local hitppl = {}
					local AttackHitbox = workspace:GetPartBoundsInRadius(Purple.Position,3,overlapParams)
					if #AttackHitbox ~= 0 then
						for _,v in AttackHitbox do

							if v.Parent:FindFirstChild("Humanoid") and v.Parent:FindFirstChild("Attributes") and not table.find(hitppl,v.Parent) then
								
								table.insert(hitppl,v.Parent)
								
								if not v.Parent:FindFirstChild("DamageHighlight") then
								
									local highlight = Instance.new("Highlight")
									highlight.Name = "DamageHighlight"
									highlight.OutlineTransparency=1
									highlight.FillTransparency=1
									highlight.FillColor = Color3.new(0.666667, 0.333333, 1)
									highlight.Parent = v.Parent
									Tween:Create(highlight,TweenInfo.new(.2,Enum.EasingStyle.Sine,Enum.EasingDirection.In,0,true),{FillTransparency = .15}):Play()
									task.delay(2.1,function()
										
										highlight:Destroy()
										
									end)
								end
								
								if LocalPlayer == Player then
									Client:Fire({"Damage",v.Parent.Humanoid,5,"Poison",RootPart.Parent}) -- Firing damage remote. I perform checks on the server to maintain security. The "Poison" applies a Poison status effect to the hit character.
								end
								
							end

						end
					end
					
					con:Disconnect()
					ToggleAll(Purple.main,false)
					EmitAll(Purple.ex)
					task.wait(3)
					Purple:Destroy()
						
	

					end
					
				end)
				
			end)

		task.wait(.1)
	end
end

function Abilities.poisonaura(Result)
	
	local Player = Result[1]
	local RootPart = Result[2][3]
	
	local gui = script.TextLabel:Clone()
	gui.Parent = RootPart.Parent.Head.BillboardGui.Frame
	Type(gui,'<b><font color="rgb(170, 0, 255)">Poison magic: </font></b><i><font color="rgb(170, 85, 255)">Poison Aura!</font></i>',.03)
	task.wait(.5)
	task.delay(1.3,function()

		Tween:Create(gui,TweenInfo.new(1),{TextTransparency = 1}):Play()
		task.wait(1.01)
		gui:Destroy()

	end)
	for _,v in pairs(RootPart.Parent:GetChildren()) do
		
		if v:IsA("BasePart") and v.Name ~= "Head" and v.Name ~= "HumanoidRootPart" then
			
			task.spawn(function()
				local AuraParticle = VFX.Poison.Aura:Clone()
				AuraParticle.Parent = v
				
				task.delay(3,function()
					
					AuraParticle.Enabled = false
					task.wait(2)
					AuraParticle:Destroy()
					
				end)
				
			end)
			
		end
		
	end
	
	local con;
	local overlap = OverlapParams.new()
	local hitppl = {}
	overlap.FilterDescendantsInstances = {RootPart.Parent,Ignore}
	con = Run.Heartbeat:Connect(function()
		
		local Hitbox = workspace:GetPartBoundsInBox(RootPart.CFrame,Vector3.new(6,6,6),overlap)
		
		if #Hitbox ~= 0 then
			
			for _,v in Hitbox do
				
				if v.Parent:FindFirstChild("Humanoid") and not table.find(hitppl,v.Parent) then
					
					table.insert(hitppl,v.Parent)
					Client:Fire({"Damage",v.Parent.Humanoid,0,"Poison"}) -- Firing damage remote. I perform checks on the server to maintain security. The "Poison" applies a Poison status effect to the hit character.
					
				end
				
			end
			
		end
		
	end)
	task.wait(3.33)
	con:Disconnect()
	
end

return Abilities
