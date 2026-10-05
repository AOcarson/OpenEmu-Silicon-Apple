# Home computers core: Apple IIe, Apple IIgs, Commodore 64 and 128, Macintosh (MAME 0.250 or 0.289)

`MAMEComputers.oecoreplugin` runs Apple //e, Apple IIgs, Commodore 64,
Commodore 128 and early Macintosh software in OpenEmu using the same headless
MAME 0.250 library as the Arcade core, built with only those drivers (or,
optionally, MAME 0.289; see below). One
core serves five systems, each with its own sidebar entry:

- **Apple IIe**, **Apple IIgs**, **Commodore 128** and **Macintosh** — system
  plugins in `OpenEmu/SystemPlugins/` added by this fork.
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

### MAME 0.289 (experimental)

The core can also be built on MAME 0.289 instead of 0.250:

```sh
./Scripts/build-mame-computers-core.sh --mame 0.289
./Scripts/install-core.sh MAMEComputers --release
```

Leave off `--mame 0.289` (or pass `--mame 0.250`) to go back. Each version
has its own MAME checkout (`deps/mame` for 0.250, `deps/mame-0289` for 0.289,
with `deps/mame-active` pointing at the one in use), so switching only
rebuilds the core, not MAME. The first 0.289 build downloads that release
(a few hundred MB) and compiles it from scratch. The installed core's version
says which MAME it has: `0.250.9` or `0.289.9`.

What to expect:

- **Not faster.** Newer MAME is usually a little slower, because it emulates
  more precisely. 0.289 is about accuracy (39 releases' worth of driver
  fixes) and is the base for the later Macs on the roadmap.
- **ROMs**: a few system ROM sets changed (see the table below). MAME's log
  names any file it can't find.
- **Saves**: save states don't carry over between the two versions. Disk
  images, MAME's per-game settings and nvram do.
- The 0.289 port (`patches/0289`) has only been compiled piecemeal so far,
  not as a whole on a Mac, so the first build may still need fixes.

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

Each system must be switched on in Settings › Library › Available Libraries.

`prepare-mame-computers-core.sh` (run by the build script) checks out the
pinned MAME 0.250 revision into `MAMEComputers/deps/mame` and applies, in order:

1. `MAME/patches/mame-headless-clang21-apple.patch` (shared with Arcade)
2. `MAMEComputers/patches/mame-headless-computers.patch` — adds
   `-[Options setValue:forOptionNamed:error:]` (slot and media options such as
   `gameio`, `flop1`, `iec8`, `quik`) and
   `-[OSD loadMediaAtPath:forDevice:error:]` for swapping media while running;
   starts MAME's Lua engine with the first machine (so plugins can be chosen
   per game); restarts the machine after a MAME hard reset; and restores most
   of MAME's main menu in headless mode.

