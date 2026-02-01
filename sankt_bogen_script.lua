local replicatedStorage = game:GetService("ReplicatedStorage")
local debrisService = game:GetService("Debris")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local chat = game:GetService("Chat")

local SanktBogenRemote = replicatedStorage.Remotes.Characters["Yhwach (TYBW)"].SanktBogen.SanktBogen
local SanktBogenCS = replicatedStorage.Remotes.Characters["Yhwach (TYBW)"].SanktBogen.SanktBogenCS

-- My movementcontroller module, used to lock player movement without causing bugs by scripts interfering with each other.

local MovementController = require(game.ReplicatedStorage.MovementController)

-- Configurations for just a better structure

local CONFIG = {
	STUN_DURATION = 1.5,
	DAMAGE_PER_ARROW = 15,
	ARROW_DISTANCE = 30,
	VFX_CLEANUP_TIME = 5,
	MAX_ARROWS = 4,
	FOURTH_ARROW_STUN = 4.5,
	FOURTH_ARROW_HITBOX = Vector3.new(60, 60, 60)
}

-- Asset list

local ANIMATION = game.ReplicatedFirst.Preloader.Animations.Characters["Yhwach (TYBW)"].SanktBogen.SanktBogenAnim
local SFX_AURA = replicatedStorage.SFX.Characters.Yhwach.Sanktbogen.Aura
local SFX_ARROW_SPAWN = replicatedStorage.SFX.Characters.Yhwach.Sanktbogen.ArrowSpawn
local SFX_ARROW_EXPLODE = replicatedStorage.SFX.Characters.Yhwach.Sanktbogen.ArrowExplode
local SFX_FOURTH_ARROW = replicatedStorage.SFX.Characters.Yhwach.Sanktbogen.FourthArrowImpact
local BOW = game.ReplicatedStorage.Meshes.Characters["Yhwach (TYBW)"].SanktBogen.default:Clone()
local sukuna_big_bang = game.ReplicatedStorage.VFX.Characters.Yhwach.SanktBogen["sukuna big bang"]:Clone()
local shadowportal = game.ReplicatedStorage.VFX.Characters.Yhwach.SanktBogen["Shadow Portal"].blablabla:Clone()

local activeBows = {}
local playerArrowCounts = {}

-- Self explanatory

local function playAnimation(humanoid, animationObject)
	if not humanoid or not animationObject or not animationObject:IsA("Animation") then 
		return nil 
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local track = animator:LoadAnimation(animationObject)
	track:Play()
	return track
end

-- Self explanatory

local function playSFX(position, soundObject, duration)
	if not soundObject then return end

	duration = duration or 3

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local sound = soundObject:Clone()
	sound.Parent = part
	sound:Play()

	debrisService:AddItem(part, duration)
end

-- Self explanatory stun system with ragdoll too

local function applyStun(enemyChar, enemyHumanoid, duration)
	if not enemyChar or not enemyHumanoid or enemyHumanoid.Health <= 0 then
		return
	end

	if enemyChar.IFrames.Value == true then
		return
	end

	enemyChar:SetAttribute("Stunned", true)

	local targetRagdollValue = enemyChar:FindFirstChild("IsRagdoll")
	if targetRagdollValue then
		targetRagdollValue.Value = true
	end

	MovementController:Lock(enemyHumanoid, "SanktBogenStun")

	task.delay(duration, function()
		if enemyHumanoid and enemyHumanoid.Parent and enemyHumanoid.Health > 0 then
			if enemyChar then
				enemyChar:SetAttribute("Stunned", false)
				MovementController:Unlock(enemyHumanoid, "SanktBogenStun")

				if targetRagdollValue and targetRagdollValue.Parent then
					targetRagdollValue.Value = false
				end
			end
		end
	end)

	task.delay(duration + 0.5, function()
		if enemyChar and enemyChar:GetAttribute("Stunned") then
			enemyChar:SetAttribute("Stunned", false)
			MovementController:Unlock(enemyHumanoid, "SanktBogenStun")

			if targetRagdollValue and targetRagdollValue.Parent then
				targetRagdollValue.Value = false
			end
		end
	end)

	task.delay(duration + 1, function()
		if enemyChar and enemyChar:GetAttribute("Stunned") then
			enemyChar:SetAttribute("Stunned", false)
			MovementController:Unlock(enemyHumanoid, "SanktBogenStun")

			if targetRagdollValue and targetRagdollValue.Parent then
				targetRagdollValue.Value = false
			end
		end
	end)
end

-- Hitbox for each of the third arrows and a different one for the final arrow (nuke-like)

