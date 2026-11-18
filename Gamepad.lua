local _, ns = ...

-- Forever Gamepad UI support. SmartNavigation / FrameControlsManager are
-- Blizzard internals (not a documented API): every call is existence-checked,
-- and every call that touches them goes through ns.RunSafe because they are
-- taint-wrapped to work from addon code only OUT OF COMBAT.

local Gamepad = {}
ns.Gamepad = Gamepad

local listeners = {}
local lastMode

function Gamepad.IsActive()
	local style = C_InputInterfaceStyle
	local types = Enum and Enum.InputDeviceInterfaceType
	if style and style.GetCurrentStyle and types and types.Gamepad ~= nil then
		return style.GetCurrentStyle() == types.Gamepad
	end
	return false
end

-- "gamepad" or "mkb"; used as the key for per-mode layout and positions.
function Gamepad.Mode()
	return Gamepad.IsActive() and "gamepad" or "mkb"
end

-- fn(mode) is called whenever the input style changes.
function Gamepad.OnModeChanged(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	local mode = Gamepad.Mode()
	if mode == lastMode then
		return
	end
	lastMode = mode
	for i = 1, #listeners do
		ns.SafeCall(listeners[i], mode)
	end
end

function Gamepad.Init()
	lastMode = Gamepad.Mode()
	ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", Notify) -- no-op on clients without it
end

local function FrameControls()
	return GamepadMode and GamepadMode.FrameControlsManager
end

-- Make a window work with B/Escape, Blizzard's gamepad focus manager and ConsolePort.
-- The frame must be named (UISpecialFrames stores names) and should have a CloseButton.
function Gamepad.RegisterPanel(frame)
	if type(frame) ~= "table" or not frame.GetObjectType then
		error("Gamepad.RegisterPanel: frame expected", 2)
	end

	local name = frame:GetName()
	if name and not tContains(UISpecialFrames, name) then
		tinsert(UISpecialFrames, name)
	end

	frame:HookScript("OnShow", function(self)
		ns.RunSafe(function()
			local manager = FrameControls()
			-- Re-check: the frame may have been hidden while we waited for combat to end.
			if manager and manager.FrameShown and self:IsShown() then
				manager:FrameShown(self)
			end
		end)
	end)

	frame:HookScript("OnHide", function(self)
		ns.RunSafe(function()
			local manager = FrameControls()
			if manager and manager.FrameHidden and not self:IsShown() then
				manager:FrameHidden(self)
			end
		end)
	end)

	if ConsolePort and ConsolePort.AddInterfaceCursorFrame then
		ns.SafeCall(ConsolePort.AddInterfaceCursorFrame, ConsolePort, frame)
	end
end

-- SmartNavigation marking setters (Blizzard_GamepadSmartNavigation/Utility.lua):
-- "may be set without causing taint (only while out of combat)".
-- Never write frame.smartNavigation* fields directly.
local function Mark(functionName, frame, ...)
	local fn = _G[functionName]
	if type(fn) ~= "function" then
		return
	end
	ns.RunSafe(fn, frame, ...)
end

-- Skip decorative/overlay frames so focus never lands on them.
function Gamepad.Ignore(frame, dontPropagate)
	Mark("SmartNavigation_MarkFrameIgnored", frame, dontPropagate)
end

-- Make a non-Button frame (e.g. a clickable row) reachable by the d-pad.
function Gamepad.MakeFocusable(frame)
	Mark("SmartNavigation_MarkFrameFocusable", frame)
end