For MAME 0.289 it checks out mamedev's `mame0289` release into
`MAMEComputers/deps/mame-0289` and applies `patches/0289/mame-headless-openemu.patch`
(OpenEmu's headless OSD, ported from the 0.250 fork) and
`patches/0289/mame-headless-computers.patch` (the same additions as above).
0.289 needs no compiler fixes for current Xcode. On 0.289 the IIgs settings
the patch adds sit one bit higher in `a2_config` (0.289 uses bit 3 for the
ROM 3's "Disable CDA Control Panel" jumper); the core reads
`OE_HEADLESS_MAME_VERSION` from the OSD headers to send the right bits.

The build script also copies MAME's Lua plugin bootstrap (`boot.lua`) and stock
plugins, plus this repo's plugins, into
`~/Library/Application Support/OpenEmu/MAMEComputers/plugins`.

Logs: `log show --last 5m --info --predicate 'subsystem == "org.openemu.MAMEComputers"'`

## System ROMs

Copy these zips, unchanged, from a MAME 0.250-compatible set (0.289 for a
0.289 build; see the changes after the tables) into
`~/Library/Application Support/OpenEmu/BIOS`. If a game won't start, the log
(see above) lists exactly which zips MAME could not find.

**Apple IIe**

| Set | What it is |
|---|---|
| `apple2ee.zip` | Apple //e (enhanced) ROMs. With a merged set they are inside `apple2e.zip` instead. |
| `apple2e.zip` | Parent set; also needed for the "Apple //e (Original)" machine. |
| `a2diskiing.zip` | Disk II controller (slot 6). |
| `votrax.zip` | Speech chip on the Mockingboard sound card MAME puts in slot 4. |

**Apple IIgs**

| Set | What it is |
|---|---|
| `apple2gs.zip` | Apple IIgs ROM 03 (the default machine), keyboard/mouse controller and character ROMs. |
| `apple2gsr1.zip` | Only for the "Apple IIgs (ROM 01)" machine. |

**Commodore 128**

| Set | What it is |
|---|---|
| `c128.zip` | C128 ROMs (NTSC machine). |
| `c128p.zip` | The PAL machine (the default) looks here; many sets store the same ROMs under both names. |
| `c1571.zip` | The C128's own 1571 drive; needed even for tapes and cartridges. |
| `c1581.zip` | Only for `.d81` disks. |

**Macintosh**

| Set | What it is |
|---|---|
| `macplus.zip` | Macintosh Plus ROM (the default machine; the Macintosh 512Ke uses it too). |
| `mackbd_m0110a.zip` | The Mac Plus keyboard's own controller chip. |
| `mac128k.zip` | For the "Macintosh 128K" machine. |
| `mac512k.zip` | For the "Macintosh 512K" machine (its own ROM revision). |
| `mackbd_m0110.zip` | The original Mac keyboard and keypad, used by the 128K, 512K and 512Ke (some sets also have `mackbd_m0120.zip` for the keypad). |
| `maclc2.zip` | Macintosh LC II ROM. |
| `egret.zip` | The LC II's Egret chip (keyboard, mouse and power). |

**Commodore 64**

| Set | What it is |
|---|---|
| `c64.zip` | C64 KERNAL, BASIC and character ROMs (used by both the PAL and NTSC machines). |
| `c1541.zip` | 1541 disk drive ROM. MAME always attaches the drive, so this is needed even for tapes and cartridges. |
| `c1571.zip` | Only for `.d71` disks. |
| `c1581.zip` | Only for `.d81` disks. |

System ROMs for these machines rarely change between MAME versions, so a
newer set usually works.

**Changes for MAME 0.289** (everything else above is the same):

| Set | What changed |
|---|---|
| `apple2gs.zip`, `apple2gsr1.zip` | Need `344s0047.bin` (the Mega II video ROM) instead of `341-0132-d.e12`. Use sets from MAME 0.289 or later. |
| `votrsc01a.zip` | The Mockingboard's speech chip, replacing `votrax.zip`. |

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

## Apple IIgs

- Supported images: 3.5" disks as `.2mg`, 800K `.po`, 3.5" `.woz` and
  DiskCopy 4.2 (`.dc`, `.dc42`). The Apple IIgs library claims only 3.5"
  disks and the Apple IIe library only 5.25" ones, decided by size and (for
  `.woz`) the disk type in the file, so importing never asks.
- To put a 5.25" disk in the Apple IIgs library instead, drop it on **Apple
  IIgs** in the sidebar, or on the Apple IIgs game list (see "Choosing the
  system when importing" below). 5.25" disks can also be inserted into a
  running IIgs game with **Insert Cart/Disk/Tape…**.
- An Apple IIe game can also be run on a IIgs without re-importing it:
  choose **Machine › Apple IIgs (ROM 03)** in its Display Mode menu.
- Machines: Apple IIgs (ROM 03, default) and ROM 01. The IIgs has no slot
  cards by default; add them through MAME's Slot Devices menu or
  `MAMEOptions`.

### Keyboard and mouse

The Mac keyboard maps straight onto the IIgs's: **Command is Open Apple**,
**Option is Option**, **F12 is RESET** (Control-F12 is Control-Reset;
Control-Command-F12 restarts). The keypad works on keyboards that have one.

The Mac pointer drives the IIgs mouse while it is over the game; click is the
mouse button. OpenEmu only reports where the pointer is, so the IIgs cursor
follows it rather than being locked to it: if they drift apart, move the
pointer off the edge of the game and back. Mouse speed can be adjusted in
MAME's menu (Analog Controls).

The joystick works as on the Apple IIe (Joystick Connected in the Display
Mode menu; Button 0 and 1 are also Open Apple and Option). The **Joystick
Timing Fix** (on by default, per game in the Display Mode menu) is built
into the IIgs emulation: a stick pushed all the way holds the paddle timer
for 287 units instead of 255, as KEGS and AppleWin do, so games whose
joystick loop never sees 255 (full down came out as up in Rampage) still
read full right/down. It is the apple2_joystick_fix plugin's rule; the
plugin itself only fits the Apple //e family's memory map. **Joystick Range**
(100% down to 50%, per game) makes a pushed stick read less far from centre,
like the joystick scale in KEGS/GSplus, for games that misread a stick at
full deflection.

**Speed.** Apple IIe software reads the joystick with timing loops made for
a 1 MHz CPU, so at the IIgs's 2.8 MHz the stick reads as pushed far
right/down and the game runs far too fast — exactly as on a real IIgs set to
Fast. The Display Mode menu's **Speed** sets Normal (1 MHz) or Fast
(2.8 MHz) per game. Normal works like a IIgs whose Control Panel is set to
Normal: the machine runs at 1 MHz except while the disk controller is busy,
so the IIgs firmware can still read 3.5" disks at full speed. (It is a setting
the core's MAME patch adds to the IIgs, shown in MAME's Machine
Configuration menu as "Apple II software speed".)

Speed defaults to Normal for 5.25" disks and for Apple IIe games run on the
IIgs machine, and to Fast for 3.5" disks — including 8-bit games on 3.5"
disks, which were made for the IIc Plus and IIgs and can expect their speed
(Rampage reads its joystick wrongly at 1 MHz). A game's choice is
remembered. (The Mac
pointer no longer moves the joystick either: MAME's default of mixing the
mouse into analog sticks is turned off.)

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

## Commodore 128

Works like the C64 (autostart, joystick ports, Extra buttons, per-game
settings), with its own machine (C128 PAL by default, or NTSC):

- **Which files go here.** The C128 shares every file type with the C64 and
  most of those files are C64 software, so imports go to the C64 unless the
  file or its folder is named as C128 software ("C128" or "128" as a word,
  e.g. TOSEC's "Commodore C128" folders) or it is a `.d71` disk. To send any
  other file to the C128, drop it on **Commodore 128** in the sidebar or on
  the Commodore 128 game list.
- **Screen.** The C128 has a 40-column (VIC) and an 80-column (VDC) screen;
  **Screen** in the Display Mode menu shows one or the other (saved per
  game). The C128 itself chooses where to print at power-on from the 40/80
  DISPLAY key (Page Up, see below).
- **Media.** `.d64/.g64/.x64/.d71` in the 1571 drive, `.d81` in a 1581,
  `.prg/.p00` loaded straight into memory, `.tap` on the datasette, `.crt`
  cartridges. C64 cartridges switch the C128 into C64 mode by themselves.

### Keyboard

As on the C64 (Esc is RUN/STOP, F10 RESTORE, F11 CLR/HOME, F12 ↑, Option
the Commodore key, F1–F8 as printed), plus:

| C128 key | Mac key |
|---|---|
| Cursor keys (the separate ones above the keyboard) | Arrow keys |
| TAB | Tab |
| CTRL | Control |
| ALT | Right Option |
| ESC | Home |
| HELP | End |
| 40/80 DISPLAY | Page Up |
| NO SCROLL | Page Down |
| Keypad | Keypad |

The arrow keys are the C128's own cursor keys, which work in C128 mode.
Keys a Mac laptop lacks (Home, End, Page Up/Down) can be moved to any key or
gamepad button in MAME's Input Settings.

## Macintosh

The Macintosh system is a **Macintosh Plus** (1986: 4 MB of memory, two 800K
floppy drives, System 1 to 7) — the reference machine for early black-and-white
Mac games — and a **Macintosh LC II** (1992: 68030, colour, 10 MB, a 1.4 MB
SuperDrive and a SCSI hard drive and CD-ROM, System 7). The Display Mode
menu's **Machine** also offers the Macintosh 512K, 512Ke and the original 128K.

Disk images: `.dsk`, `.img` and `.image` (raw 400K, 800K or 1.4 MB), DiskCopy
4.2 (`.dc42`, `.dc`, `.diskcopy`), Applesauce `.moof`, and hard drives (see
below). The library takes a file as a Mac disk when it holds a Mac (HFS or
MFS) volume or Mac boot blocks, so Apple II disks of the same size and
extension still go to the Apple IIs. 1.4 MB disks start on the LC II (the
Plus has no SuperDrive).

### Hard drives and the LC II

A hard drive image is imported like a game: it shows up in the Macintosh
library, and opening it starts a Mac from that drive (the LC II, or the Plus
if the LC II's ROMs are missing or you choose it under Machine). Everything
installed on the drive is there each time, and changes are saved to the
image, as on a real hard drive.

- **Whole-drive images** start up as they are: `.hda`/`.hd`/`.img`/`.dsk`
  files with an Apple partition map and driver (BlueSCSI and ZuluSCSI
  images are like this), or MAME hard disk `.chd` files.
- **Basilisk II / Mini vMac disks** (`.dsk`, `.hfv`, `.img` volumes) are
  only the Mac volume, without the partition map and Apple driver the real
  hardware starts up from. Opening one says so; set up a drive as below and
  copy what you need onto it.
- **Setting up a new drive with System 7:**
  1. Make an empty drive image in Terminal (500 MB here; HFS volumes on
     System 7 go up to 2 GB):
     `mkfile -n 500m "Macintosh HD.hda"`
  2. Import `Macintosh HD.hda` into the Macintosh library and open it. The
     LC II starts and shows the flashing question mark (nothing to start up
     from yet).
  3. **Insert Cart/Disk/Tape…** a System 7.5 CD image (`.iso`, `.cdr`,
     `.toast`), then **Reset**: the LC II starts up from the CD. The CD
     stays in its drive across restarts and the next time you open the
     drive, until **Eject CD** in the Display Mode menu.
  4. Run **Apple HD SC Setup** (on the CD's utilities, or the Disk Tools
     disk) and **Initialize** the drive: MAME's drive answers as an Apple
     Seagate, which HD SC Setup accepts. Then run the System 7.5 Installer
     onto it.
  5. Eject the CD and Reset: the LC II starts up from its hard drive.
     Install games from floppies (Insert Cart/Disk/Tape…, 1.4 MB disks
     included) or CDs.

The LC II has the Apple Extended Keyboard: Command, Option and Control are
the Mac's own keys, with Esc, the arrows, F-keys (except F9, the MAME menu)
and the keypad. MAME 0.289 runs the LC II better than 0.250 (whose LC II
sound is marked imperfect). Its ROMs are `maclc2.zip` and `egret.zip` (the
Egret ADB/power chip).

### Startup disk

Many Mac game disks can't start the Mac on their own: they hold only the game
and need a System disk to start up from. Put one System disk image (System 6
or 7.0.1 are good choices for a Mac Plus) in

    ~/Library/Application Support/OpenEmu/MAMEComputers/Startup Disks/Macintosh/

(the core creates the folder the first time a Mac game is opened; with
several images, the first by name is used). When a game's disk has no boot
blocks, the Mac then starts up from the System disk in drive 1 with the game
in drive 2 — open it from the desktop. The Display Mode menu's **Startup
Disk** setting can make a game always or never use it.

The Mac writes to the disk it starts up from, so each game gets its own copy
of the System disk (in `Startup Disks/Macintosh Copies/<game>/`), made again
whenever the original is replaced. Games can't spoil it for each other, and
save states find the disk as they left it. All three Mac models use the Mac
Plus keyboard.

### Keyboard and mouse

Command is Command and Option is Option. The Mac Plus keyboard has no Control
or Esc key (in Mac software Command-. usually stands in for Esc); its keypad
has Clear (the Mac's Clear key or Num Lock) and =. A gamepad button (or a
key) can be bound to **Mouse Button** in OpenEmu's Controls.

### Which Mac a game runs on

Early Mac software often only works on the Macs of its time: Frogger 1.0
draws its playing field straight into the screen memory of a 128K/512K Mac,
so on a Plus only its title screen shows. The core looks each Mac disk up
in MAME's software lists (`mac_flop_orig`, `mac_flop_clcracked`,
`mac_flop`), which record for several hundred disks which Macs the software
runs on, and starts the game on a compatible one. The table is
`MAMEComputers/MCMacSoftwareList.h`, made from MAME's lists by
`Scripts/generate-mac-software-table.py`; a disk is recognised by its SHA-1,
so only unmodified dumps (such as 4am's moof-a-day `.moof` files) match. The
match is remembered in the game's settings, so it still applies after the
game has saved to its disk.

Machines are tried in this order, and the first whose ROMs are all present
runs:

1. The game's **Machine** setting, if you chose one.
2. The Macs the software list names, in the Machine menu's order (Plus,
   512K, 128K, 512Ke, LC II; software listed for colour Macs such as the
   Mac II or LC family goes to the LC II).
3. The LC II for hard drives, CDs and 1.4 MB disks.
4. The Macintosh Plus.

So a missing ROM set no longer locks a game out: it starts on the next
machine, and the log says which ROMs the skipped one needed. Choosing a
machine in the menu whose ROMs are missing keeps the one that was running.

Each Mac has its own keyboard: the Plus keyboard on the Plus, the original
keyboard with numeric keypad on the 128K, 512K and 512Ke (as on archive.org).
The original keyboard has no arrow keys; the Mac's arrow keys press the
keypad keys that carry the arrows (/ , + *).

**Mouse** (Display Mode menu, per game):

- **Follows the Pointer** (default): the Mac's cursor sits under your
  pointer. Once the Mac OS has started, the core writes the pointer's
  position into the OS's own mouse variables each time the pointer moves
  (MTemp, RawMouse and Mouse in low memory, then CrsrNew), as Mini vMac
  does, so the Mac's mouse acceleration can't pull the two apart. Before the
  OS starts (the happy Mac and the disk icon) the cursor doesn't move.
- **Relative**: the old behaviour, an emulated mouse moved by the distance
  the pointer moves. For the rare game that reads the mouse hardware itself
  and ignores the OS's cursor.

The memory access needs the core's MAME patch from 0.250.6 / 0.289.6 or
later (`-[OSD readProgramMemory:…]` / `writeProgramMemory:…`).

## Choosing the system when importing

OpenEmu normally sorts imported files by itself. To choose, drop the files on
a system in the sidebar, or on the game list while that system is shown:
files of a type the system accepts go into it even if it wouldn't claim them
on its own. Dropping on the "Consoles" header, or on a system that doesn't
take that file type, sorts automatically as before. (A file already in the
library stays where it is; remove it first to import it into another system.)

## All systems

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

### Keys bound in OpenEmu's Controls

A Mac key bound to a control in Preferences › Controls (a joystick
direction, a button, MAME Menu, Reset) does only that job; it is not also
typed on the emulated keyboard. Bindings are per system, so the Apple IIe,
Apple IIgs, C64 and C128 each have their own. For a quick keyboard joystick
without setting up bindings, use **Arrow Keys Control Joystick** in the
Display Mode menu instead.

### Binding keys to gamepad buttons

Games that need keys beyond the joystick (a space bar to start, F1 for
options, RUN/STOP to pause) can have them on a gamepad:

1. In Preferences › Controls, bind gamepad buttons to **Extra 1–6** (they sit
   under MAME Menu, on every system).
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
- **Machine (restarts)** — Apple //e (Enhanced), Apple //e (Original), or
  Apple IIgs (ROM 03) to run the game on a IIgs (needs `apple2gs.zip`).
- **Drive 1 / Drive 2** — shown for multi-disk games (see below).

Apple IIgs: the same, without the timing fix, and Machine is ROM 03 or ROM 01.
Drive 1 and 2 are the 3.5" drives (or the 5.25" ones for a 5.25" disk set).

Commodore 64 and 128:

- **Joystick Port** — port 2 or port 1 for joystick 1 (applies at once).
- **Arrow Keys Control Joystick** — as above; right Option/Command fire.
- **Autostart (next launch)** — type LOAD/RUN for you (on by default).
- **Machine (restarts)** — PAL or NTSC.
- **Screen** (C128 only) — 40 or 80 columns.
- **Disk** — shown for multi-disk games.

The settings live in
`~/Library/Application Support/OpenEmu/MAMEComputers/Game Settings/<system>/<game>.plist`.
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
script installs the MAME version's own plugins there, plus the ones kept in this
repo's `MAMEComputers/plugins/`: `apple2_joystick_fix` and `c64_openemu`.

**Joystick timing fix.** `apple2_joystick_fix` is on for every Apple IIe
game by default (it leaves the IIgs alone). When the joystick is pushed fully right or down (value 255), it
stretches the paddle timer to 287, as AppleWin and KEGS do, so games whose
timing loops never see 255 in MAME (Boulder Dash, for one) register full
deflection. If it upsets a game, turn **Joystick Timing Fix** off for that
game in the Display Mode menu; it takes effect the next time the game is
opened.

**Commodore glue.** `c64_openemu` routes the joysticks to the control ports
and does the autostart typing described above, on the C64 and the C128. The
core always loads it for their games (and it does nothing on other machines).

**Choosing plugins.** Every game gets the default list, which is the joystick
fix (it only acts on the Apple IIe) unless `Global Settings.plist` in the core's support folder has its own
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
stopping the game. On a 0.250 build plugins run on MAME 0.250's Lua API: a
plugin written for a much newer MAME may need small changes (for example
`emu.register_frame` instead of `emu.add_machine_frame_notifier`). The two
plugins in this repo check which one MAME has, so they work on both builds.

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
