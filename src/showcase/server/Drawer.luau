--!strict
-- Sliding a drawer, which is the other half of Hinge.
--
-- Hinge rotates about an edge; this translates along an axis. Same discipline in both: cancel
-- rather than queue, close on a token rather than a stored timer, and put the sound that says
-- "it stopped" at the *end* of the travel rather than the start.
--
-- **The axis is measured, not assumed.** A drawer's pull direction is its shortest horizontal
-- dimension -- a drawer is wide and shallow, and it comes out of the shallow face. Assuming
-- local Z means every drawer built the other way round slides out through the side of the desk,
-- which looks like a physics bug rather than a wrong constant.

local TweenService = game:GetService("TweenService")

local Drawer = {}
Drawer.__index = Drawer

export type Config = {
	-- How far it comes out, as a share of its own depth. 0.7 leaves it visibly still in the desk.
	TravelShare: number,
	OpenSeconds: number,
	CloseSeconds: number,
	AutoCloseSeconds: number,
	OpenSound: string?,
	ShutSound: string?,
}

export type Slide = typeof(setmetatable({} :: {
	part: BasePart,
	home: CFrame,
	out: CFrame,
	alpha: NumberValue,
	config: Config,
	isOpen: boolean,
	tween: Tween?,
	closeToken: number,
	rattle: Sound?,
	shut: Sound?,
}, Drawer))

local function makeSound(parent: BasePart, name: string, id: string, volume: number, speed: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = 40
	sound.Parent = parent
	return sound
end

function Drawer.new(part: BasePart, config: Config): Slide
	-- The pull axis: whichever of local X or Z is shorter. A drawer front is wide; its depth
	-- into the desk is the small number.
	local size = part.Size
	local pullLocal = if size.X <= size.Z then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local depth = if size.X <= size.Z then size.X else size.Z

	local self = setmetatable({
		part = part,
		home = part.CFrame,
		out = part.CFrame * CFrame.new(pullLocal * depth * config.TravelShare),
		alpha = Instance.new("NumberValue"),
		config = config,
		isOpen = false,
		tween = nil,
		closeToken = 0,
		rattle = nil,
		shut = nil,
	}, Drawer) :: Slide

	-- One NumberValue per drawer, created once. TweenService cannot tween a computed CFrame, so
	-- the interpolant gets its own property and the part follows it -- the same trick as Hinge,
	-- and for the same reason: making it per-open allocates an Instance every time somebody
	-- opens a desk.
	self.alpha.Name = "SlideAlpha"
	self.alpha.Value = 0
	self.alpha.Parent = part
	self.alpha.Changed:Connect(function(value: number)
		self.part.CFrame = self.home:Lerp(self.out, value)
	end)

	if config.OpenSound ~= nil then
		self.rattle = makeSound(part, "Rattle", config.OpenSound, 0.55, 1)
	end
	if config.ShutSound ~= nil then
		self.shut = makeSound(part, "Shut", config.ShutSound, 0.7, 0.95)
	end

	return self
end

function Drawer.slideTo(self: Slide, target: number, seconds: number, easing: Enum.EasingStyle)
	if self.tween ~= nil then
		self.tween:Cancel()
	end
	self.tween = TweenService:Create(self.alpha, TweenInfo.new(seconds, easing, Enum.EasingDirection.Out), { Value = target })
	;(self.tween :: Tween):Play()
end

function Drawer.Open(self: Slide)
	if self.isOpen then
		return
	end
	self.isOpen = true
	if self.rattle ~= nil then
		self.rattle:Play()
	end
	-- Quint-out: a drawer on runners leaves quickly and glides to a stop. Linear reads as a lift.
	self:slideTo(1, self.config.OpenSeconds, Enum.EasingStyle.Quint)

	self.closeToken += 1
	local token = self.closeToken
	task.delay(self.config.AutoCloseSeconds, function()
		if token == self.closeToken and self.isOpen then
			self:Close()
		end
	end)
end

function Drawer.Close(self: Slide)
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.closeToken += 1
	self:slideTo(0, self.config.CloseSeconds, Enum.EasingStyle.Quad)

	local token = self.closeToken
	task.delay(self.config.CloseSeconds, function()
		-- The knock of it seating, at the end of the travel. With the tween it sounds like the
		-- drawer hit something on the way out.
		if token == self.closeToken and not self.isOpen and self.shut ~= nil then
			self.shut:Play()
		end
	end)
end

function Drawer.Toggle(self: Slide)
	if self.isOpen then
		self:Close()
	else
		self:Open()
	end
end

return Drawer
