-- license:BSD-3-Clause
--
-- Boulder Dash joystick timing compatibility fix for MAME Apple II emulation.
--
-- Reproduces the KEGS/AppleWin maximum-paddle workaround used by Boulder Dash:
-- when an Apple II joystick axis reaches 255, extend the emulated paddle timer
-- to the equivalent of 287.
--
-- The plugin remains inactive unless Boulder Dash is detected on an Apple II
-- floppy image/software list.
--
-- Port of the MAME 0.289 version to MAME 0.250's Lua API (as used by the
-- OpenEmu Apple IIe core):
--   * emu.add_machine_frame_notifier / add_machine_stop_notifier do not exist;
--     emu.register_frame / emu.register_stop are used instead. Those persist
--     for the whole session, so they are registered once in startplugin
--     rather than on every machine start.
--   * image:add_media_change_notifier does not exist; while the fix is
--     installed, the mounted disks are re-checked about once a second and the
--     fix is removed if Boulder Dash is no longer in a drive.
--   * machine:side_effects_disabled() does not exist; it only matters for
--     debugger memory reads, and the debugger is not available in OpenEmu.

local exports = {
    name = "boulderdash_joystick_fix",
    version = "1.0.0-mame0250",
    description = "Apple II Boulder Dash joystick timing compatibility fix",
    license = "BSD-3-Clause",
    author = { name = "Community compatibility shim" }
}
local plugin = exports

local PDL_UNIT_SEC = 10.8e-6
local NATIVE_MAX   = 255
local EXTENDED_MAX = 287

local C064 = 0xc064
local C065 = 0xc065
local C070 = 0xc070
local C07F = 0xc07f

-- Frames between media re-checks while the fix is installed (~1 s at 60 Hz).
local RECHECK_FRAMES = 60

local trigger_read_tap
local trigger_write_tap
local paddle_read_tap
local change_notifier
local installed = false
local running = false
local frames_since_check = 0

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function basename(s)
    local v = tostring(s or "")
    return v:match("([^/\\]+)$") or v
end

local function is_apple2(machine)
    return lower(machine.system.name):match("^apple2") ~= nil
end

local function text_is_boulderdash(s)
    s = lower(s)
    return s:find("boulder dash", 1, true)
        or s:find("boulder_dash", 1, true)
        or s:find("boulderdash", 1, true)
        or s:find("bouldash", 1, true)
end

local function detect_boulderdash(machine)
    for _, image in pairs(machine.images) do
        if image.exists then
            local listname = lower(image.software_list_name)
            local longname = lower(image.software_longname)
            local parent   = lower(image.software_parent)
            local filename = lower(basename(image.filename))

            local apple2_floppy_list = listname:match("^apple2_flop") ~= nil

            if apple2_floppy_list and (
                text_is_boulderdash(longname)
                or text_is_boulderdash(parent)
                or text_is_boulderdash(filename)
            ) then
                return true
            end

            if not image.loaded_through_softlist and text_is_boulderdash(filename) then
                return true
            end
        end
    end

    return false
end

local function find_port(machine, suffix)
    for tag, port in pairs(machine.ioport.ports) do
        if tag == suffix or tag:sub(-#suffix) == suffix then
            return port
        end
    end
end

local function remove_fix()
    if trigger_read_tap then
        trigger_read_tap:remove()
        trigger_read_tap = nil
    end

    if trigger_write_tap then
        trigger_write_tap:remove()
        trigger_write_tap = nil
    end

    if paddle_read_tap then
        paddle_read_tap:remove()
        paddle_read_tap = nil
    end

    if change_notifier then
        change_notifier:unsubscribe()
        change_notifier = nil
    end

    installed = false
end

local function install_fix()
    if installed then
        return
    end

    local machine = manager.machine
    if not machine or not is_apple2(machine) or not detect_boulderdash(machine) then
        return
    end

    local joy_x = find_port(machine, "joystick_1_x")
    local joy_y = find_port(machine, "joystick_1_y")
    if not joy_x or not joy_y then
        return
    end

    local cpu = machine.devices[":maincpu"]
    if not cpu or not cpu.started or not cpu.spaces or not cpu.spaces["program"] then
        return
    end

    local space = cpu.spaces["program"]

    local x_native_expiry = 0.0
    local y_native_expiry = 0.0
    local x_extended_expiry = 0.0
    local y_extended_expiry = 0.0

    local function now()
        return machine.time:as_double()
    end

    local function trigger_paddles()
        local t = now()
        local x = joy_x:read() & 0xff
        local y = joy_y:read() & 0xff

        if t >= x_native_expiry then
            x_native_expiry = t + (x * PDL_UNIT_SEC)
            x_extended_expiry =
                t + (((x >= NATIVE_MAX) and EXTENDED_MAX or x) * PDL_UNIT_SEC)
        end

        if t >= y_native_expiry then
            y_native_expiry = t + (y * PDL_UNIT_SEC)
            y_extended_expiry =
                t + (((y >= NATIVE_MAX) and EXTENDED_MAX or y) * PDL_UNIT_SEC)
        end
    end

    trigger_read_tap = space:install_read_tap(
        C070, C07F, "Boulder Dash paddle trigger read",
        function(offset, data, mask)
            trigger_paddles()
            return data
        end
    )

    trigger_write_tap = space:install_write_tap(
        C070, C07F, "Boulder Dash paddle trigger write",
        function(offset, data, mask)
            trigger_paddles()
            return data
        end
    )

    paddle_read_tap = space:install_read_tap(
        C064, C065, "Boulder Dash paddle timing extension",
        function(offset, data, mask)
            local t = now()

            if offset == C064
               and t >= x_native_expiry
               and t < x_extended_expiry then
                return data | 0x80
            end

            if offset == C065
               and t >= y_native_expiry
               and t < y_extended_expiry then
                return data | 0x80
            end

            return data
        end
    )

    local reinstalling = false

    change_notifier = space:add_change_notifier(function(kind)
        if reinstalling then
            return
        end

        reinstalling = true

        if trigger_read_tap then
            trigger_read_tap:reinstall()
        end

        if trigger_write_tap then
            trigger_write_tap:reinstall()
        end

        if paddle_read_tap then
            paddle_read_tap:reinstall()
        end

        reinstalling = false
    end)

    installed = true
    frames_since_check = 0

    emu.print_info(
        "[boulderdash_joystick_fix] Boulder Dash detected; 255 -> 287 paddle timing enabled"
    )
end

local function on_frame()
    if not running then
        return
    end

    if not installed then
        install_fix()
        return
    end

    -- Stand-in for 0.289's media change notifier: if the disk was swapped
    -- away from Boulder Dash, drop the fix.
    frames_since_check = frames_since_check + 1
    if frames_since_check >= RECHECK_FRAMES then
        frames_since_check = 0
        local machine = manager.machine
        if not machine or not detect_boulderdash(machine) then
            remove_fix()
        end
    end
end

function plugin.startplugin()
    -- Runs on every machine start and reset. The taps survive a reset, so
    -- only the running flag is updated here.
    emu.register_prestart(function()
        running = true
    end)

    emu.register_frame(on_frame)

    -- Runs before the machine is torn down (including OpenEmu restarts), so
    -- the taps are removed while their address space still exists.
    emu.register_stop(function()
        remove_fix()
        running = false
    end)
end

return exports