local function createArrowHitbox(arrowPosition, playerCharacter, damage, isLastArrow)
	local hitboxSize = isLastArrow and CONFIG.FOURTH_ARROW_HITBOX or Vector3.new(20, 20, 20)
	local stunDuration = isLastArrow and CONFIG.FOURTH_ARROW_STUN or CONFIG.STUN_DURATION

	local hitboxCFrame = CFrame.new(arrowPosition)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {playerCharacter}

	local hitParts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
	local hitCharacters = {}

	for _, part in ipairs(hitParts) do
		local enemyChar = part.Parent
		if enemyChar and not hitCharacters[enemyChar] then
			local enemyHumanoid = enemyChar:FindFirstChildOfClass("Humanoid")
			local enemyRoot = enemyChar:FindFirstChild("HumanoidRootPart")

			if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
				if enemyChar.IFrames.Value == true then

				else
					hitCharacters[enemyChar] = true
					enemyHumanoid:TakeDamage(damage)
					enemyChar:SetAttribute("Stunned", false)
					applyStun(enemyChar, enemyHumanoid, stunDuration)
				end
			end
		end
	end
end

-- Release action lock attribute so now I can use other skills without colliding them with each other

local function releaseActionLock(character, token)
	if not character or not character.Parent then 
		return 
	end

	if character:GetAttribute("ActionLockToken") == token then
		character:SetAttribute("ActionLock", false)
	end

	task.wait(0.1)

	if character and character.Parent then
		if character:GetAttribute("ActionLockToken") == token then
			character:SetAttribute("ActionLock", false)
		end
	end
end

-- Creation of the arrows and their directions

