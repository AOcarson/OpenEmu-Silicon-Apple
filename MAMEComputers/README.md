# Home computers core: Apple IIe and Commodore 64 (MAME 0.250)

`MAMEComputers.oecoreplugin` runs Apple //e and Commodore 64 software in
OpenEmu using the same headless MAME 0.250 library as the Arcade core, built
with only the Apple //e and C64 drivers. One core serves two systems:

- **Apple IIe** — the system plugin in `OpenEmu/SystemPlugins/Apple IIe`
  (added by this fork).
- **Commodore 64** — OpenEmu's existing `OpenEmu/SystemPlugins/Commodore 64`,
  which had no core since the libretro bridge was removed.

Until version 0.250.2 this core was called `MAMEApple2` and ran only the
Apple IIe. The build script moves its support folder (ROMs, settings, MAME
config, plugins) to the new name and removes the old core. Save states made
with `MAMEApple2` don't load in this core.

## Build and install

```sh
./Scripts/build-mame-computers-core.sh           # MAME dylib + core plugin
./Scripts/install-core.sh MAMEComputers --release
./Scripts/verify-core-installed.sh MAMEComputers --release
```

The app itself must also be built from this checkout, since the Apple IIe
system plugin ships inside OpenEmu.app:

```sh
./Scripts/build-for-worktree.sh --release
```

That builds to `~/Builds/openemu/<branch>/Build/Products/Release/OpenEmu.app`
(the same place every time) and, if Xcode has an Apple Development
certificate (a free Apple ID in Xcode › Settings › Accounts › Manage
Certificates › +), signs with it, so macOS keeps the Input Monitoring
permission across rebuilds. Quit OpenEmu before opening a new build.

Both systems must be switched on in Settings › Library › Available Libraries.

`prepare-mame-computers-core.sh` (run by the build script) checks out the
pinned MAME revision into `MAMEComputers/deps/mame` and applies, in order:

1. `MAME/patches/mame-headless-clang21-apple.patch` (shared with Arcade)
2. `MAMEComputers/patches/mame-headless-computers.patch` — adds
   `-[Options setValue:forOptionNamed:error:]` (slot and media options such as
   `gameio`, `flop1`, `iec8`, `quik`) and
   `-[OSD loadMediaAtPath:forDevice:error:]` for swapping media while running;
   starts MAME's Lua engine with the first machine (so plugins can be chosen
   per game); restarts the machine after a MAME hard reset; and restores most
   of MAME's main menu in headless mode.

The build script also copies MAME's Lua plugin bootstrap (`boot.lua`) and stock
plugins, plus this repo's plugins, into
`~/Library/Application Support/OpenEmu/MAMEComputers/plugins`.

Logs: `log show --last 5m --info --predicate 'subsystem == "org.openemu.MAMEComputers"'`

## System ROMs

Copy these zips, unchanged, from a MAME 0.250-compatible set into
`~/Library/Application Support/OpenEmu/BIOS`. If something is missing, the
error message lists exactly which zips MAME could not find.

**Apple IIe**

| Set | What it is |
|---|---|
| `apple2ee.zip` | Apple //e (enhanced) ROMs. With a merged set they are inside `apple2e.zip` instead. |
| `apple2e.zip` | Parent set; also needed for the "Apple //e (Original)" machine. |
| `a2diskiing.zip` | Disk II controller (slot 6). |
| `votrax.zip` | Speech chip on the Mockingboard sound card MAME puts in slot 4. |

**Commodore 64**

| Set | What it is |
|---|---|
| `c64.zip` | C64 KERNAL, BASIC and character ROMs (used by both the PAL and NTSC machines). |
| `c1541.zip` | 1541 disk drive ROM. MAME always attaches the drive, so this is needed even for tapes and cartridges. |
| `c1571.zip` | Only for `.d71` disks. |
| `c1581.zip` | Only for `.d81` disks. |

System ROMs for these machines rarely change between MAME versions, so a
newer set usually works.

## Apple IIe

- Supported images: `.dsk`, `.do`, `.po`, `.nib`, `.woz`. `.dsk` is shared
  with MSX, so the importer only claims files whose size (143,360 or 116,480
  bytes) proves they are Apple II disks.
- MAME writes changes back to the disk image, so games that save to disk keep
  their saves.

### Keyboard

Every Mac key goes to the Apple //e keyboard. Option or Command are the Apple
keys (left = Open Apple, right = Solid Apple), which are also joystick buttons
0 and 1 on real hardware. **F12 is Control-Reset** (bound in Preferences ›
Controls, so it can be changed).

### Joystick

Gamepads map to the Apple II joystick; an analog stick gives proportional
movement, a d-pad full deflection. Two joysticks are supported.

