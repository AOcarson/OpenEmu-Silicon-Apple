-- license:BSD-3-Clause
--
-- Apple II joystick timing compatibility fix for MAME Apple II emulation.
--
-- Reproduces the KEGS/AppleWin maximum-paddle workaround: when an Apple II
-- joystick axis reaches 255, extend the emulated paddle timer to the
-- equivalent of 287. Some games (Boulder Dash among them) time the paddle
-- with a loop that never sees 255 on MAME's exact timing, so full right/down
-- never registers.
--
-- Applies to every game on an Apple II machine. The OpenEmu Apple IIe core
-- enables it by default and has a per-game "Joystick Timing Fix" switch in
-- the Display Mode menu to turn it off for a game it upsets.
--
-- Works with MAME 0.250's and 0.289's Lua APIs (see on_frame/on_stop below).

local exports = {
    name = "apple2_joystick_fix",
    version = "2.0.0-mame0250",
    description = "Apple II joystick maximum-deflection timing fix",
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

local trigger_read_tap
local trigger_write_tap
local paddle_read_tap
local change_notifier
local installed = false
local running = false

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function is_apple2(machine)
    -- The Apple //e family only: the IIgs reads its paddles differently.
    local name = lower(machine.system.name)
    return name:match("^apple2") ~= nil and name:match("^apple2gs") == nil
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
    if not machine or not is_apple2(machine) then
        return
    end

    -- No joystick in the game port (e.g. "Joystick Connected" off): nothing to fix.
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
        C070, C07F, "Apple II paddle trigger read",
        function(offset, data, mask)
            trigger_paddles()
            return data
        end
    )

    trigger_write_tap = space:install_write_tap(
        C070, C07F, "Apple II paddle trigger write",
        function(offset, data, mask)
            trigger_paddles()
            return data
        end
    )

    paddle_read_tap = space:install_read_tap(
        C064, C065, "Apple II paddle timing extension",
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

    emu.print_info("[apple2_joystick_fix] 255 -> 287 paddle timing enabled")
end

-- MAME 0.250 has emu.register_frame/register_stop; later versions replace
-- them with notifiers whose subscriptions must be kept alive. Both last for
-- the whole session.
local subscriptions = {}
local function on_frame(callback)
    if emu.add_machine_frame_notifier then
        table.insert(subscriptions, emu.add_machine_frame_notifier(callback))
    else
        emu.register_frame(callback)
    end
end
local function on_stop(callback)
    if emu.add_machine_stop_notifier then
        table.insert(subscriptions, emu.add_machine_stop_notifier(callback))
    else
        emu.register_stop(callback)
    end
end

function plugin.startplugin()
    -- The callbacks last for the whole session, so they
    -- are registered once here. prestart runs on every machine start and
    -- reset; the taps survive a reset.
    emu.register_prestart(function()
        running = true
    end)

    -- Installs on the first frame after the CPU has started.
    on_frame(function()
        if running and not installed then
            install_fix()
        end
    end)

    -- Runs before the machine is torn down (including OpenEmu restarts), so
    -- the taps are removed while their address space still exists.
    on_stop(function()
        remove_fix()
        running = false
    end)
end

return exports
