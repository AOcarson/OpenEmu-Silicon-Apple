-- license:BSD-3-Clause
--
-- OpenEmu glue for MAME's Commodore 64 drivers (c64, c64p and relatives).
-- The OpenEmu MAMEComputers core always loads it for Commodore 64 games.
--
-- 1. Joystick ports. The C64 has two control ports and most games read the
--    joystick in port 2, some in port 1, and two-player games read both.
--    MAME wires both ports to player 1 by default. This routes OpenEmu's
--    player 1 to the port the game wants and player 2 to the other one.
--    The core holds KEYCODE_F19 down while the game's setting says port 1,
--    so a change in OpenEmu's menu (or its "Swap Joysticks" button) applies
--    at once.
--
-- 2. Autostart. When the machine reaches the READY. prompt it types (through
--    the KERNAL keyboard buffer) what a C64 owner would:
--      disk:      LOAD"*",8,1  then RUN once it has loaded
--      program:   RUN          (MAME has already put .prg/.t64 in memory)
--      tape:      LOAD         with PLAY pressed, then RUN
--    Cartridges start themselves. The core holds KEYCODE_F18 down when
--    autostart is off for the game.
--
-- Written for MAME 0.250's Lua API.

local exports = {
    name = "c64_openemu",
    version = "1.0.0-mame0250",
    description = "OpenEmu glue for the Commodore 64",
    license = "BSD-3-Clause",
    author = { name = "OpenEmu MAMEComputers core" }
}
local plugin = exports

local SCREEN_RAM = 0x0400
local COLUMNS, ROWS = 40, 25
local READY = { 0x12, 0x05, 0x01, 0x04, 0x19, 0x2e } -- "READY." in screen codes
local QUICKLOAD_SETTLE = 4.0   -- MAME loads .prg files 3 s after power-on
local SCAN_EVERY = 10          -- frames between screen scans

local active = false
local frame = 0
local routed_primary          -- port joystick 1 is routed to (1 or 2)
local fields_by_port          -- { [1] = { up = field, ... }, [2] = { ... } }
local auto                    -- autostart state, nil when finished/off

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function is_c64(machine)
    return lower(machine.system.name):match("^c64") ~= nil
end

local function pressed(token)
    local input = manager.machine.input
    local code = input:code_from_token(token)
    return code ~= nil and input:code_pressed(code)
end

-------------------------------------------------------------------------------
-- Joystick routing
-------------------------------------------------------------------------------

local CONTROLS = {
    { key = "up",    token = "P1_JOYSTICK_UP",    suffix = " Up",       code = "YAXIS_UP_SWITCH" },
    { key = "down",  token = "P1_JOYSTICK_DOWN",  suffix = " Down",     code = "YAXIS_DOWN_SWITCH" },
    { key = "left",  token = "P1_JOYSTICK_LEFT",  suffix = " Left",     code = "XAXIS_LEFT_SWITCH" },
    { key = "right", token = "P1_JOYSTICK_RIGHT", suffix = " Right",    code = "XAXIS_RIGHT_SWITCH" },
    { key = "fire",  token = "P1_BUTTON1",        suffix = " Button 1", code = "BUTTON1" },
}

