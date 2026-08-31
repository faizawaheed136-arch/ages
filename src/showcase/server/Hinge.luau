--!strict
-- Swinging a door on its hinge, which is not the same as rotating it.
--
-- **The mistake this module exists to prevent.** Tweening `door.CFrame` or `door.Orientation`
-- rotates the leaf about its own centre, so it pivots through its middle and half of it sweeps
-- straight through the wall. It looks almost right at 15 degrees and obviously wrong at 90,
-- which is why it survives a first test.
--
-- A hinge is a rotation about an *edge*. The fix is to work out the hinge frame once at setup,
-- keep the leaf's offset from it, and rebuild the CFrame for every angle:
--
--     leaf:PivotTo(hinge * CFrame.Angles(0, angle, 0) * offset)
--
-- `offset` is constant, so this is two CFrame multiplies per frame per moving door and nothing
-- else. Doors that are not moving cost nothing at all -- there is no polling anywhere in here.

local TweenService = game:GetService("TweenService")

local Hinge = {}
Hinge.__index = Hinge

export type Config = {
	Side: "Left" | "Right",
	SwingDegrees: number,
	OpenSeconds: number,
	CloseSeconds: number,
	SlamSeconds: number,
	AutoCloseSeconds: number,
	OpenSound: string?,
	LatchSound: string?,
	ThudSound: string?,
}

export type Door = typeof(setmetatable({} :: {
	subject: PVInstance,
	leaf: BasePart,
	hinge: CFrame,
	offset: CFrame,
	angle: NumberValue,
	config: Config,
	isOpen: boolean,
	tween: Tween?,
	closeToken: number,
	latch: Sound?,
	creak: Sound?,
	thud: Sound?,
}, Hinge))

-- ---------------------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------------------

-- Parented to the leaf, so it is **positional** -- unlike the bell in section 08, a door you
-- cannot see should not be audible across the courtyard. RollOff is tapered rather than linear
-- because a heavy latch should be sharp up close and gone by twenty studs.
local function makeSound(parent: BasePart, name: string, id: string, volume: number, speed: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 65
	sound.Parent = parent
	return sound
end

-- ---------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------

function Hinge.new(subject: PVInstance, config: Config): Door?
	-- A Model swings as a unit but the hinge has to be derived from one flat part, because a
	-- model's pivot can be anywhere its author left it. The PrimaryPart is the leaf.
	local leaf: BasePart?
	if subject:IsA("BasePart") then
		leaf = subject
	elseif subject:IsA("Model") then
		leaf = subject.PrimaryPart
	end
	if leaf == nil then
		warn(`[Hinge] {subject:GetFullName()} has no PrimaryPart -- cannot find the hinge edge`)
		return nil
	end

	-- The hinge sits on the leaf's local X edge, full height, centred in depth. Which edge is
	-- the Side; which way it swings is the sign of SwingDegrees.
	local sign = if config.Side == "Right" then 1 else -1
	local hinge = leaf.CFrame * CFrame.new(sign * leaf.Size.X / 2, 0, 0)

	local self = setmetatable({
		subject = subject,
		leaf = leaf,
		hinge = hinge,
		-- Constant for the life of the door. Everything else is derived from it.
		offset = hinge:Inverse() * subject:GetPivot(),
		angle = Instance.new("NumberValue"),
		config = config,
		isOpen = false,
		tween = nil,
		closeToken = 0,
		latch = nil,
		creak = nil,
		thud = nil,
	}, Hinge) :: Door

	-- **One NumberValue per door, created once.**
	--
	-- TweenService cannot tween a computed expression, only a property, so the angle gets its
	-- own property to live in and the door follows it. Making this per-open instead would
	-- allocate an Instance and a connection every single time somebody opens a locker.
	self.angle.Name = "HingeAngle"
	self.angle.Value = 0
	self.angle.Parent = leaf
	self.angle.Changed:Connect(function(value: number)
		self.subject:PivotTo(self.hinge * CFrame.Angles(0, math.rad(value), 0) * self.offset)
	end)

	if config.LatchSound ~= nil then
		self.latch = makeSound(leaf, "Latch", config.LatchSound, 0.7, 1)
	end
	if config.OpenSound ~= nil then
		-- Pitched down: the same hinge sample at 0.8 reads as a much heavier door, the same
		-- trick as the bell.
		self.creak = makeSound(leaf, "Creak", config.OpenSound, 0.75, 0.8)
	end
	if config.ThudSound ~= nil then
		self.thud = makeSound(leaf, "Thud", config.ThudSound, 0.85, 0.9)
	end

	return self
end

-- ---------------------------------------------------------------------------------------
-- Swing
-- ---------------------------------------------------------------------------------------

function Hinge.swingTo(self: Door, target: number, seconds: number, easing: Enum.EasingStyle)
	-- Cancelled, not ignored. A player who re-triggers mid-swing should have the door reverse
	-- from wherever it actually is; letting the old tween finish first is what produces a door
	-- that snaps backwards before closing.
	if self.tween ~= nil then
		self.tween:Cancel()
	end
	local info = TweenInfo.new(seconds, easing, Enum.EasingDirection.Out)
	self.tween = TweenService:Create(self.angle, info, { Value = target })
	;(self.tween :: Tween):Play()
end

function Hinge.Open(self: Door)
	if self.isOpen then
		return
	end
	self.isOpen = true

	-- Latch first, then the swing. A heavy door is a mechanism releasing and *then* moving, and
	-- playing both together is the single thing that makes a door sound light.
	if self.latch ~= nil then
		self.latch:Play()
	end
	if self.creak ~= nil then
		self.creak:Play()
	end

	-- Quad-out: fast off the latch, slowing into the stop. Linear reads as a machine; a door
	-- with mass leaves quickly and arrives slowly.
	self:swingTo(self.config.SwingDegrees, self.config.OpenSeconds, Enum.EasingStyle.Quad)

	self.closeToken += 1
	local token = self.closeToken
	task.delay(self.config.AutoCloseSeconds, function()
		-- **Token, not a stored handle.** A door opened, slammed and opened again inside the
		-- five seconds has two pending closes in flight; without this the first one shuts the
		-- door under the second open.
		if token == self.closeToken and self.isOpen then
			self:Close(false)
		end
	end)
end

function Hinge.Close(self: Door, slam: boolean)
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.closeToken += 1

	local seconds = if slam then self.config.SlamSeconds else self.config.CloseSeconds
	if self.creak ~= nil and not slam then
		self.creak:Play()
	end

	-- Quart-in for the close: slow to leave, quick to arrive, so it lands on the thud rather
	-- than easing gently into it.
	self:swingTo(0, seconds, Enum.EasingStyle.Quart)

	local token = self.closeToken
	task.delay(seconds, function()
		-- The thud belongs at the *end* of the travel, not the start. Firing it with the tween
		-- is the second most common reason a door sounds weightless.
		if token == self.closeToken and not self.isOpen then
			if self.thud ~= nil then
				self.thud:Play()
			end
			if self.latch ~= nil then
				self.latch:Play()
			end
		end
	end)
end

function Hinge.Toggle(self: Door)
	if self.isOpen then
		-- "Instantly" on a second trigger, read as a slam rather than a teleport: a zero-length
		-- tween skips the travel *and* the sound, and looks like the door failed to animate.
		self:Close(true)
	else
		self:Open()
	end
end

return Hinge