## Commodore 64

The C64 starts as a PAL machine (most C64 games are European); switch a game
to NTSC in the Display Mode menu if it runs too slowly or its music is off.

| File | What happens |
|---|---|
| `.d64` `.g64` `.x64` | Inserted in a 1541 drive; the core types `LOAD"*",8,1` and then `RUN` if the game doesn't start itself. |
| `.d71` / `.d81` | As above, with a 1571 / 1581 drive instead. |
| `.prg` `.p00` `.t64` | Loaded straight into memory, then `RUN`. |
| `.tap` | PLAY is pressed, the core types `LOAD`, then `RUN`. Tapes are slow, as on the real thing. |
| `.crt` | Plugged into the expansion port; cartridges start by themselves. |

`.p64` disks are listed by the Commodore 64 system but MAME 0.250 can't read
them; convert them to `.g64`. The typing is done by the `c64_openemu` Lua
plugin, which the core always loads for C64 games. Turn **Autostart** off for
a game to get a plain READY prompt instead. **Insert Cart/Disk/Tape…** puts a
file in the matching device (a cartridge restarts the machine).

### Joysticks

Most C64 games read the joystick in port 2, some in port 1. OpenEmu's
player 1 controls the port chosen under **Joystick Port** in the Display Mode
menu (port 2 by default), and player 2 controls the other port, so
two-player games work with two controllers. The **Swap Joysticks** button
(bindable in Preferences › Controls) flips the ports instantly and the choice
is saved for the game. **Jump** is joystick up, for games where up jumps.

With **Arrow Keys Control Joystick** on, the arrow keys move joystick 1 and
right Option or right Command fire.

### Keyboard