local function find_joystick_fields(machine)
    local ioport = machine.ioport
    local types = {}
    for _, c in ipairs(CONTROLS) do
        local ok, t = pcall(function() return (ioport:token_to_input_type(c.token)) end)
        types[c.key] = ok and t or nil
    end

    local result = {}
    for tag, port in pairs(ioport.ports) do
        local n = tag:match("^:joy([12]):")
        if n then
            n = tonumber(n)
            for name, field in pairs(port.fields) do
                for _, c in ipairs(CONTROLS) do
                    local by_type = types[c.key] ~= nil and field.type == types[c.key]
                    local by_name = name:sub(-#c.suffix) == c.suffix
                    if by_type or by_name then
                        result[n] = result[n] or {}
                        result[n][c.key] = field
                    end
                end
            end
        end
    end
    return result
end

local function route_joysticks(primary)
    local input = manager.machine.input
    for port = 1, 2 do
        local fields = fields_by_port[port]
        if fields then
            local joy = (port == primary) and 1 or 2
            for _, c in ipairs(CONTROLS) do
                local field = fields[c.key]
                if field then
                    local seq = input:seq_from_tokens(string.format("JOYCODE_%d_%s", joy, c.code))
                    field:set_input_seq("standard", seq)
                end
            end
        end
    end
    routed_primary = primary
    emu.print_info(string.format("c64_openemu: joystick 1 -> port %d, joystick 2 -> port %d", primary, 3 - primary))
end

local function update_routing()
    local primary = pressed("KEYCODE_F19") and 1 or 2
    if primary ~= routed_primary then
        route_joysticks(primary)
    end
end

-------------------------------------------------------------------------------
-- Autostart
-------------------------------------------------------------------------------

local function main_space(machine)
    local cpu = machine.devices[":u7"] or machine.devices[":maincpu"]
    return cpu and cpu.spaces["program"]
end

-- Rows (0-based) that start with READY., top to bottom.
local function ready_rows(space)
    local rows = {}
    for row = 0, ROWS - 1 do
        local base = SCREEN_RAM + row * COLUMNS
        local match = true
        for i, code in ipairs(READY) do
            if (space:read_u8(base + i - 1) & 0x7f) ~= code then
                match = false
                break
            end
        end
        if match then
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function mounted_media(machine)
    local media = {}
    for _, image in pairs(machine.images) do
        if image.exists then
            media[image.brief_instance_name] = image
        end
    end
    return media
end

local function start_autostart(machine)
    auto = nil
    if pressed("KEYCODE_F18") then
        emu.print_info("c64_openemu: autostart is off for this game")
        return
    end

    local media = mounted_media(machine)
    local mode
    if media.cart then
        return -- cartridges start by themselves
    elseif media.quik then
        mode = "program"
    elseif media.cass then
        mode = "tape"
    elseif media.flop then
        mode = "disk"
    else
        return
    end

    auto = { mode = mode, step = "boot", row = -1 }
    emu.print_info("c64_openemu: autostart " .. mode)
end

-- Typing goes straight into the KERNAL's keyboard buffer, as VICE's
-- autostart does, rather than through MAME's natural keyboard: pressing keys
-- through the emulated keyboard matrix can drop or garble characters (the
-- matrix is shared with the joystick ports).
local KEYBUF = 0x0277      -- KERNAL keyboard buffer
local KEYBUF_COUNT = 0x00c6
local KEYBUF_SIZE = 10

local function type_text(text)
    auto.pending = (auto.pending or "") .. text
end

-- Feeds pending text into the keyboard buffer as it empties. Returns true
-- while there is still text waiting to be typed.
local function feed_keyboard(space)
    local pending = auto.pending
    if not pending or pending == "" then
        return false
    end
    if space:read_u8(KEYBUF_COUNT) ~= 0 then
        return true
    end
    local chunk = pending:sub(1, KEYBUF_SIZE)
    for i = 1, #chunk do
        -- Upper case ASCII, digits and punctuation are the same in PETSCII;
        -- "\r" is RETURN.
        space:write_u8(KEYBUF + i - 1, chunk:byte(i))
    end
    space:write_u8(KEYBUF_COUNT, #chunk)
    auto.pending = pending:sub(KEYBUF_SIZE + 1)
    return true
end

local function step_autostart(machine)
    if not auto or frame % SCAN_EVERY ~= 0 then
        return
    end
    local space = main_space(machine)
    if not space then
        auto = nil
        return
    end
    if feed_keyboard(space) then
        return
    end
    if auto.step == "done" then
        auto = nil
        return
    end

    local rows = ready_rows(space)
    local last = rows[#rows]

    if auto.step == "boot" then
        if not last then
            return
        end
        if auto.mode == "program" then
            if machine.time:as_double() < QUICKLOAD_SETTLE then
                return
            end
            type_text("RUN\r")
            auto.step = "done"
        elseif auto.mode == "disk" then
            type_text('LOAD"*",8,1\r')
            auto.step, auto.row = "loading", last
        elseif auto.mode == "tape" then
            for _, cass in pairs(machine.cassettes) do
                cass:play()
            end
            type_text("LOAD\r")
            auto.step, auto.row = "loading", last
        end
    elseif auto.step == "loading" then
        -- A new READY. below the one we typed after means the load finished
        -- without the program starting itself.
        if last and last > auto.row then
            type_text("RUN\r")
            auto.step = "done"
        end
    end
    feed_keyboard(space)
end

-------------------------------------------------------------------------------
-- Plugin entry
-------------------------------------------------------------------------------

function plugin.startplugin()
    -- MAME 0.250's register_* callbacks last for the whole session (the core
    -- restarts the machine on reset and on some menu changes), so register
    -- once and re-arm on every machine start.
    emu.register_prestart(function()
        active = false
        frame = 0
        routed_primary = nil
        fields_by_port = nil
        auto = nil
    end)

    emu.register_frame(function()
        local machine = manager.machine
        if frame == 0 then
            active = is_c64(machine)
            if active then
                fields_by_port = find_joystick_fields(machine)
                start_autostart(machine)
            end
        end
        frame = frame + 1
        if not active then
            return
        end
        update_routing()
        step_autostart(machine)
    end)

    emu.register_stop(function()
        active = false
        auto = nil
    end)
end

return exports