local function createArrowPart(startCFrame, targetPosition, player, playerCharacter, isLastArrow, arrowNumber)
	local arrowTemplate = script.Union
	if not arrowTemplate then
		return
	end

	local arrow = arrowTemplate:Clone()

	local spawnOffsets = {
		Vector3.new(8, 15, -4),
		Vector3.new(-10, 18, -5),
		Vector3.new(12, 13, -3),
		Vector3.new(-8, 16, -4),
		Vector3.new(7, 20, -4),
		Vector3.new(-11, 14, -5),
		Vector3.new(10, 17, -4),
		Vector3.new(-7, 19, -4),
		Vector3.new(8, 12, -3),
		Vector3.new(-9, 21, -5)
	}

	local randomOffset = spawnOffsets[math.random(1, #spawnOffsets)]

	local startPosition = (startCFrame * CFrame.new(randomOffset)).Position
	arrow.CFrame = CFrame.lookAt(startPosition, targetPosition)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Parent = workspace

	playSFX(startPosition, SFX_ARROW_SPAWN)

	local spawnMarker = Instance.new("Part")
	spawnMarker.Size = Vector3.new(1, 1, 1)
	spawnMarker.Transparency = 1
	spawnMarker.Anchored = true
	spawnMarker.CanCollide = false
	spawnMarker.CFrame = CFrame.new(startPosition)
	spawnMarker.Parent = workspace

	local spawnPortal = shadowportal:Clone()
	spawnPortal.Parent = spawnMarker

	for _, v in pairs(spawnPortal:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = true
		end
	end

	task.delay(0.2, function()
		for _, v in pairs(spawnPortal:GetDescendants()) do
			if v:IsA("ParticleEmitter") then
				v.Enabled = false
			end
		end
	end)

	debrisService:AddItem(spawnMarker, 3)

	local tweenInfo = TweenInfo.new(
		0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local targetCFrame = CFrame.lookAt(targetPosition, targetPosition + (targetPosition - startPosition).Unit)
	local tween = tweenService:Create(arrow, tweenInfo, {
		CFrame = targetCFrame
	})

	tween:Play()

	tween.Completed:Connect(function()
		if isLastArrow then
			playSFX(targetPosition, SFX_FOURTH_ARROW, 6)

			for _, nearbyPlayer in pairs(players:GetPlayers()) do
				if nearbyPlayer.Character then
					local nearbyHRP = nearbyPlayer.Character:FindFirstChild("HumanoidRootPart")
					if nearbyHRP and (nearbyHRP.Position - targetPosition).Magnitude <= 400 then
						SanktBogenRemote:FireClient(nearbyPlayer)
					end
				end
			end

			local bigBangVFX = sukuna_big_bang:Clone()

			for _, child in pairs(bigBangVFX:GetChildren()) do
				if child:IsA("BasePart") then
					child.Anchored = true
					child.CanCollide = false

					for _, descendant in pairs(child:GetDescendants()) do
						if descendant:IsA("ParticleEmitter") then
							descendant.Enabled = true
						elseif descendant:IsA("Beam") then
							descendant.Enabled = true
						elseif descendant:IsA("Trail") then
							descendant.Enabled = true
						elseif descendant:IsA("Light") then
							descendant.Enabled = true
						elseif descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
							descendant.Enabled = true
						end
					end
				end
			end

			bigBangVFX.Parent = workspace

			local verticalCFrame = CFrame.new(targetPosition + Vector3.new(0, 55, 0)) * CFrame.Angles(math.rad(-90), 0, 0)
			bigBangVFX:PivotTo(verticalCFrame)

			debrisService:AddItem(bigBangVFX, 4.5)

			task.spawn(function()
				task.wait(4.3)
				if bigBangVFX and bigBangVFX.Parent then
					for _, child in pairs(bigBangVFX:GetChildren()) do
						if child:IsA("BasePart") then
							for _, descendant in pairs(child:GetDescendants()) do
								if descendant:IsA("ParticleEmitter") then
									descendant.Enabled = false
								elseif descendant:IsA("Beam") then
									descendant.Enabled = false
								elseif descendant:IsA("Trail") then
									descendant.Enabled = false
								elseif descendant:IsA("Light") then
									descendant.Enabled = false
								elseif descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
									descendant.Enabled = false
								end
							end
						end
					end
				end
			end)

		else
			playSFX(targetPosition, SFX_ARROW_EXPLODE)
		end

		createArrowHitbox(targetPosition, playerCharacter, CONFIG.DAMAGE_PER_ARROW, isLastArrow)

		arrow.Transparency = 1

		if not isLastArrow then
			for _, v in pairs(arrow:GetDescendants()) do
				if v:IsA("ParticleEmitter") then
					if v.Name == "Crescents" then v:Emit(15) end
					if v.Name == "Crescents2" then v:Emit(15) end
					if v.Name == "Dots" then v:Emit(25) end
					if v.Name == "Flame" then v:Emit(25) end
					if v.Name == "Lines" then v:Emit(45) end
					if v.Name == "Shockwave" then v:Emit(8) end
					if v.Name == "Smoke (BLACK)" then v:Emit(91) end
					if v.Name == "Stars" then v:Emit(25) end
				end
			end
		end

		debrisService:AddItem(arrow, 2)
	end)

	return arrow
end

-- The bow you see in front of the user in the move is spawned in this function.

local function spawnBow(character, hrp)
	local bow = BOW:Clone()
	bow.Parent = workspace
	bow.Anchored = false
	bow.CanCollide = false
	bow.CFrame = hrp.CFrame * CFrame.new(0, 5, -9) * CFrame.Angles(0, math.rad(180), 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = bow
	weld.Parent = bow

	for _, v in pairs(bow:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = true
		elseif v:IsA("Highlight") then
			v.Enabled = true
		end
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local animTrack = playAnimation(humanoid, ANIMATION)

	activeBows[character] = {bow = bow, weld = weld, animTrack = animTrack}

	return animTrack
end

-- And here it is destroyed

local function destroyBow(character)
	local bowData = activeBows[character]
	if bowData and bowData.bow and bowData.bow.Parent then
		local bow = bowData.bow

		for _, v in pairs(bow:GetDescendants()) do
			if v:IsA("ParticleEmitter") then
				v.Enabled = false
			elseif v:IsA("Highlight") then
				v.Enabled = false
			end
		end

		task.delay(0.3, function()
			if bow and bow.Parent then
				bow:Destroy()
			end
			activeBows[character] = nil
		end)
	end
end

-- Playing animations, sfx and forcing the player to send out a message with chat.

SanktBogenRemote.OnServerEvent:Connect(function(player, mousePosition, cameraCFrame)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp then return end

	local token = tick()
	character:SetAttribute("ActionLockToken", token)

	character:SetAttribute("ActionLock", true)
	hrp.Anchored = true

	local animTrack = spawnBow(character, hrp)

	if animTrack then
		animTrack.Stopped:Connect(function()
			if hrp and hrp.Parent then
				hrp.Anchored = false
			end

			releaseActionLock(character, token)
		end)
	end

	playSFX(hrp.Position, SFX_AURA, 5)

	chat:Chat(character.Head, "Sankt Bogen.", Enum.ChatColor.Blue)
	task.delay(6, function()
		chat:Chat(character.Head, "", Enum.ChatColor.Blue)
	end)

	playerArrowCounts[player] = 0
end)

-- The script is divided into 2 server events because the arrow logic is taken from client.

SanktBogenCS.OnServerEvent:Connect(function(player, mousePos, arrowNum)
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	playerArrowCounts[player] = (playerArrowCounts[player] or 0) + 1
	local currentArrowCount = playerArrowCounts[player]

	local isLastArrow = (currentArrowCount >= CONFIG.MAX_ARROWS)

	local lookDirection = (mousePos - hrp.Position) * Vector3.new(1, 0, 1)
	if lookDirection.Magnitude > 0 then
		local targetCFrame = CFrame.new(hrp.Position, hrp.Position + lookDirection.Unit)

		local tweenInfo = TweenInfo.new(
			0.15,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)

		local tween = tweenService:Create(hrp, tweenInfo, {
			CFrame = targetCFrame
		})

		tween:Play()
	end

	createArrowPart(hrp.CFrame, mousePos, player, character, isLastArrow, currentArrowCount)

	if isLastArrow then
		playerArrowCounts[player] = nil
		destroyBow(character)
	end
end)