Letters, digits and punctuation keys sit where they are on a C64 keyboard
(so the Mac's `-` key types `+`, `[` types `@`, `;` types `:` and so on). The
special keys are:

| C64 key | Mac key |
|---|---|
| RUN/STOP | Esc |
| RESTORE | F10 (or Page Up) |
| CLR/HOME | F11 (or Home) |
| INST/DEL | Delete |
| CTRL | Tab or Control |
| Commodore (C=) | Option |
| £ | End |
| ↑ | F12 (or Page Down) |
| ← | `` ` `` |
| SHIFT LOCK | Caps Lock |
| F1–F8 | F1–F8 (the core presses Shift for F2/F4/F6/F8) |
| Cursor keys | Arrow keys (the core presses Shift for up and left) |

Command is left to the Mac.

## Both systems

### MAME's menu

Open MAME's menu (Input Settings, DIP Switches, Machine Configuration, File
Manager, Tape Control, Slot Devices, BIOS Selection, Slider Controls, Cheat,
Plugin Options) any of these ways:

- **F9** — the **MAME Menu** control in Preferences › Controls, so it can be
  moved to another key or a gamepad button. Press it again to close the menu.
- **Open MAME Menu** in the Display Mode menu of the HUD bar.
- MAME's own way: **Forward Delete** toggles MAME's UI keys on (so every key
  otherwise reaches the emulated keyboard), then **Tab**. Mac laptop keyboards
  send fn-Delete to OpenEmu as plain Delete, so this only works with a
  keyboard that has a Forward Delete key.

While the menu is open the keyboard types plain PC keys, whatever the
machine: arrows move, Return selects, Esc goes back, Delete clears an
assignment, Tab closes the menu. A gamepad's stick and first button work too.
F-keys on a Mac laptop need fn held, or "Use F1, F2, etc. keys as standard
function keys" switched on in System Settings › Keyboard.

Changes made there are saved **per game** in MAME's own config files under
`~/Library/Application Support/OpenEmu/MAMEComputers/cfg/<system>/<game>/`.
Slot changes need **Reset System** from the Slot Devices menu, which restarts
the machine.

### Binding keys to gamepad buttons

Games that need keys beyond the joystick (a space bar to start, F1 for
options, RUN/STOP to pause) can have them on a gamepad:

1. In Preferences › Controls, bind gamepad buttons to **Extra 1–6** (they sit
   under MAME Menu, for both systems).
2. In the game, open MAME's menu › Input Settings › Input Assignments (this
   system), pick the key (e.g. "Space"), and press the gamepad button. MAME
   shows it as Joy 1 Button 3–8 (Extra 1 is Button 3).

The assignment is saved for that game only. On the C64, leave the control
port joysticks to OpenEmu's Joystick Port setting: the core re-routes them
each time the game starts.

### Per-game settings (the Display Mode menu)

In-game, the Display Mode menu in the HUD bar holds settings that are saved
per game.

Apple IIe:

- **Joystick Connected (restarts)** — plugs the joystick into the game port
  (on by default). Some games misbehave when no joystick is present, others
  when one is.
- **Arrow Keys Control Joystick** — arrow keys move joystick 1 instead of
  typing arrows. Handy for action games; leave off for text games.
- **Joystick Timing Fix (next launch)** — see Lua plugins below.
- **Machine (restarts)** — Apple //e (Enhanced) or Apple //e (Original).
- **Drive 1 / Drive 2** — shown for multi-disk games (see below).

Commodore 64:

- **Joystick Port** — port 2 or port 1 for joystick 1 (applies at once).
- **Arrow Keys Control Joystick** — as above; right Option/Command fire.
- **Autostart (next launch)** — type LOAD/RUN for you (on by default).
- **Machine (restarts)** — Commodore 64 (PAL) or Commodore 64 (NTSC).
- **Disk** — shown for multi-disk games.

The settings live in
`~/Library/Application Support/OpenEmu/MAMEComputers/Game Settings/<Apple IIe or Commodore 64>/<game>.plist`.
Besides the keys the menu writes (`JoystickConnected`, `ArrowKeysControlJoystick`,
`Machine`, `JoystickPort`, `Autostart`), you can add a `MAMEOptions`
dictionary of any MAME option to apply at boot — the equivalent of extra MAME
command-line switches. For example, on the Apple IIe:

```xml
<key>MAMEOptions</key>
<dict>
    <key>gameio</key>  <string>paddles</string>  <!-- paddle games instead of a joystick -->
    <key>sl4</key>     <string></string>         <!-- remove the Mockingboard -->
    <key>sl7</key>     <string>cffa2</string>    <!-- CFFA2 hard disk card (needs a2cffa2.zip)... -->
    <key>hard1</key>   <string>/path/to/ProDOS.po</string> <!-- ...with this image -->
</dict>
```

or on the C64 (`joy1`/`joy2` pick what is in each control port):

```xml
<key>MAMEOptions</key>
<dict>
    <key>joy1</key>  <string>pad</string>    <!-- paddles in port 1 -->
    <key>iec8</key>  <string>c1571</string>  <!-- a 1571 drive for this game -->
</dict>
```

Slot options are applied before media options, and `MAMEOptions` are applied
after the menu settings, so they win.

### MAME Lua plugins

Plugins live in `~/Library/Application Support/OpenEmu/MAMEComputers/plugins/`
(one folder per plugin, with its `plugin.json` and `init.lua`). The build
script installs MAME 0.250's own plugins there, plus the ones kept in this
repo's `MAMEComputers/plugins/`: `apple2_joystick_fix` and `c64_openemu`.

**Joystick timing fix.** `apple2_joystick_fix` is on for every game by
default. When the joystick is pushed fully right or down (value 255), it
stretches the paddle timer to 287, as AppleWin and KEGS do, so games whose
timing loops never see 255 in MAME (Boulder Dash, for one) register full
deflection. If it upsets a game, turn **Joystick Timing Fix** off for that
game in the Display Mode menu; it takes effect the next time the game is
opened.

**C64 glue.** `c64_openemu` routes the joysticks to the C64 control ports and
does the autostart typing described above. The core always loads it for C64
games (and it does nothing on other machines).

**Choosing plugins.** Every game gets the default list, which is the joystick
fix (it only acts on Apple II machines) unless `Global Settings.plist` in the core's support folder has its own
`MAMEPlugins` array (an empty array turns plugins off everywhere). A game's
settings file can then add and remove plugins:

```xml
<key>MAMEPlugins</key>          <!-- added for this game -->
<array>
    <string>myplugin</string>   <!-- the plugin's folder name -->
</array>
<key>DisabledMAMEPlugins</key>  <!-- removed for this game -->
<array>
    <string>apple2_joystick_fix</string>
</array>
```

Plugins start when the game is opened, so changes apply the next time you
open it. A plugin that isn't installed is skipped (and logged) rather than
stopping the game. These run on MAME 0.250's Lua API: a plugin written for a
much newer MAME may need small changes (for example `emu.register_frame`
instead of `emu.add_machine_frame_notifier`).

### Multi-disk games

Disks that sit in the same folder and share a name apart from a disk or side
marker are treated as one game, e.g.

```
Ultima IV (Disk 1 of 4 Side A).woz
Ultima IV (Disk 1 of 4 Side B).woz
```

(TOSEC `(Disk 1 of 2)(Side A)`, `(Side B)`, and plain `disk1`/`disk2`
suffixes also work.) Launch any of them. Swap disks with **Select Disc** in
the HUD menu (drive 1) or the **Drive 1** / **Drive 2** groups in the Display
Mode menu. **Insert Cart/Disk/Tape…** loads any other image into drive 1.
All disks of a set share one settings file.
