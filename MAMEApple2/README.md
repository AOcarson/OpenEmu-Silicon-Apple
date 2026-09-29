# Apple IIe core (MAME 0.250)

`MAMEApple2.oecoreplugin` runs Apple //e disk images in OpenEmu using the same
headless MAME 0.250 library as the Arcade core, built with only the Apple //e
drivers. It pairs with the **Apple IIe** system plugin
(`OpenEmu/SystemPlugins/Apple IIe`), which adds "Apple IIe" to the library
sidebar.

## Build and install

```sh
./Scripts/build-mame-apple2-core.sh          # MAME dylib + core plugin
./Scripts/install-core.sh MAMEApple2 --release
./Scripts/verify-core-installed.sh MAMEApple2 --release
```

The app itself must also be built from this checkout, since the Apple IIe
system plugin ships inside OpenEmu.app:

```sh
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Release -destination 'platform=macOS,arch=arm64' build
```

`prepare-mame-apple2-core.sh` (run by the build script) checks out the pinned
MAME revision from `MAME/deps-mame-revision.txt` into `MAMEApple2/deps/mame`
and applies, in order:

1. `MAME/patches/mame-headless-clang21-apple.patch` (shared with Arcade)
2. `MAMEApple2/patches/mame-headless-apple2.patch` — adds
   `-[Options setValue:forOptionNamed:error:]` (slot and media options such as
   `gameio` and `flop1`) and `-[OSD loadMediaAtPath:forDevice:error:]` for
   swapping disks while running; starts MAME's Lua engine with the first
   machine (so plugins can be chosen per game); restarts the machine after a
   MAME hard reset; and restores most of MAME's main menu in headless mode.

The build script also copies MAME's Lua plugin bootstrap (`boot.lua`) and stock
plugins into `~/Library/Application Support/OpenEmu/MAMEApple2/plugins`.

## System ROMs

Copy these zips, unchanged, from a MAME 0.250-compatible set into
`~/Library/Application Support/OpenEmu/BIOS`:

| Set | What it is |
|---|---|
| `apple2ee.zip` | Apple //e (enhanced) ROMs. With a merged set they are inside `apple2e.zip` instead. |
| `apple2e.zip` | Parent set; also needed for the "Apple //e (Original)" machine. |
| `a2diskiing.zip` | Disk II controller (slot 6). |
| `votrax.zip` | Speech chip on the Mockingboard sound card MAME puts in slot 4. |

Apple II system ROMs rarely change between MAME versions, so a newer set
usually works. If something is missing, the error message lists exactly which
zips MAME could not find.

## Using it

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

### MAME's menu

Like standalone MAME, the Apple //e starts with MAME's UI keys off so every
key reaches the emulated keyboard. **fn-Delete** (Forward Delete) toggles them
on and off; while on, **Tab** opens MAME's menu (Input Settings, DIP Switches,
Machine Configuration, File Manager, Slot Devices, BIOS Selection, Slider
Controls, Cheat, Plugin Options). Changes made there are saved in MAME's own
config files under `~/Library/Application Support/OpenEmu/MAMEApple2/cfg`.
Slot changes need **Reset System** from the Slot Devices menu, which restarts
the machine. Esc with UI keys on asks before "quitting", which just restarts
the machine; OpenEmu's own controls close the game.

### Joystick

Gamepads map to the Apple II joystick; an analog stick gives proportional
movement, a d-pad full deflection. Two joysticks are supported.

### Per-game settings (the Display Mode menu)

In-game, the Display Mode menu in the HUD bar holds settings that are saved
per game:

- **Joystick Connected (restarts)** — plugs the joystick into the game port
  (on by default). Some games misbehave when no joystick is present, others
  when one is.
- **Arrow Keys Control Joystick** — arrow keys move joystick 1 instead of
  typing arrows. Handy for action games; leave off for text games.
- **Machine (restarts)** — Apple //e (Enhanced) or Apple //e (Original).
- **Drive 1 / Drive 2** — shown for multi-disk games (see below).

The settings live in
`~/Library/Application Support/OpenEmu/MAMEApple2/Game Settings/<game>.plist`.
Besides the keys the menu writes (`JoystickConnected`, `ArrowKeysControlJoystick`,
`Machine`), you can add a `MAMEOptions` dictionary of any MAME option to apply
at boot — the equivalent of extra MAME command-line switches. For example:

```xml
<key>MAMEOptions</key>
<dict>
    <key>gameio</key>  <string>paddles</string>  <!-- paddle games instead of a joystick -->
    <key>sl4</key>     <string></string>         <!-- remove the Mockingboard -->
    <key>sl7</key>     <string>cffa2</string>    <!-- CFFA2 hard disk card (needs a2cffa2.zip)... -->
    <key>hard1</key>   <string>/path/to/ProDOS.po</string> <!-- ...with this image -->
</dict>
```

Slot options are applied before media options, and `MAMEOptions` are applied
after the menu settings, so they win.

### MAME Lua plugins

Put a plugin folder (with its `plugin.json` and `init.lua`) in
`~/Library/Application Support/OpenEmu/MAMEApple2/plugins/`, next to MAME's
own plugins, and list it in the game's settings file:

```xml
<key>MAMEPlugins</key>
<array>
    <string>myfix</string>   <!-- the plugin's folder name -->
</array>
```

Plugins kept in `MAMEApple2/plugins/` in this repo are installed there by
the build script too — currently `boulderdash_joystick_fix`, which extends the
joystick's maximum paddle timing (255 → 287, like AppleWin and KEGS) so
Boulder Dash can move right and down. It only activates when a Boulder Dash
disk is mounted.

Plugins start when the game is opened, so changes apply the next time you
open it. A plugin name that isn't installed is skipped (and logged) rather
than stopping the game. Note these run on MAME 0.250's Lua API: a plugin
written for a much newer MAME may need small changes (for example
`emu.register_frame_done` instead of `emu.add_machine_frame_notifier`).

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
