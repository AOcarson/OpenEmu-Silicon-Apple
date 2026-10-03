/*
 Copyright (c) 2026, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "MAMEComputersGameCore.h"

#import <OpenEmuBase/OERingBuffer.h>
#import <OpenGL/gl.h>
#import <os/log.h>
#import <os/lock.h>

#pragma mark - Systems

typedef NS_ENUM(NSInteger, MCSystem)
{
    MCSystemApple2,
    MCSystemApple2GS,
    MCSystemC64,
    MCSystemC128,
    MCSystemMac,
};

static NSString *const MCSystemIdentifierApple2   = @"openemu.system.apple2";
static NSString *const MCSystemIdentifierApple2GS = @"openemu.system.apple2gs";
static NSString *const MCSystemIdentifierC64      = @"openemu.system.c64";
static NSString *const MCSystemIdentifierC128     = @"openemu.system.c128";
static NSString *const MCSystemIdentifierMac      = @"openemu.system.mac";

#pragma mark - Settings

// Per-game settings file keys. These files live in
// <core support folder>/Game Settings/<system>/<game>.plist and can be edited
// by hand.
static NSString *const MCSettingMachine          = @"Machine";                   // MAME driver
static NSString *const MCSettingArrowKeys        = @"ArrowKeysControlJoystick";  // BOOL, default NO
static NSString *const MCSettingJoystick         = @"JoystickConnected";         // Apple II/IIgs: BOOL, default YES
static NSString *const MCSettingJoystickPort     = @"JoystickPort";              // C64/C128: 1 or 2, default 2
static NSString *const MCSettingAutostart        = @"Autostart";                 // C64/C128: BOOL, default YES
static NSString *const MCSettingScreen           = @"Screen";                    // C128: "40" or "80", default "40"
static NSString *const MCSettingIIgsSpeed        = @"IIgsSpeed";                 // IIgs machine: "normal" (1 MHz) or "fast" (2.8 MHz)
static NSString *const MCSettingJoystickRange    = @"JoystickRange";             // IIgs machine: percent, 50-100, default 100
static NSString *const MCSettingStartupDisk      = @"StartupDisk";               // Mac: "auto", "always" or "never", default "auto"
static NSString *const MCSettingMAMEOptions      = @"MAMEOptions";               // { option: value }, applied at boot
static NSString *const MCSettingMAMEPlugins      = @"MAMEPlugins";               // [ plugin folder name ], added
static NSString *const MCSettingDisabledPlugins  = @"DisabledMAMEPlugins";       // [ plugin folder name ], removed

// Lua plugins. Required ones are part of how a system works here; default
// ones can be turned off per game (or replaced everywhere through
// Global Settings.plist's MAMEPlugins).
static NSString *const MCPluginApple2JoystickFix = @"apple2_joystick_fix";
static NSString *const MCPluginC64               = @"c64_openemu";

// Display-mode preference keys (identify menu entries; never saved by OpenEmu).
static NSString *const MCModeJoystick     = @"mc.joystick";
static NSString *const MCModeArrowKeys    = @"mc.arrowkeys";
static NSString *const MCModeMachine      = @"mc.machine";
static NSString *const MCModeDrive1       = @"mc.drive1";
static NSString *const MCModeDrive2       = @"mc.drive2";
static NSString *const MCModeJoystickFix  = @"mc.joystickfix";
static NSString *const MCModeJoystickPort = @"mc.joystickport";
static NSString *const MCModeAutostart    = @"mc.autostart";
static NSString *const MCModeMAMEMenu     = @"mc.mamemenu";
static NSString *const MCModeScreen       = @"mc.screen";
static NSString *const MCModeIIgsSpeed    = @"mc.iigsspeed";
static NSString *const MCModeJoystickRange = @"mc.joystickrange";
static NSString *const MCModeStartupDisk  = @"mc.startupdisk";

// The IIgs's "Apple II software speed" setting, which the core's MAME patch
// adds to the IIgs's Machine Configuration: Normal keeps the machine at
// 1 MHz except while a disk drive's motor is on, so the firmware can still
// run 3.5" drives at full speed (as on a IIgs set to Normal).
static NSString *const MCIIgsConfigPort   = @":a2_config";
static const uint32_t  MCIIgsNormalSpeed  = 0x08;
// The patch also gives the IIgs the apple2_joystick_fix plugin's 255 -> 287
// paddle rule (the plugin's taps only fit the Apple //e family's memory map).
static const uint32_t  MCIIgsJoystickFix  = 0x10;
// Bits 5-7: how far from centre a pushed stick reads, 100% down to 50% in
// steps of 10 (some games misread full deflection; Rampage takes down as up).
static const uint32_t  MCIIgsJoystickRange = 0xE0;

enum { MCMaxPlayers = 2 };
enum { MCExtraButtons = 6 };  // MAME joystick buttons 3-8
enum { MCDriveEmpty = -1 };

#pragma mark - Keyboard mapping

// USB HID keyboard usage (what OpenEmu delivers in keyDown:/keyUp:) to the
// MAME keyboard item the emulated keyboard expects. MAME defines each
// machine's keyboard matrix in terms of PC keycodes; these tables put those
// keys where a Mac user expects them. `mod` is an extra key held with it:
// the C64 has one key for Cursor Left/Right and one for F1/F2, told apart
// by Shift, so the Mac's Left arrow and F2 press Shift for you.
typedef struct
{
    uint8_t     hid;
    InputItemID item;
    InputItemID mod;
    const char *name;
} MCKeyMapping;

#define KEY(h, i, n)        { h, InputItemID_##i, InputItemID_INVALID, n }
#define KEYMOD(h, i, m, n)  { h, InputItemID_##i, InputItemID_##m, n }

#define MC_LETTERS_AND_DIGITS \
    KEY(0x04, A, "A"), KEY(0x05, B, "B"), KEY(0x06, C, "C"), KEY(0x07, D, "D"), \
    KEY(0x08, E, "E"), KEY(0x09, F, "F"), KEY(0x0A, G, "G"), KEY(0x0B, H, "H"), \
    KEY(0x0C, I, "I"), KEY(0x0D, J, "J"), KEY(0x0E, K, "K"), KEY(0x0F, L, "L"), \
    KEY(0x10, M, "M"), KEY(0x11, N, "N"), KEY(0x12, O, "O"), KEY(0x13, P, "P"), \
    KEY(0x14, Q, "Q"), KEY(0x15, R, "R"), KEY(0x16, S, "S"), KEY(0x17, T, "T"), \
    KEY(0x18, U, "U"), KEY(0x19, V, "V"), KEY(0x1A, W, "W"), KEY(0x1B, X, "X"), \
    KEY(0x1C, Y, "Y"), KEY(0x1D, Z, "Z"), \
    KEY(0x1E, 1, "1"), KEY(0x1F, 2, "2"), KEY(0x20, 3, "3"), KEY(0x21, 4, "4"), \
    KEY(0x22, 5, "5"), KEY(0x23, 6, "6"), KEY(0x24, 7, "7"), KEY(0x25, 8, "8"), \
    KEY(0x26, 9, "9"), KEY(0x27, 0, "0")

// Forward Delete (fn-Delete on external keyboards) toggles MAME's UI keys on
// and off, as with MAME's own Scroll Lock. While on, Tab opens MAME's menu.
// Mac laptop keyboards report fn-Delete to OpenEmu as plain Delete, so the
// menu also has its own control (F9 by default) and a Display Mode item.
#define MC_UI_TOGGLE KEY(0x4C, SCRLOCK, "Toggle MAME UI (Forward Delete)")

// Apple //e: MAME's matrix uses the PC layout directly (Open Apple = left
// Alt, Solid Apple = right Alt, RESET = F12).
static const MCKeyMapping Apple2KeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x29, ESC,        "Esc"),
    KEY(0x2A, BACKSPACE,  "Delete"),
    KEY(0x2B, TAB,        "Tab"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "-"),
    KEY(0x2E, EQUALS,     "="),
    KEY(0x2F, OPENBRACE,  "["),
    KEY(0x30, CLOSEBRACE, "]"),
    KEY(0x31, BACKSLASH,  "\\"),
    KEY(0x32, BACKSLASH2, "Non-US #"),
    KEY(0x33, COLON,      ";"),
    KEY(0x34, QUOTE,      "'"),
    KEY(0x35, TILDE,      "`"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    KEY(0x39, CAPSLOCK,   "Caps Lock"),

    KEY(0x3A, F1, "F1"),  KEY(0x3B, F2, "F2"),  KEY(0x3C, F3, "F3"),  KEY(0x3D, F4, "F4"),
    KEY(0x3E, F5, "F5"),  KEY(0x3F, F6, "F6"),  KEY(0x40, F7, "F7"),  KEY(0x41, F8, "F8"),
    // F9 is left out: it is OpenEmu's default key for the MAME menu control.
    KEY(0x43, F10, "F10"), KEY(0x44, F11, "F11"), KEY(0x45, F12, "F12 (Reset)"),

    MC_UI_TOGGLE,

    KEY(0x4F, RIGHT, "Right"),
    KEY(0x50, LEFT,  "Left"),
    KEY(0x51, DOWN,  "Down"),
    KEY(0x52, UP,    "Up"),

    KEY(0x53, NUMLOCK,   "Clear"),
    KEY(0x54, SLASH_PAD, "Keypad /"),
    KEY(0x55, ASTERISK,  "Keypad *"),
    KEY(0x56, MINUS_PAD, "Keypad -"),
    KEY(0x57, PLUS_PAD,  "Keypad +"),
    KEY(0x58, ENTER_PAD, "Keypad Enter"),
    KEY(0x59, 1_PAD, "Keypad 1"), KEY(0x5A, 2_PAD, "Keypad 2"), KEY(0x5B, 3_PAD, "Keypad 3"),
    KEY(0x5C, 4_PAD, "Keypad 4"), KEY(0x5D, 5_PAD, "Keypad 5"), KEY(0x5E, 6_PAD, "Keypad 6"),
    KEY(0x5F, 7_PAD, "Keypad 7"), KEY(0x60, 8_PAD, "Keypad 8"), KEY(0x61, 9_PAD, "Keypad 9"),
    KEY(0x62, 0_PAD, "Keypad 0"), KEY(0x63, DEL_PAD, "Keypad ."),

    // Both Controls are the IIe's Control key. Option and Command are the
    // Apple keys (left = Open Apple, right = Solid Apple): the original Mac
    // Command key *was* the Apple key.
    KEY(0xE0, LCONTROL, "Control"),
    KEY(0xE1, LSHIFT,   "Left Shift"),
    KEY(0xE2, LALT,     "Open Apple"),
    KEY(0xE3, LALT,     "Open Apple"),
    KEY(0xE4, LCONTROL, "Control"),
    KEY(0xE5, RSHIFT,   "Right Shift"),
    KEY(0xE6, RALT,     "Solid Apple"),
    KEY(0xE7, RALT,     "Solid Apple"),
};

// Commodore 64: MAME places the C64's keys on the PC keys in the same
// physical spot (so "+" is on the Mac's "-", "@" on "[", and so on) and puts
// the special keys on PC-only keys, which are moved here to keys a Mac has.
static const MCKeyMapping C64KeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x29, HOME,       "RUN/STOP (Esc)"),
    KEY(0x2A, BACKSPACE,  "INST/DEL (Delete)"),
    KEY(0x2B, TAB,        "CTRL (Tab)"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "+ (-)"),
    KEY(0x2E, EQUALS,     "- (=)"),
    KEY(0x2F, OPENBRACE,  "@ ([)"),
    KEY(0x30, CLOSEBRACE, "* (])"),
    KEY(0x31, BACKSLASH,  "= (\\)"),
    KEY(0x32, BACKSLASH2, "Pound (Non-US #)"),
    KEY(0x33, COLON,      ": (;)"),
    KEY(0x34, QUOTE,      "; (')"),
    KEY(0x35, TILDE,      "Left Arrow (`)"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    KEY(0x39, CAPSLOCK,   "SHIFT LOCK (Caps Lock)"),

    // F1..F8 as printed on the C64: odd keys alone, even keys with Shift.
    KEY   (0x3A, F1,         "F1"),
    KEYMOD(0x3B, F1, LSHIFT, "F2"),
    KEY   (0x3C, F2,         "F3"),
    KEYMOD(0x3D, F2, LSHIFT, "F4"),
    KEY   (0x3E, F3,         "F5"),
    KEYMOD(0x3F, F3, LSHIFT, "F6"),
    KEY   (0x40, F4,         "F7"),
    KEYMOD(0x41, F4, LSHIFT, "F8"),

    // The C64's extra keys, on F10-F12 (F9 is the MAME menu control) and on
    // Home/Page Up/End/Page Down for keyboards that have them. fn-arrows on
    // a Mac laptop arrive as plain arrows, so F10-F12 are the ones to use there.
    KEY(0x43, PRTSCR,     "RESTORE (F10)"),
    KEY(0x44, INSERT,     "CLR/HOME (F11)"),
    KEY(0x45, DEL,        "Up Arrow (F12)"),
    KEY(0x4A, INSERT,     "CLR/HOME (Home)"),
    KEY(0x4B, PRTSCR,     "RESTORE (Page Up)"),
    MC_UI_TOGGLE,
    KEY(0x4D, BACKSLASH2, "Pound (End)"),
    KEY(0x4E, DEL,        "Up Arrow (Page Down)"),

    // The C64's two cursor keys go down/right; Shift reverses them.
    KEY   (0x4F, RCONTROL,         "Cursor Right"),
    KEYMOD(0x50, RCONTROL, LSHIFT, "Cursor Left"),
    KEY   (0x51, RALT,             "Cursor Down"),
    KEYMOD(0x52, RALT,     LSHIFT, "Cursor Up"),

    // Control and Tab are CTRL; Option is the Commodore key. Command is left
    // to the Mac (and is joystick fire in "Arrow Keys Control Joystick").
    KEY(0xE0, TAB,    "CTRL (Control)"),
    KEY(0xE1, LSHIFT, "Left Shift"),
    KEY(0xE2, LALT,   "Commodore (Option)"),
    KEY(0xE4, TAB,    "CTRL (Control)"),
    KEY(0xE5, RSHIFT, "Right Shift"),
    KEY(0xE6, LALT,   "Commodore (Option)"),
};

// Apple IIgs: MAME's ADB keyboard is a PC layout too. Command is Open Apple
// and Option is Option, as on the IIgs's own (ADB) keyboard; F12 is RESET.
static const MCKeyMapping Apple2GSKeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x29, ESC,        "Esc"),
    KEY(0x2A, BACKSPACE,  "Delete"),
    KEY(0x2B, TAB,        "Tab"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "-"),
    KEY(0x2E, EQUALS,     "="),
    KEY(0x2F, OPENBRACE,  "["),
    KEY(0x30, CLOSEBRACE, "]"),
    KEY(0x31, BACKSLASH,  "\\"),
    KEY(0x33, COLON,      ";"),
    KEY(0x34, QUOTE,      "'"),
    KEY(0x35, TILDE,      "`"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    KEY(0x39, CAPSLOCK,   "Caps Lock"),
    KEY(0x45, F12,        "RESET (F12)"),

    MC_UI_TOGGLE,

    KEY(0x4F, RIGHT, "Right"),
    KEY(0x50, LEFT,  "Left"),
    KEY(0x51, DOWN,  "Down"),
    KEY(0x52, UP,    "Up"),

    KEY(0x53, NUMLOCK,    "Keypad Clear"),
    KEY(0x54, SLASH_PAD,  "Keypad /"),
    KEY(0x55, ASTERISK,   "Keypad *"),
    KEY(0x56, MINUS_PAD,  "Keypad -"),
    KEY(0x57, PLUS_PAD,   "Keypad +"),
    KEY(0x58, ENTER_PAD,  "Keypad Enter"),
    KEY(0x59, 1_PAD, "Keypad 1"), KEY(0x5A, 2_PAD, "Keypad 2"), KEY(0x5B, 3_PAD, "Keypad 3"),
    KEY(0x5C, 4_PAD, "Keypad 4"), KEY(0x5D, 5_PAD, "Keypad 5"), KEY(0x5E, 6_PAD, "Keypad 6"),
    KEY(0x5F, 7_PAD, "Keypad 7"), KEY(0x60, 8_PAD, "Keypad 8"), KEY(0x61, 9_PAD, "Keypad 9"),
    KEY(0x62, 0_PAD, "Keypad 0"), KEY(0x63, DEL_PAD, "Keypad ."),
    KEY(0x67, EQUALS_PAD, "Keypad ="),

    KEY(0xE0, LCONTROL, "Control"),
    KEY(0xE1, LSHIFT,   "Left Shift"),
    KEY(0xE2, RALT,     "Option"),
    KEY(0xE3, LALT,     "Open Apple (Command)"),
    KEY(0xE4, LCONTROL, "Control"),
    KEY(0xE5, RSHIFT,   "Right Shift"),
    KEY(0xE6, RALT,     "Option"),
    KEY(0xE7, LALT,     "Open Apple (Command)"),
};

// Commodore 128: the C64 layout plus the C128's own keys. The C128 has real
// cursor keys (they work in C128 mode), a keypad, and ESC, TAB, ALT, HELP,
// NO SCROLL and 40/80 DISPLAY, which MAME puts on F5-F12.
static const MCKeyMapping C128KeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x29, HOME,       "RUN/STOP (Esc)"),
    KEY(0x2A, BACKSPACE,  "INST/DEL (Delete)"),
    KEY(0x2B, F6,         "TAB (Tab)"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "+ (-)"),
    KEY(0x2E, EQUALS,     "- (=)"),
    KEY(0x2F, OPENBRACE,  "@ ([)"),
    KEY(0x30, CLOSEBRACE, "* (])"),
    KEY(0x31, BACKSLASH,  "= (\\)"),
    KEY(0x32, BACKSLASH2, "Pound (Non-US #)"),
    KEY(0x33, COLON,      ": (;)"),
    KEY(0x34, QUOTE,      "; (')"),
    KEY(0x35, TILDE,      "Left Arrow (`)"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    KEY(0x39, CAPSLOCK,   "SHIFT LOCK (Caps Lock)"),

    KEY   (0x3A, F1,         "F1"),
    KEYMOD(0x3B, F1, LSHIFT, "F2"),
    KEY   (0x3C, F2,         "F3"),
    KEYMOD(0x3D, F2, LSHIFT, "F4"),
    KEY   (0x3E, F3,         "F5"),
    KEYMOD(0x3F, F3, LSHIFT, "F6"),
    KEY   (0x40, F4,         "F7"),
    KEYMOD(0x41, F4, LSHIFT, "F8"),

    KEY(0x43, PRTSCR,     "RESTORE (F10)"),
    KEY(0x44, INSERT,     "CLR/HOME (F11)"),
    KEY(0x45, DEL,        "Up Arrow (F12)"),
    KEY(0x4A, F5,         "ESC (Home)"),
    KEY(0x4B, F11,        "40/80 DISPLAY (Page Up)"),
    MC_UI_TOGGLE,
    KEY(0x4D, F9,         "HELP (End)"),
    KEY(0x4E, F12,        "NO SCROLL (Page Down)"),

    KEY(0x4F, RIGHT, "Cursor Right"),
    KEY(0x50, LEFT,  "Cursor Left"),
    KEY(0x51, DOWN,  "Cursor Down"),
    KEY(0x52, UP,    "Cursor Up"),

    KEY(0x56, MINUS_PAD,  "Keypad -"),
    KEY(0x57, PLUS_PAD,   "Keypad +"),
    KEY(0x58, ENTER_PAD,  "Keypad Enter"),
    KEY(0x59, 1_PAD, "Keypad 1"), KEY(0x5A, 2_PAD, "Keypad 2"), KEY(0x5B, 3_PAD, "Keypad 3"),
    KEY(0x5C, 4_PAD, "Keypad 4"), KEY(0x5D, 5_PAD, "Keypad 5"), KEY(0x5E, 6_PAD, "Keypad 6"),
    KEY(0x5F, 7_PAD, "Keypad 7"), KEY(0x60, 8_PAD, "Keypad 8"), KEY(0x61, 9_PAD, "Keypad 9"),
    KEY(0x62, 0_PAD, "Keypad 0"), KEY(0x63, DEL_PAD, "Keypad ."),

    // Control is CTRL, left Option the Commodore key, right Option ALT.
    KEY(0xE0, TAB,    "CTRL (Control)"),
    KEY(0xE1, LSHIFT, "Left Shift"),
    KEY(0xE2, LALT,   "Commodore (Option)"),
    KEY(0xE4, TAB,    "CTRL (Control)"),
    KEY(0xE5, RSHIFT, "Right Shift"),
    KEY(0xE6, F7,     "ALT (Right Option)"),
};

// Macintosh Plus: MAME's M0110A keyboard. MAME puts the Mac's Command key
// on the PC's left Control, so the Mac's own Command key is mapped there;
// Option is Option. The Plus keyboard has no Control or Esc key, and its
// keypad has Clear and = where a Mac extended keyboard has them.
static const MCKeyMapping MacKeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x2A, BACKSPACE,  "Backspace (Delete)"),
    KEY(0x2B, TAB,        "Tab"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "-"),
    KEY(0x2E, EQUALS,     "="),
    KEY(0x2F, OPENBRACE,  "["),
    KEY(0x30, CLOSEBRACE, "]"),
    KEY(0x31, BACKSLASH,  "\\"),
    KEY(0x33, COLON,      ";"),
    KEY(0x34, QUOTE,      "'"),
    KEY(0x35, TILDE,      "`"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    KEY(0x39, CAPSLOCK,   "Caps Lock"),

    MC_UI_TOGGLE,

    KEY(0x4F, RIGHT, "Right"),
    KEY(0x50, LEFT,  "Left"),
    KEY(0x51, DOWN,  "Down"),
    KEY(0x52, UP,    "Up"),

    KEY(0x53, NUMLOCK,    "Keypad Clear"),
    KEY(0x54, SLASH_PAD,  "Keypad /"),
    KEY(0x55, ASTERISK,   "Keypad *"),
    KEY(0x56, MINUS_PAD,  "Keypad -"),
    KEY(0x57, PLUS_PAD,   "Keypad +"),
    KEY(0x58, ENTER_PAD,  "Keypad Enter"),
    KEY(0x59, 1_PAD, "Keypad 1"), KEY(0x5A, 2_PAD, "Keypad 2"), KEY(0x5B, 3_PAD, "Keypad 3"),
    KEY(0x5C, 4_PAD, "Keypad 4"), KEY(0x5D, 5_PAD, "Keypad 5"), KEY(0x5E, 6_PAD, "Keypad 6"),
    KEY(0x5F, 7_PAD, "Keypad 7"), KEY(0x60, 8_PAD, "Keypad 8"), KEY(0x61, 9_PAD, "Keypad 9"),
    KEY(0x62, 0_PAD, "Keypad 0"), KEY(0x63, DEL_PAD, "Keypad ."),
    KEY(0x67, EQUALS_PAD, "Keypad ="),

    KEY(0xE1, LSHIFT,   "Shift"),
    KEY(0xE2, LALT,     "Option"),
    KEY(0xE3, LCONTROL, "Command"),
    KEY(0xE5, RSHIFT,   "Shift"),
    KEY(0xE6, RALT,     "Option"),
    KEY(0xE7, LCONTROL, "Command"),
};

// While one of MAME's menus is open the keyboard types PC keys, so the menu
// works the same on every machine: arrows move, Return selects, Esc goes
// back, Tab closes, Delete clears an input assignment.
static const MCKeyMapping MenuKeyMap[] =
{
    MC_LETTERS_AND_DIGITS,

    KEY(0x28, ENTER,      "Return"),
    KEY(0x29, ESC,        "Esc"),
    KEYMOD(0x2A, BACKSPACE, DEL, "Delete"),
    KEY(0x2B, TAB,        "Tab"),
    KEY(0x2C, SPACE,      "Space"),
    KEY(0x2D, MINUS,      "-"),
    KEY(0x2E, EQUALS,     "="),
    KEY(0x2F, OPENBRACE,  "["),
    KEY(0x30, CLOSEBRACE, "]"),
    KEY(0x31, BACKSLASH,  "\\"),
    KEY(0x33, COLON,      ";"),
    KEY(0x34, QUOTE,      "'"),
    KEY(0x35, TILDE,      "`"),
    KEY(0x36, COMMA,      ","),
    KEY(0x37, STOP,       "."),
    KEY(0x38, SLASH,      "/"),
    MC_UI_TOGGLE,
    KEY(0x4A, HOME,       "Home"),
    KEY(0x4B, PGUP,       "Page Up"),
    KEY(0x4D, END,        "End"),
    KEY(0x4E, PGDN,       "Page Down"),
    KEY(0x4F, RIGHT,      "Right"),
    KEY(0x50, LEFT,       "Left"),
    KEY(0x51, DOWN,       "Down"),
    KEY(0x52, UP,         "Up"),
    KEY(0xE0, LCONTROL,   "Control"),
    KEY(0xE1, LSHIFT,     "Left Shift"),
    KEY(0xE2, LALT,       "Option"),
    KEY(0xE4, RCONTROL,   "Right Control"),
    KEY(0xE5, RSHIFT,     "Right Shift"),
    KEY(0xE6, RALT,       "Right Option"),
};

#undef KEY
#undef KEYMOD

// Keys the core holds down to signal the c64_openemu Lua plugin. The C64
// keyboard doesn't use them.
static const InputItemID C64SignalJoystickPort1 = InputItemID_F19;  // held: joystick 1 is in port 1
static const InputItemID C64SignalNoAutostart   = InputItemID_F18;  // held: don't autostart

enum
{
    MCHIDRight     = 0x4F,
    MCHIDLeft      = 0x50,
    MCHIDDown      = 0x51,
    MCHIDUp        = 0x52,
    MCHIDRightAlt  = 0xE6,
    MCHIDRightCmd  = 0xE7,
};

// Joystick direction indices; the Apple II and C64 control enums both start
// Up, Down, Left, Right.
enum { MCDirUp, MCDirDown, MCDirLeft, MCDirRight, MCDirCount };

// Relative mouse movement is latched once per frame (see -latchMouse) so every
// read within a frame sees the same delta, as MAME expects of an OSD.
static const int32_t MCRelativePerPixel = 512;  // MAME's INPUT_RELATIVE_PER_PIXEL

static int32_t mc_get_state(void *device_internal, void *item_internal)
{
    return *(int32_t *)item_internal;
}

static os_log_t OE_CORE_LOG;

#pragma mark - Machines and media

typedef struct
{
    NSString *driver;
    NSString *label;
} MCMachine;

static NSArray<NSValue *> *MCMachinesFor(MCSystem system);
static NSSet<NSString *> *MCMacDiskExtensions(void);

/*! A game's disk images: the launched file plus sibling images in the same
 *  folder that share its name apart from a disk/side marker, e.g.
 *  "Ultima IV (Disk 1 of 4 Side A).woz", "Ultima IV (Disk 1 of 4 Side B).woz". */
@interface MCDiskSet : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *paths;
@property (nonatomic, readonly) NSArray<NSString *> *labels;
@property (nonatomic, readonly) NSUInteger launchedIndex;
/*! Stable name shared by every disk of the set; used for per-game settings. */
@property (nonatomic, readonly) NSString *settingsName;
+ (instancetype)diskSetForPath:(NSString *)path extensions:(NSSet<NSString *> *)extensions;
@end

#pragma mark - Core

@interface MAMEComputersGameCore () <OEApple2SystemResponderClient, OEApple2GSSystemResponderClient,
                                     OEC64SystemResponderClient, OEC128SystemResponderClient,
                                     OEMacSystemResponderClient>
{
    MCSystem _system;

    // input state read by MAME through mc_get_state
    int32_t _keys[InputItemID_ABSOLUTE_MAXIMUM];
    int32_t _axes[MCMaxPlayers][2];
    int32_t _buttons[MCMaxPlayers][2];
    int32_t _extras[MCMaxPlayers][MCExtraButtons];

    // raw input, combined into the above
    BOOL    _hidDown[256];
    BOOL    _resetHeld;                          // Apple II Control-Reset binding
    CGFloat _stick[MCMaxPlayers][MCDirCount];    // gamepad deflection 0...1
    BOOL    _padButton[MCMaxPlayers][2];         // gamepad buttons (Apple: 0/1; C64: fire)
    BOOL    _jumpHeld[MCMaxPlayers];             // C64 "Jump" (joystick up)

    // MAME menu. Requests come from other threads and are carried out on the
    // emulation thread, between frames.
    BOOL _menuMode;                  // keyboard is typing PC keys for the menu
    volatile BOOL _menuToggleRequested;
    volatile BOOL _menuOpenRequested;

    // Apple IIgs mouse: OpenEmu reports pointer positions; they are turned
    // into movement, accumulated between frames and latched for MAME.
    os_unfair_lock _mouseLock;
    double  _mouseAccum[2];      // screen pixels since the last latch
    int32_t _mouseDelta[2];      // this frame's movement, MAME units
    int32_t _mouseButtons[2];
    BOOL    _hostMouseDown;      // the Mac's own (left) mouse button
    BOOL    _padMouseDown;       // a control bound to Mac "Mouse Button"
    BOOL    _mouseHasLast;
    OEIntPoint _mouseLast;

    BOOL _screenPending;         // C128: apply the Screen setting once running

    uint32_t  *_buffer;
    OEIntSize  _bufferSize;
    OEIntRect  _screenRect;
    OEIntSize  _aspectSize;
    NSTimeInterval _frameInterval;

    OSD *_osd;
    BOOL _supportsRewinding;
    BOOL _machineRunning;   // NO after a failed restart; frames are skipped

    NSString  *_launchPath;
    BOOL       _launchedFromDisk;
    BOOL       _eightBitDisk, _eightBitDiskChecked;  // see iigsRunsAtNormalSpeed
    NSString  *_macStartupDisk;  // this game's copy of the startup disk in drive 1, or nil
    MCDiskSet *_disks;
    NSString  *_drive1Path;    // may be a file inserted from outside the set
    NSInteger  _drive2Index;
    NSString  *_cartridgePath; // C64 cartridge inserted after launch

    NSString *_settingsPath;
    NSString *_gameFolderName;     // this game's name, safe as a folder name
    NSMutableDictionary<NSString *, id> *_settings;

    NSMutableDictionary<NSString *, NSDictionary *> *_cheatList;
}
@end

@implementation MAMEComputersGameCore

#pragma mark - Lifecycle

+ (void)initialize
{
    if (self == [MAMEComputersGameCore class])
    {
        OE_CORE_LOG = os_log_create("org.openemu.MAMEComputers", "");
    }
}

- (instancetype)init
{
    if ((self = [super init]) == nil)
    {
        return nil;
    }

    _bufferSize    = OEIntSizeMake(1024, 1024);
    _frameInterval = 60;
    _screenRect    = OEIntRectMake(0, 0, _bufferSize.width, _bufferSize.height);
    _aspectSize    = OEIntSizeMake(4, 3);
    _drive2Index   = MCDriveEmpty;

    _osd = [OSD shared];
    _osd.delegate = self;

    return self;
}

#pragma mark - System profile

- (BOOL)isCommodore { return _system == MCSystemC64 || _system == MCSystemC128; }
- (BOOL)isC128      { return _system == MCSystemC128; }
- (BOOL)isApple2GS  { return _system == MCSystemApple2GS; }
- (BOOL)isMac       { return _system == MCSystemMac; }
/*! Machines driven with the Mac's pointer: the IIgs and the Macintosh. */
- (BOOL)hasMouse    { return self.isApple2GS || self.isMac; }
/*! The Apple II family (IIe and IIgs systems), which has the game port. */
- (BOOL)isApple2Family { return _system == MCSystemApple2 || _system == MCSystemApple2GS; }

- (NSString *)systemFolderName
{
    switch (_system)
    {
        case MCSystemApple2GS: return @"Apple IIgs";
        case MCSystemC64:      return @"Commodore 64";
        case MCSystemC128:     return @"Commodore 128";
        case MCSystemMac:      return @"Macintosh";
        default:               return @"Apple IIe";
    }
}

- (NSString *)defaultMachine
{
    // PAL by default for the Commodores, as in VICE: most of their games are
    // European.
    switch (_system)
    {
        case MCSystemApple2GS: return @"apple2gs";
        case MCSystemC64:      return @"c64p";
        case MCSystemC128:     return @"c128p";
        case MCSystemMac:      return @"macplus";
        default:               return @"apple2ee";
    }
}

- (const MCKeyMapping *)keyMap:(size_t *)count
{
    if (_menuMode)
    {
        *count = sizeof(MenuKeyMap) / sizeof(MenuKeyMap[0]);
        return MenuKeyMap;
    }
    return [self machineKeyMap:count];
}

- (const MCKeyMapping *)machineKeyMap:(size_t *)count
{
#define MC_MAP(m) do { *count = sizeof(m) / sizeof(m[0]); return m; } while (0)
    switch (_system)
    {
        case MCSystemApple2GS: MC_MAP(Apple2GSKeyMap);
        case MCSystemC64:      MC_MAP(C64KeyMap);
        case MCSystemC128:     MC_MAP(C128KeyMap);
        case MCSystemMac:      MC_MAP(MacKeyMap);
        default:               MC_MAP(Apple2KeyMap);
    }
#undef MC_MAP
}

- (NSSet<NSString *> *)diskExtensions
{
    // Keep in sync with OEFileSuffixes in the system plugins.
    switch (_system)
    {
        case MCSystemApple2GS:
            // 3.5" disks, plus 5.25" ones for a IIgs game on 5.25" disks
            return [NSSet setWithObjects:@"2mg", @"po", @"woz", @"dc", @"dc42", @"dsk", @"do", @"nib", nil];
        case MCSystemC64:
        case MCSystemC128:
            return [NSSet setWithObjects:@"d64", @"g64", @"x64", @"d71", @"d81", nil];
        case MCSystemMac:
            return MCMacDiskExtensions();
        default:
            return [NSSet setWithObjects:@"dsk", @"do", @"po", @"nib", @"woz", nil];
    }
}

/*! YES for a 5.25" Apple disk image, NO for a 3.5" one. */
static BOOL MCIsFiveInchAppleDisk(NSString *path)
{
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"dsk"] || [ext isEqualToString:@"do"] || [ext isEqualToString:@"nib"])
        return YES;

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [fh readDataOfLength:32];
    [fh closeFile];
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];

    if ([ext isEqualToString:@"po"])
        return size <= 143360;
    if ([ext isEqualToString:@"woz"] && head.length >= 22)
    {
        const uint8_t *b = (const uint8_t *)head.bytes;
        BOOL info = memcmp(b + 12, "INFO", 4) == 0;
        return !(info && b[21] == 2);   // disk type 2 is 3.5"
    }
    return NO; // .2mg, DiskCopy: 3.5"
}

#pragma mark - Macintosh startup disk

static NSSet<NSString *> *MCMacDiskExtensions(void)
{
    // Keep in sync with OEFileSuffixes in the Macintosh system plugin.
    return [NSSet setWithObjects:@"dsk", @"img", @"image", @"dc", @"dc42", @"diskcopy", @"moof", nil];
}

/*! YES when a Mac floppy image starts with boot blocks (the "LK" signature),
 *  so the Mac can start up from it. Raw images (.dsk, .img, .image) begin
 *  with the disk's first block; DiskCopy 4.2 images after an 84-byte header.
 *  MOOF images are bit-level copies that would need decoding: assumed
 *  bootable. */
static BOOL MCMacDiskIsBootable(NSString *path)
{
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"moof"])
        return YES;

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (fh == nil)
        return YES;  // let MAME report the problem
    NSData *head = [fh readDataOfLength:84 + 2];
    [fh closeFile];
    if (head.length < 2)
        return YES;

    const uint8_t *b = (const uint8_t *)head.bytes;
    // DiskCopy 4.2: name length < 64 at 0, magic 0x0100 at 0x52.
    BOOL diskCopy = head.length >= 86 && b[0] < 64 && b[0x52] == 0x01 && b[0x53] == 0x00;
    const uint8_t *data = diskCopy ? b + 84 : b;
    return data[0] == 'L' && data[1] == 'K';
}

/*! Where the user keeps the System disk the Mac starts up from when a game's
 *  own disk can't: <core support folder>/Startup Disks/Macintosh. */
- (NSString *)macStartupDiskFolder
{
    return [[self.supportDirectoryPath stringByAppendingPathComponent:@"Startup Disks"]
            stringByAppendingPathComponent:@"Macintosh"];
}

/*! The startup disk to put in drive 1 for this game, or nil to start up
 *  from the game's own disk. "auto" (the default) uses it only when the
 *  game's disk has no boot blocks; "always" and "never" force the choice.
 *  The disk is the first image in the startup disk folder, by name. Decided
 *  when the machine starts (see -startMachineWithError:). */
- (NSString *)chooseMacStartupDisk
{
    if (!self.isMac || !_launchedFromDisk)
        return nil;

    id setting = _settings[MCSettingStartupDisk];
    NSString *mode = [setting isKindOfClass:[NSString class]] ? setting : @"auto";
    if ([mode isEqualToString:@"never"])
        return nil;
    if ([mode isEqualToString:@"auto"] && MCMacDiskIsBootable(_launchPath))
        return nil;

    NSString *folder = self.macStartupDiskFolder;
    NSArray<NSString *> *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil]
                                  sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names)
    {
        if ([name hasPrefix:@"."])
            continue;  // Finder's ._ files and the like
        if ([MCMacDiskExtensions() containsObject:name.pathExtension.lowercaseString])
            return [self perGameCopyOfStartupDisk:[folder stringByAppendingPathComponent:name]];
    }
    return nil;
}

/*! The Mac writes to the disk it starts up from, so each game gets its own
 *  copy of the startup disk (kept in sync with the original when that is
 *  replaced): games can't spoil it for each other, and a save state always
 *  finds the disk as it left it. */
- (NSString *)perGameCopyOfStartupDisk:(NSString *)original
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *folder = [[[self.supportDirectoryPath stringByAppendingPathComponent:@"Startup Disks"]
                         stringByAppendingPathComponent:@"Macintosh Copies"]
                        stringByAppendingPathComponent:_gameFolderName];
    NSString *copy = [folder stringByAppendingPathComponent:original.lastPathComponent];

    NSDate *originalDate = [[fm attributesOfItemAtPath:original error:nil] fileModificationDate];
    NSDate *markerDate = [[fm attributesOfItemAtPath:[copy stringByAppendingString:@".source-date"] error:nil] fileModificationDate];
    BOOL current = [fm fileExistsAtPath:copy] && originalDate && markerDate && [markerDate isEqualToDate:originalDate];
    if (current)
        return copy;

    NSError *error = nil;
    [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtPath:copy error:nil];
    if (![fm copyItemAtPath:original toPath:copy error:&error])
    {
        os_log_error(OE_CORE_LOG, "could not copy the startup disk for this game (%{public}@); using the original", error);
        return original;
    }
    // Remembers which version of the original the copy came from.
    NSString *marker = [copy stringByAppendingString:@".source-date"];
    [fm createFileAtPath:marker contents:[NSData data] attributes:nil];
    if (originalDate)
        [fm setAttributes:@{ NSFileModificationDate: originalDate } ofItemAtPath:marker error:nil];
    return copy;
}

/*! MAME image devices for the disk drives, drive 1 first. */
- (NSArray<NSString *> *)driveDevices
{
    switch (_system)
    {
        case MCSystemApple2GS:
            // Two 5.25" drives (flop1, flop2) and two 3.5" drives (flop3,
            // flop4); a disk set uses the pair that fits the launched disk.
            return MCIsFiveInchAppleDisk(_launchPath) ? @[ @"flop1", @"flop2" ] : @[ @"flop3", @"flop4" ];
        case MCSystemC64:
        case MCSystemC128:
            return @[ @"flop" ];
        case MCSystemMac:
            // With a startup disk in drive 1, the game's disks go in drive 2.
            return _macStartupDisk ? @[ @"flop2" ] : @[ @"flop1", @"flop2" ];
        default:
            return @[ @"flop1", @"flop2" ];
    }
}

/*! MAME options that put `path` in the right device, slot options first. */
- (NSArray<NSArray<NSString *> *> *)mediaOptionsForPath:(NSString *)path
{
    NSString *ext = path.pathExtension.lowercaseString;
    if (self.isApple2GS)
    {
        return @[ @[ MCIsFiveInchAppleDisk(path) ? @"flop1" : @"flop3", path ] ];
    }
    if (self.isMac)
    {
        if (_macStartupDisk)
            return @[ @[ @"flop1", _macStartupDisk ], @[ @"flop2", path ] ];
        return @[ @[ @"flop1", path ] ];
    }
    if (!self.isCommodore)
    {
        return @[ @[ self.driveDevices[0], path ] ];
    }

    // The C64's 1541 reads .d64/.g64/.x64; .d71 needs a 1571 (the C128's own
    // drive) and .d81 a 1581.
    if ([ext isEqualToString:@"d71"] && !self.isC128)
        return @[ @[ @"iec8", @"c1571" ], @[ @"flop", path ] ];
    if ([ext isEqualToString:@"d81"])
        return @[ @[ @"iec8", @"c1581" ], @[ @"flop", path ] ];
    if ([ext isEqualToString:@"prg"] || [ext isEqualToString:@"p00"] || [ext isEqualToString:@"t64"])
        return @[ @[ @"quik", path ] ];
    if ([ext isEqualToString:@"crt"])
        return @[ @[ @"cart", path ] ];
    if ([ext isEqualToString:@"tap"])
        return @[ @[ @"cass", path ] ];
    return @[ @[ @"flop", path ] ];
}

#pragma mark - Settings

- (BOOL)boolSetting:(NSString *)key fallback:(BOOL)fallback
{
    id value = _settings[key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

- (BOOL)joystickConnected    { return [self boolSetting:MCSettingJoystick fallback:YES]; }
- (BOOL)arrowKeysAreJoystick { return [self boolSetting:MCSettingArrowKeys fallback:NO]; }
- (BOOL)autostart            { return [self boolSetting:MCSettingAutostart fallback:YES]; }

/*! YES when the running machine is a IIgs (the IIgs system, or an Apple IIe
 *  game whose Machine is set to the IIgs). */
- (BOOL)machineIsIIgs
{
    return [self.machine hasPrefix:@"apple2gs"];
}

/*! Apple IIe software reads the joystick with timing loops written for a
 *  1 MHz CPU; at the IIgs's 2.8 MHz they read the stick as pushed far
 *  right/down, as on a real IIgs set to Fast (and the game itself runs
 *  nearly three times too fast). So Apple IIe games and 5.25" disks default
 *  to Normal speed; 3.5" software (IIgs, or 8-bit made for the IIc Plus and
 *  IIgs) to Fast. */
- (BOOL)iigsRunsAtNormalSpeed
{
    id value = _settings[MCSettingIIgsSpeed];
    if ([value isKindOfClass:[NSString class]])
        return [value isEqualToString:@"normal"];
    if (_system == MCSystemApple2)
        return YES;
    if (!_launchedFromDisk)
        return NO;
    if (!_eightBitDiskChecked)
    {
        // Only 5.25" disks: 8-bit games on 3.5" disks were made for the
        // IIc Plus and IIgs and can expect their speed (Rampage reads its
        // joystick wrongly at 1 MHz).
        _eightBitDisk = MCIsFiveInchAppleDisk(_launchPath);
        _eightBitDiskChecked = YES;
    }
    return _eightBitDisk;
}

/*! The IIgs's speed and joystick timing settings (see MCIIgsConfigPort). */
- (void)applyIIgsSettings
{
    // Other Apple II machines use the same bits of their a2_config port for
    // something else, so the settings are only ever sent to a IIgs.
    if (!self.machineIsIIgs)
    {
        [_osd removeConfigPort:MCIIgsConfigPort mask:MCIIgsNormalSpeed];
        [_osd removeConfigPort:MCIIgsConfigPort mask:MCIIgsJoystickFix];
        [_osd removeConfigPort:MCIIgsConfigPort mask:MCIIgsJoystickRange];
        return;
    }
    uint32_t rangeStep = (uint32_t)((100 - self.joystickRange) / 10);
    BOOL normal = self.iigsRunsAtNormalSpeed;
    BOOL fix = [self.requestedPlugins containsObject:MCPluginApple2JoystickFix];
    [_osd setConfigPort:MCIIgsConfigPort mask:MCIIgsNormalSpeed value:(normal ? MCIIgsNormalSpeed : 0)];
    [_osd setConfigPort:MCIIgsConfigPort mask:MCIIgsJoystickFix value:(fix ? MCIIgsJoystickFix : 0)];
    [_osd setConfigPort:MCIIgsConfigPort mask:MCIIgsJoystickRange value:(rangeStep << 5)];
}

/*! The IIgs's Joystick Range, in percent: 100, 90, ... 50. */
- (NSInteger)joystickRange
{
    id value = _settings[MCSettingJoystickRange];
    NSInteger range = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 100;
    range = (range / 10) * 10;
    return MAX(50, MIN(100, range));
}

- (BOOL)showsEightyColumns
{
    id value = _settings[MCSettingScreen];
    return [value isKindOfClass:[NSString class]] && [value isEqualToString:@"80"];
}

- (NSInteger)joystickPort
{
    id value = _settings[MCSettingJoystickPort];
    return ([value isKindOfClass:[NSNumber class]] && [value integerValue] == 1) ? 1 : 2;
}

- (NSString *)machine
{
    id value = _settings[MCSettingMachine];
    return ([value isKindOfClass:[NSString class]] && [value length] > 0) ? value : self.defaultMachine;
}

- (void)loadSettingsNamed:(NSString *)settingsName
{
    NSString *root = [self.supportDirectoryPath stringByAppendingPathComponent:@"Game Settings"];
    NSString *name = [[settingsName stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                      stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    _gameFolderName = name;
    NSString *file = [name stringByAppendingPathExtension:@"plist"];
    _settingsPath = [[root stringByAppendingPathComponent:self.systemFolderName] stringByAppendingPathComponent:file];

    // Apple IIe settings from before the C64 was added sit directly in Game Settings.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *legacy = [root stringByAppendingPathComponent:file];
    if (_system == MCSystemApple2 && ![fm fileExistsAtPath:_settingsPath] && [fm fileExistsAtPath:legacy])
    {
        [fm createDirectoryAtPath:[_settingsPath stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm moveItemAtPath:legacy toPath:_settingsPath error:NULL];
    }

    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:_settingsPath];
    _settings = saved ? [saved mutableCopy] : [NSMutableDictionary new];
}

- (void)setSetting:(id)value forKey:(NSString *)key
{
    _settings[key] = value;

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[_settingsPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:&error];
    if (![_settings writeToURL:[NSURL fileURLWithPath:_settingsPath] error:&error])
    {
        os_log_error(OE_CORE_LOG, "could not save game settings to %{public}@: %{public}@", _settingsPath, error);
    }
}

#pragma mark - OSDDelegate

- (void)didInitialize
{
    // Called by MAME each time a machine starts (including restarts), so the
    // input devices are re-created for every new machine.

    for (int player = 0; player < MCMaxPlayers; player++)
    {
        NSString *name = [NSString stringWithFormat:@"OpenEmu Joystick %d", player + 1];
        InputDevice *dev = [_osd.joystick addDeviceNamed:name];
        [dev addItemNamed:@"X Axis"   id:InputItemID_XAXIS   getter:mc_get_state context:&_axes[player][0]];
        [dev addItemNamed:@"Y Axis"   id:InputItemID_YAXIS   getter:mc_get_state context:&_axes[player][1]];
        [dev addItemNamed:@"Button 1" id:InputItemID_BUTTON1 getter:mc_get_state context:&_buttons[player][0]];
        [dev addItemNamed:@"Button 2" id:InputItemID_BUTTON2 getter:mc_get_state context:&_buttons[player][1]];
        for (int extra = 0; extra < MCExtraButtons; extra++)
        {
            // OpenEmu's "Extra n" controls; MAME calls them Button 3-8.
            [dev addItemNamed:[NSString stringWithFormat:@"Button %d", extra + 3]
                           id:(InputItemID)(InputItemID_BUTTON3 + extra)
                       getter:mc_get_state context:&_extras[player][extra]];
        }
    }

    // A new machine starts with its menus closed, and on its default screen.
    _menuMode = NO;
    _screenPending = self.isC128;

    if (self.hasMouse)
    {
        InputDevice *mouse = [_osd.mouse addDeviceNamed:@"OpenEmu Mouse"];
        [mouse addItemNamed:@"X Axis" id:InputItemID_XAXIS getter:mc_get_state context:&_mouseDelta[0]];
        [mouse addItemNamed:@"Y Axis" id:InputItemID_YAXIS getter:mc_get_state context:&_mouseDelta[1]];
        [mouse addItemNamed:@"Left Button"  id:InputItemID_BUTTON1 getter:mc_get_state context:&_mouseButtons[0]];
        [mouse addItemNamed:@"Right Button" id:InputItemID_BUTTON2 getter:mc_get_state context:&_mouseButtons[1]];
    }

    InputDevice *kb = [_osd.keyboard addDeviceNamed:@"OpenEmu Keyboard"];
    BOOL added[InputItemID_ABSOLUTE_MAXIMUM] = { NO };

    // Every key either map can press: the machine's, then the menu's.
    size_t machineCount = 0, menuCount = sizeof(MenuKeyMap) / sizeof(MenuKeyMap[0]);
    const MCKeyMapping *machineMap = [self machineKeyMap:&machineCount];
    const MCKeyMapping *maps[] = { machineMap, MenuKeyMap };
    size_t counts[] = { machineCount, menuCount };

    for (int m = 0; m < 2; m++)
    {
        for (size_t i = 0; i < counts[m]; i++)
        {
            InputItemID item = maps[m][i].item;
            if (added[item])
            {
                continue; // several Mac keys can share one emulated key
            }
            added[item] = YES;
            [kb addItemNamed:@(maps[m][i].name) id:item getter:mc_get_state context:&_keys[item]];
        }
    }

    // Keys only ever pressed as another key's modifier.
    for (int m = 0; m < 2; m++)
    {
        for (size_t i = 0; i < counts[m]; i++)
        {
            InputItemID mod = maps[m][i].mod;
            if (mod != InputItemID_INVALID && !added[mod])
            {
                added[mod] = YES;
                [kb addItemNamed:(mod == InputItemID_DEL ? @"Delete" : @"Shift") id:mod
                          getter:mc_get_state context:&_keys[mod]];
            }
        }
    }

    if (self.isCommodore)
    {
        [kb addItemNamed:@"OpenEmu: joystick 1 in port 1" id:C64SignalJoystickPort1
                  getter:mc_get_state context:&_keys[C64SignalJoystickPort1]];
        [kb addItemNamed:@"OpenEmu: autostart off" id:C64SignalNoAutostart
                  getter:mc_get_state context:&_keys[C64SignalNoAutostart]];
        [self updateC64Signals];
    }
}

- (void)didChangeDisplayBounds:(NSSize)bounds fps:(double)fps aspect:(NSSize)aspect
{
    _screenRect = OEIntRectMake(0, 0, (int)bounds.width, (int)bounds.height);
    CGFloat height = (aspect.height / aspect.width) * bounds.width;
    _aspectSize = OEIntSizeMake((int)bounds.width, (int)height);
    _frameInterval = fps;
}

- (void)updateAudioBuffer:(const int16_t *)buffer samples:(NSInteger)samples
{
    id<OEAudioBuffer> buf = [self audioBufferAtIndex:0];
    [buf write:buffer maxLength:samples * 2 * sizeof(int16_t)];
}

- (void)logLevel:(OSDLogLevel)level message:(NSString *)msg
{
    switch (level)
    {
        case OSDLogLevelError:
            os_log_error(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
        case OSDLogLevelVerbose:
        case OSDLogLevelDebug:
            os_log_debug(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
        default:
            os_log_info(OE_CORE_LOG, "%{public}s", msg.UTF8String);
            break;
    }
}

#pragma mark - Loading

- (NSString *)romSearchPath
{
    // MAME looks for the machine's ROM zips (apple2ee.zip, c64.zip, ...) here.
    NSString *coreROMs = [self.supportDirectoryPath stringByAppendingPathComponent:@"roms"];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if (self.biosDirectoryPath.length > 0)
    {
        [paths addObject:self.biosDirectoryPath];
    }
    [paths addObject:coreROMs];
    return [paths componentsJoinedByString:@";"];
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    NSDictionary<NSString *, NSNumber *> *systems = @{
        MCSystemIdentifierApple2:   @(MCSystemApple2),
        MCSystemIdentifierApple2GS: @(MCSystemApple2GS),
        MCSystemIdentifierC64:      @(MCSystemC64),
        MCSystemIdentifierC128:     @(MCSystemC128),
        MCSystemIdentifierMac:      @(MCSystemMac),
    };
    _system = (MCSystem)(systems[self.systemIdentifier] ?: @(MCSystemApple2)).integerValue;
    _launchPath = path;
    _launchedFromDisk = [self.diskExtensions containsObject:path.pathExtension.lowercaseString];

    _disks = [MCDiskSet diskSetForPath:path extensions:(_launchedFromDisk ? self.diskExtensions : [NSSet set])];
    _drive1Path  = _disks.paths[_disks.launchedIndex];
    _drive2Index = MCDriveEmpty;

    [self loadSettingsNamed:_disks.settingsName];

    if (self.isMac)
    {
        // Made up front so it's there to find; see -chooseMacStartupDisk.
        [[NSFileManager defaultManager] createDirectoryAtPath:self.macStartupDiskFolder
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }

    os_log_info(OE_CORE_LOG, "loading %{public}@ on %{public}@ (%lu disk(s) in set), machine %{public}@, settings %{public}@",
                path.lastPathComponent, self.systemIdentifier, (unsigned long)_disks.paths.count, self.machine, _settingsPath);

    NSError *startError = nil;
    if (![self startMachineWithError:&startError])
    {
        // OpenEmu shows its own generic message, so this log is where the reason is.
        os_log_error(OE_CORE_LOG, "could not start: %{public}@ %{public}@",
                     startError.localizedDescription, startError.localizedRecoverySuggestion ?: @"");
        if (error)
        {
            *error = startError;
        }
        return NO;
    }
    return YES;
}

/*! Selects the driver, applies every option and boots. Used for the first
 *  boot and for restarts after a setting that changes the hardware. */
- (BOOL)startMachineWithError:(NSError **)error
{
    Options *opts = _osd.options;
    [opts setBasePath:self.supportDirectoryPath];
    // MAME's own settings (input assignments, DIP switches, machine
    // configuration, made in MAME's menu) are kept per game, so a key bound
    // for one game doesn't change another.
    opts.CFGDirectory = [[[self.supportDirectoryPath stringByAppendingPathComponent:@"cfg"]
                          stringByAppendingPathComponent:self.systemFolderName]
                         stringByAppendingPathComponent:_gameFolderName];
    opts.romsPath = [self romSearchPath];
    opts.cheat = NO;
    opts.autoStretchXY = NO;
    opts.unevenStretchX = NO;
    opts.unevenStretchY = NO;
    opts.unevenStretch = NO;
    opts.keepAspect = YES;
    _osd.verboseOutput = NO;

    // Before any media option: it decides which drive the game goes in.
    _macStartupDisk = [self chooseMacStartupDisk];
    if (_macStartupDisk)
        os_log_info(OE_CORE_LOG, "starting up from %{public}@ with the game in drive 2", _macStartupDisk);
    else if (self.isMac && _launchedFromDisk && !MCMacDiskIsBootable(_launchPath))
        os_log_info(OE_CORE_LOG, "the game's disk has no boot blocks; put a System disk in %{public}@",
                    self.macStartupDiskFolder);

    NSString *machine = self.machine;
    AuditResult *audit = nil;
    NSError *driverError = nil;
    if (![_osd setDriver:machine withAuditResult:&audit error:&driverError])
    {
        os_log_error(OE_CORE_LOG, "MAME has no machine \"%{public}@\": %{public}@", machine, driverError);
        if (error)
        {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey: @"Unknown machine.",
                NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:
                    @"\"%@\" is not a machine this core can emulate. Check the \"%@\" entry in:\n\n%@",
                    machine, MCSettingMachine, _settingsPath],
            }];
        }
        return NO;
    }

    if (audit.summary == AuditSummaryIncorrect || audit.summary == AuditSummaryNotFound)
    {
        if (error)
        {
            *error = [self errorForAudit:audit];
        }
        return NO;
    }

    NSMutableArray<NSString *> *rejected = [NSMutableArray array];
    NSError *optionError = nil;
#define MC_SET(value, name) \
    if (![opts setValue:(value) forOptionNamed:(name) error:&optionError]) \
        [rejected addObject:optionError.localizedDescription ?: @"unknown option error"];

    // Esc with MAME's UI keys on asks before "quitting" (which restarts the
    // machine here, since OpenEmu owns the window).
    MC_SET(@"1", @"confirm_quit");

    // Lua plugins. MAME starts them once, with the first machine of this game
    // session, so changes to the list apply the next time the game is opened.
    MC_SET(self.supportDirectoryPath, @"homepath");
    MC_SET(@"1", @"plugins");
    MC_SET(self.pluginOptionValue, @"plugin");

    // The IIgs and the Mac need their mouse; MAME only reads mice when asked to.
    if (self.hasMouse)
    {
        MC_SET(@"1", @"mouse");
    }

    // Slot options come before the media options their cards provide.
    if (self.isCommodore)
    {
        // A joystick in both control ports; the c64_openemu plugin decides
        // which OpenEmu player drives which port.
        MC_SET(@"joy", @"joy1");
        MC_SET(@"joy", @"joy2");
    }
    else if (self.isApple2Family)
    {
        MC_SET(self.joystickConnected ? @"joy" : @"", @"gameio");
    }
    else if (self.isMac)
    {
        // The Mac Plus keyboard (with arrow keys and keypad) on every Mac
        // model, so MacKeyMap fits them all; the 128K and 512Ke otherwise
        // get the original keyboard and keypad.
        MC_SET(@"usp", @"kbd");
    }

    NSDictionary *custom = _settings[MCSettingMAMEOptions];
    if ([custom isKindOfClass:[NSDictionary class]])
    {
        for (NSString *name in custom)
        {
            id value = custom[name];
            if ([name isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]])
            {
                MC_SET(value, name);
            }
        }
    }

    // The launched file (drive 1 holds whatever disk is in it now).
    NSString *mainFile = _launchedFromDisk ? _drive1Path : _launchPath;
    for (NSArray<NSString *> *option in [self mediaOptionsForPath:mainFile])
    {
        if (![opts setValue:option[1] forOptionNamed:option[0] error:&optionError])
        {
            // Without it there is nothing to run.
            if (error)
            {
                *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                    NSLocalizedDescriptionKey: @"Could not insert the game.",
                    NSLocalizedRecoverySuggestionErrorKey: optionError.localizedDescription ?: @"",
                }];
            }
            return NO;
        }
    }

    // (A Mac starting up from a startup disk has its game in drive 2
    // already, and only that drive is listed.)
    if (self.driveDevices.count > 1 && _launchedFromDisk)
    {
        NSString *drive2 = (_drive2Index == MCDriveEmpty) ? @"" : _disks.paths[_drive2Index];
        MC_SET(drive2, self.driveDevices[1]);
    }

    if (self.isCommodore && _cartridgePath != nil)
    {
        MC_SET(_cartridgePath, @"cart");
    }
#undef MC_SET

    for (NSString *message in rejected)
    {
        os_log_error(OE_CORE_LOG, "ignored option: %{public}@", message);
    }

    if (![_osd initializeWithError:error])
    {
        os_log_error(OE_CORE_LOG, "MAME failed to start %{public}@", machine);
        return NO;
    }

    _machineRunning = YES;
    _supportsRewinding = _osd.supportsSave && _osd.stateSize < 1e6;
    [self applyIIgsSettings];

    // A restart drops MAME's pointer to our video buffer; hand it back.
    if (_buffer != NULL)
    {
        [_osd setBuffer:_buffer size:CGSizeFromOEIntSize(_bufferSize)];
    }

    return YES;
}

- (BOOL)restartMachine
{
    _machineRunning = NO;
    [_osd unload];

    NSError *error = nil;
    if (![self startMachineWithError:&error])
    {
        os_log_error(OE_CORE_LOG, "restart failed: %{public}@ %{public}@", error.localizedDescription,
                     error.localizedRecoverySuggestion);
        return NO;
    }
    return YES;
}

- (NSError *)errorForAudit:(AuditResult *)audit
{
    NSMutableOrderedSet<NSString *> *missing = [NSMutableOrderedSet orderedSet];
    GameDriver *driver = _osd.driver;

    for (AuditRecord *record in audit.records)
    {
        switch (record.substatus)
        {
            case AuditSubstatusNotFound:
            case AuditSubstatusFoundBadChecksum:
            case AuditSubstatusFoundWrongLength:
            {
                // ROMs belonging to a device (e.g. a disk drive) are in that
                // device's own set; the machine's are in its own set, or its
                // parent's for a merged ROM set.
                NSString *set = record.sharedDevice ? record.sharedDevice.shortName : driver.name;
                if (record.sharedDevice == nil && driver.parent.length > 0)
                {
                    set = [NSString stringWithFormat:@"%@ (or %@)", set, driver.parent];
                }
                [missing addObject:set];
                break;
            }
            default:
                break;
        }
    }

    NSMutableString *list = [NSMutableString string];
    for (NSString *set in missing)
    {
        [list appendFormat:@"  • %@.zip\n", set];
    }

    NSString *suggestion = [NSString stringWithFormat:
        @"%@ needs these ROM sets from a MAME 0.250-compatible ROM set:\n\n%@\n"
        @"Copy the .zip files, unchanged, into:\n\n%@",
        driver.fullName ?: @"This machine", list, self.biosDirectoryPath ?: @"the OpenEmu BIOS folder"];

    return [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
        NSLocalizedDescriptionKey: @"System ROMs are missing.",
        NSLocalizedRecoverySuggestionErrorKey: suggestion,
    }];
}

- (void)resetEmulation
{
    // A cold boot, like power-cycling the machine, with the current media.
    [self restartMachine];
}

#pragma mark - Plugins

static NSArray<NSString *> *MCNameList(id value)
{
    NSArray *items = nil;
    if ([value isKindOfClass:[NSArray class]])
    {
        items = value;
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        items = [value componentsSeparatedByString:@","];
    }

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id item in items)
    {
        if (![item isKindOfClass:[NSString class]])
        {
            continue;
        }
        NSString *name = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0)
        {
            [names addObject:name];
        }
    }
    return names;
}

- (NSString *)pluginsDirectory
{
    return [self.supportDirectoryPath stringByAppendingPathComponent:@"plugins"];
}

- (BOOL)pluginIsInstalled:(NSString *)name
{
    NSString *manifest = [[self.pluginsDirectory stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"plugin.json"];
    return [[NSFileManager defaultManager] fileExistsAtPath:manifest];
}

/*! Plugins a system needs to work as intended here. */
- (NSArray<NSString *> *)requiredPlugins
{
    return self.isCommodore ? @[ MCPluginC64 ] : @[];
}

/*! Plugins for every game: Global Settings.plist's MAMEPlugins, or the
 *  Apple II joystick fix when that file doesn't say. Plugins check which
 *  machine they are running on, so one list serves both systems. */
- (NSArray<NSString *> *)defaultPlugins
{
    NSString *path = [self.supportDirectoryPath stringByAppendingPathComponent:@"Global Settings.plist"];
    NSDictionary *global = [NSDictionary dictionaryWithContentsOfFile:path];
    id list = global[MCSettingMAMEPlugins];
    return list ? MCNameList(list) : @[ MCPluginApple2JoystickFix ];
}

/*! Required + defaults + the game's MAMEPlugins, minus its DisabledMAMEPlugins. */
- (NSArray<NSString *> *)requestedPlugins
{
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSetWithArray:self.requiredPlugins];
    [names addObjectsFromArray:self.defaultPlugins];
    [names addObjectsFromArray:MCNameList(_settings[MCSettingMAMEPlugins])];
    [names removeObjectsInArray:MCNameList(_settings[MCSettingDisabledPlugins])];
    return names.array;
}

/*! requestedPlugins as MAME's comma-separated "plugin" option, keeping only
 *  plugins that are installed (an unknown name would otherwise stop MAME
 *  from starting any plugin). */
- (NSString *)pluginOptionValue
{
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (NSString *name in self.requestedPlugins)
    {
        if ([self pluginIsInstalled:name])
        {
            [valid addObject:name];
        }
        else
        {
            os_log_error(OE_CORE_LOG, "MAME plugin \"%{public}@\" is not installed in %{public}@", name, self.pluginsDirectory);
        }
    }

    NSString *boot = [self.pluginsDirectory stringByAppendingPathComponent:@"boot.lua"];
    if (valid.count > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:boot])
    {
        os_log_error(OE_CORE_LOG, "MAME plugins need boot.lua in %{public}@; run Scripts/build-mame-computers-core.sh to install it", self.pluginsDirectory);
    }

    os_log_info(OE_CORE_LOG, "MAME plugins: %{public}@", valid.count ? [valid componentsJoinedByString:@", "] : @"none");
    return [valid componentsJoinedByString:@","];
}

/*! Turns a plugin on or off for this game only. */
- (void)setPlugin:(NSString *)name enabledForGame:(BOOL)enabled
{
    NSMutableArray<NSString *> *added = [MCNameList(_settings[MCSettingMAMEPlugins]) mutableCopy];
    NSMutableArray<NSString *> *disabled = [MCNameList(_settings[MCSettingDisabledPlugins]) mutableCopy];

    [added removeObject:name];
    [disabled removeObject:name];
    BOOL isDefault = [self.defaultPlugins containsObject:name] || [self.requiredPlugins containsObject:name];
    if (enabled && !isDefault)
    {
        [added addObject:name];
    }
    else if (!enabled && isDefault)
    {
        [disabled addObject:name];
    }

    _settings[MCSettingMAMEPlugins] = added;
    [self setSetting:disabled forKey:MCSettingDisabledPlugins];
}

#pragma mark - Disks and media

- (NSUInteger)discCount
{
    return _launchedFromDisk ? _disks.paths.count : 0;
}

- (void)setDisc:(NSUInteger)discNumber
{
    // OpenEmu numbers discs from 1.
    if (_launchedFromDisk && discNumber >= 1 && discNumber <= _disks.paths.count)
    {
        [self insertDiskAtIndex:discNumber - 1 intoDrive:0];
    }
}

- (BOOL)insertDiskAtIndex:(NSUInteger)index intoDrive:(NSUInteger)drive
{
    if (drive >= self.driveDevices.count)
    {
        return NO;
    }

    NSString *path = _disks.paths[index];
    NSError *error = nil;
    if (![_osd loadMediaAtPath:path forDevice:self.driveDevices[drive] error:&error])
    {
        os_log_error(OE_CORE_LOG, "could not insert %{public}@: %{public}@", path.lastPathComponent, error);
        return NO;
    }

    if (drive == 0)
    {
        _drive1Path = path;
    }
    else
    {
        _drive2Index = (NSInteger)index;
    }
    return YES;
}

- (void)insertFileAtURL:(NSURL *)url completionHandler:(void (^)(BOOL, NSError *))block
{
    NSString *path = url.path;
    NSString *ext = path.pathExtension.lowercaseString;
    NSError *error = nil;
    BOOL ok = NO;

    if (self.isCommodore && [ext isEqualToString:@"crt"])
    {
        // A cartridge is only seen at power-on: plug it in and restart.
        _cartridgePath = path;
        ok = [self restartMachine];
    }
    else
    {
        NSString *device = [[self mediaOptionsForPath:path].lastObject firstObject];
        ok = [_osd loadMediaAtPath:path forDevice:device error:&error];
        if (ok && [self.driveDevices.firstObject isEqualToString:device])
        {
            _drive1Path = path;
        }
    }

    if (block)
    {
        block(ok, error);
    }
}

#pragma mark - Display modes (per-game settings menu)

static NSDictionary *MCToggle(NSString *name, NSString *prefKey, BOOL state)
{
    return @{
        OEGameCoreDisplayModeNameKey: name,
        OEGameCoreDisplayModePrefKeyNameKey: prefKey,
        OEGameCoreDisplayModeStateKey: @(state),
        OEGameCoreDisplayModeAllowsToggleKey: @YES,
        OEGameCoreDisplayModeDisallowPrefSaveKey: @YES,
        OEGameCoreDisplayModeManualOnlyKey: @YES,
    };
}

static NSDictionary *MCChoice(NSString *name, NSString *prefKey, NSString *value, BOOL state)
{
    return @{
        OEGameCoreDisplayModeNameKey: name,
        OEGameCoreDisplayModePrefKeyNameKey: prefKey,
        OEGameCoreDisplayModePrefValueNameKey: value,
        OEGameCoreDisplayModeStateKey: @(state),
        OEGameCoreDisplayModeDisallowPrefSaveKey: @YES,
        OEGameCoreDisplayModeManualOnlyKey: @YES,
    };
}

static NSDictionary *MCGroup(NSString *name, NSArray *items)
{
    return @{ OEGameCoreDisplayModeGroupNameKey: name, OEGameCoreDisplayModeGroupItemsKey: items };
}

static NSArray<NSValue *> *MCMachinesFor(MCSystem system)
{
    static MCMachine apple2[] = {
        { @"apple2ee", @"Apple //e (Enhanced)" },
        { @"apple2e",  @"Apple //e (Original)" },
        // The IIgs runs most //e software; its 5.25" drives are flop1/flop2 too.
        { @"apple2gs", @"Apple IIgs (ROM 03)" },
    };
    static MCMachine apple2gs[] = {
        { @"apple2gs",   @"Apple IIgs (ROM 03)" },
        { @"apple2gsr1", @"Apple IIgs (ROM 01)" },
    };
    static MCMachine c64[] = {
        { @"c64p", @"Commodore 64 (PAL)" },
        { @"c64",  @"Commodore 64 (NTSC)" },
    };
    static MCMachine c128[] = {
        { @"c128p", @"Commodore 128 (PAL)" },
        { @"c128",  @"Commodore 128 (NTSC)" },
    };
    static MCMachine mac[] = {
        { @"macplus",  @"Macintosh Plus" },
        { @"mac512ke", @"Macintosh 512Ke" },
        { @"mac128k",  @"Macintosh 128K (400K disks only)" },
    };

    MCMachine *list = apple2;
    size_t count = sizeof(apple2) / sizeof(apple2[0]);
    switch (system)
    {
        case MCSystemApple2GS: list = apple2gs; count = sizeof(apple2gs) / sizeof(apple2gs[0]); break;
        case MCSystemC64:      list = c64;      count = sizeof(c64) / sizeof(c64[0]);           break;
        case MCSystemC128:     list = c128;     count = sizeof(c128) / sizeof(c128[0]);         break;
        case MCSystemMac:      list = mac;      count = sizeof(mac) / sizeof(mac[0]);           break;
        default: break;
    }

    NSMutableArray<NSValue *> *machines = [NSMutableArray array];
    for (size_t i = 0; i < count; i++)
    {
        [machines addObject:[NSValue valueWithPointer:&list[i]]];
    }
    return machines;
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayModes
{
    NSMutableArray *modes = [NSMutableArray array];

    if (self.isCommodore)
    {
        NSInteger port = self.joystickPort;
        [modes addObject:MCGroup(@"Joystick Port", @[
            MCChoice(@"Joystick in Port 2", MCModeJoystickPort, @"2", port == 2),
            MCChoice(@"Joystick in Port 1", MCModeJoystickPort, @"1", port == 1),
        ])];
        [modes addObject:MCToggle(@"Arrow Keys Control Joystick", MCModeArrowKeys, self.arrowKeysAreJoystick)];
        [modes addObject:MCToggle(@"Autostart (next launch)", MCModeAutostart, self.autostart)];
        if (self.isC128)
        {
            BOOL eighty = self.showsEightyColumns;
            [modes addObject:MCGroup(@"Screen", @[
                MCChoice(@"40 Columns", MCModeScreen, @"40", !eighty),
                MCChoice(@"80 Columns", MCModeScreen, @"80", eighty),
            ])];
        }
    }
    else if (self.isMac)
    {
        id setting = _settings[MCSettingStartupDisk];
        NSString *mode = [setting isKindOfClass:[NSString class]] ? setting : @"auto";
        [modes addObject:MCGroup(@"Startup Disk (restarts)", @[
            MCChoice(@"Automatic (when the game's disk can't start up)", MCModeStartupDisk, @"auto", [mode isEqualToString:@"auto"]),
            MCChoice(@"Always Start Up from the Startup Disk", MCModeStartupDisk, @"always", [mode isEqualToString:@"always"]),
            MCChoice(@"Never (start up from the game's disk)", MCModeStartupDisk, @"never", [mode isEqualToString:@"never"]),
        ])];
    }
    else
    {
        [modes addObject:MCToggle(@"Joystick Connected (restarts)", MCModeJoystick, self.joystickConnected)];
        [modes addObject:MCToggle(@"Arrow Keys Control Joystick", MCModeArrowKeys, self.arrowKeysAreJoystick)];
        if (self.machineIsIIgs)
        {
            BOOL normal = self.iigsRunsAtNormalSpeed;
            [modes addObject:MCGroup(@"Speed", @[
                MCChoice(@"Normal (1 MHz, for Apple IIe software)", MCModeIIgsSpeed, @"normal", normal),
                MCChoice(@"Fast (2.8 MHz)", MCModeIIgsSpeed, @"fast", !normal),
            ])];
        }
        BOOL fixOn = [self.requestedPlugins containsObject:MCPluginApple2JoystickFix];
        if (self.machineIsIIgs)
        {
            // Built into the IIgs emulation, so these apply at once.
            [modes addObject:MCToggle(@"Joystick Timing Fix", MCModeJoystickFix, fixOn)];
            NSInteger range = self.joystickRange;
            NSMutableArray *ranges = [NSMutableArray array];
            for (NSInteger r = 100; r >= 50; r -= 10)
            {
                NSString *label = (r == 100) ? @"100% (full)" : [NSString stringWithFormat:@"%ld%%", (long)r];
                [ranges addObject:MCChoice(label, MCModeJoystickRange, [@(r) stringValue], range == r)];
            }
            [modes addObject:MCGroup(@"Joystick Range", ranges)];
        }
        else if (_system == MCSystemApple2 && [self pluginIsInstalled:MCPluginApple2JoystickFix])
        {
            [modes addObject:MCToggle(@"Joystick Timing Fix (next launch)", MCModeJoystickFix, fixOn)];
        }
    }

    NSString *machine = self.machine;
    NSMutableArray *machines = [NSMutableArray array];
    for (NSValue *value in MCMachinesFor(_system))
    {
        MCMachine *m = (MCMachine *)value.pointerValue;
        [machines addObject:MCChoice(m->label, MCModeMachine, m->driver, [machine isEqualToString:m->driver])];
    }
    [modes addObject:MCGroup(@"Machine (restarts)", machines)];

    if (_launchedFromDisk && _disks.paths.count > 1)
    {
        BOOL twoDrives = self.driveDevices.count > 1;
        NSMutableArray *drive1 = [NSMutableArray array];
        NSMutableArray *drive2 = [NSMutableArray array];
        [drive2 addObject:MCChoice(@"Drive 2: Empty", MCModeDrive2, @"-1", _drive2Index == MCDriveEmpty)];

        // What MAME actually has mounted; MAME's File Manager can change it.
        NSString *mounted = [_osd mediaPathForDevice:self.driveDevices[0]] ?: _drive1Path;

        for (NSUInteger i = 0; i < _disks.paths.count; i++)
        {
            NSString *label = _disks.labels[i];
            NSString *value = [NSString stringWithFormat:@"%lu", (unsigned long)i];
            BOOL inDrive1 = [mounted isEqualToString:_disks.paths[i]];
            NSString *name1 = twoDrives ? [NSString stringWithFormat:@"Drive 1: %@", label] : label;
            [drive1 addObject:MCChoice(name1, MCModeDrive1, value, inDrive1)];
            [drive2 addObject:MCChoice([NSString stringWithFormat:@"Drive 2: %@", label], MCModeDrive2, value, _drive2Index == (NSInteger)i)];
        }
        [modes addObject:MCGroup(twoDrives ? @"Drive 1" : @"Disk", drive1)];
        if (twoDrives)
        {
            [modes addObject:MCGroup(@"Drive 2", drive2)];
        }
    }

    [modes addObject:@{ OEGameCoreDisplayModeSeparatorItemKey: @"" }];
    [modes addObject:MCToggle(@"Open MAME Menu", MCModeMAMEMenu, NO)];
    [modes addObject:@{ OEGameCoreDisplayModeSeparatorItemKey: @"" }];
    [modes addObject:@{ OEGameCoreDisplayModeLabelKey: @"Settings are saved for this game" }];

    return modes;
}

- (NSDictionary *)displayModeNamed:(NSString *)name
{
    for (NSDictionary *mode in self.displayModes)
    {
        NSArray *items = mode[OEGameCoreDisplayModeGroupItemsKey] ?: @[ mode ];
        for (NSDictionary *item in items)
        {
            if ([item[OEGameCoreDisplayModeNameKey] isEqualToString:name])
            {
                return item;
            }
        }
    }
    return nil;
}

- (void)changeDisplayWithMode:(NSString *)displayMode
{
    // Runs on the emulation thread, between frames.
    NSDictionary *mode = [self displayModeNamed:displayMode];
    if (mode == nil)
    {
        return;
    }

    NSString *key   = mode[OEGameCoreDisplayModePrefKeyNameKey];
    NSString *value = mode[OEGameCoreDisplayModePrefValueNameKey];
    BOOL      state = [mode[OEGameCoreDisplayModeStateKey] boolValue];

    if ([key isEqualToString:MCModeJoystick])
    {
        [self setSetting:@(!state) forKey:MCSettingJoystick];
        [self restartMachine];
    }
    else if ([key isEqualToString:MCModeJoystickFix])
    {
        // MAME starts plugins once per session, so on the Apple //e this
        // applies the next time the game is opened; the IIgs has it built in.
        [self setPlugin:MCPluginApple2JoystickFix enabledForGame:!state];
        [self applyIIgsSettings];
    }
    else if ([key isEqualToString:MCModeArrowKeys])
    {
        [self setSetting:@(!state) forKey:MCSettingArrowKeys];
        [self releaseArrowKeys];
    }
    else if ([key isEqualToString:MCModeJoystickPort])
    {
        [self setSetting:@(value.integerValue == 1 ? 1 : 2) forKey:MCSettingJoystickPort];
        [self updateC64Signals];
    }
    else if ([key isEqualToString:MCModeStartupDisk] && !state)
    {
        NSString *choice = ([value isEqualToString:@"always"] || [value isEqualToString:@"never"]) ? value : @"auto";
        [self setSetting:choice forKey:MCSettingStartupDisk];
        [self restartMachine];
    }
    else if ([key isEqualToString:MCModeJoystickRange])
    {
        [self setSetting:@(value.integerValue) forKey:MCSettingJoystickRange];
        [self applyIIgsSettings];
    }
    else if ([key isEqualToString:MCModeIIgsSpeed])
    {
        [self setSetting:([value isEqualToString:@"normal"] ? @"normal" : @"fast") forKey:MCSettingIIgsSpeed];
        [self applyIIgsSettings];
    }
    else if ([key isEqualToString:MCModeScreen])
    {
        [self setSetting:([value isEqualToString:@"80"] ? @"80" : @"40") forKey:MCSettingScreen];
        _screenPending = YES;
    }
    else if ([key isEqualToString:MCModeMAMEMenu])
    {
        _menuOpenRequested = YES;
    }
    else if ([key isEqualToString:MCModeAutostart])
    {
        [self setSetting:@(!state) forKey:MCSettingAutostart];
        [self updateC64Signals];
    }
    else if ([key isEqualToString:MCModeMachine])
    {
        if (!state)
        {
            // If the other model can't start (usually its ROM set is
            // missing), fall back to the one that was running.
            NSString *previous = self.machine;
            [self setSetting:value forKey:MCSettingMachine];
            if (![self restartMachine])
            {
                [self setSetting:previous forKey:MCSettingMachine];
                [self restartMachine];
            }
        }
    }
    else if ([key isEqualToString:MCModeDrive1])
    {
        [self insertDiskAtIndex:(NSUInteger)value.integerValue intoDrive:0];
    }
    else if ([key isEqualToString:MCModeDrive2])
    {
        NSInteger index = value.integerValue;
        if (index == MCDriveEmpty)
        {
            [_osd unloadMediaForDevice:self.driveDevices[1]];
            _drive2Index = MCDriveEmpty;
        }
        else
        {
            [self insertDiskAtIndex:(NSUInteger)index intoDrive:1];
        }
    }
}

#pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    _buffer = (uint32_t *)hint;
    [_osd setBuffer:hint size:CGSizeFromOEIntSize(_bufferSize)];
    return _buffer;
}

- (OEIntSize)bufferSize  { return _bufferSize; }
- (OEIntRect)screenRect  { return _screenRect; }
- (OEIntSize)aspectSize  { return _aspectSize; }
- (GLenum)pixelFormat    { return GL_BGRA; }
- (GLenum)pixelType      { return GL_UNSIGNED_INT_8_8_8_8_REV; }

#pragma mark - Execution

- (void)executeFrame
{
    if (!_machineRunning)
    {
        return;
    }

    if (_menuOpenRequested || _menuToggleRequested)
    {
        BOOL toggle = _menuToggleRequested;
        _menuOpenRequested = _menuToggleRequested = NO;
        if (toggle && _osd.menuActive)
            [_osd hideMenu];
        else
            [_osd showMenu];
    }
    [self syncMenuMode];
    [self latchMouse];

    if (_screenPending)
    {
        // Only possible once the machine is running; MAME's saved view (from
        // an earlier session) has been restored by then, so this wins.
        if ([_osd showScreenWithTag:(self.showsEightyColumns ? @"screen80" : @"screen")])
            _screenPending = NO;
    }

    [_osd execute];
}

/*! Switches the keyboard between the machine's layout and plain PC keys when
 *  MAME's menu opens or closes (by any means, including Esc in the menu). */
- (void)syncMenuMode
{
    BOOL active = _osd.menuActive;
    if (active == _menuMode)
    {
        return;
    }
    _menuMode = active;

    // Release everything, then press what is held in the new layout.
    BOOL port1 = _keys[C64SignalJoystickPort1], noAuto = _keys[C64SignalNoAutostart];
    memset(_keys, 0, sizeof(_keys));
    _keys[C64SignalJoystickPort1] = port1;
    _keys[C64SignalNoAutostart] = noAuto;
    for (NSUInteger hid = 0; hid < 256; hid++)
    {
        if (_hidDown[hid])
        {
            [self updateKeyItemsForHID:hid];
        }
    }
    [self updateJoystickForPlayer:0];
}

- (void)stopEmulation
{
    _machineRunning = NO;
    _osd.delegate = nil;
    [_osd unload];
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return _frameInterval;
}

#pragma mark - Audio

- (double)audioSampleRate { return 48000; }
- (NSUInteger)channelCount { return 2; }

#pragma mark - Input: keyboard

- (BOOL)hidKeyIsJoystick:(NSUInteger)hid
{
    if (_menuMode || !self.arrowKeysAreJoystick)
    {
        return NO;
    }
    if (hid == MCHIDUp || hid == MCHIDDown || hid == MCHIDLeft || hid == MCHIDRight)
    {
        return YES;
    }
    // On the C64 the right Option and Command keys are fire.
    return self.isCommodore && (hid == MCHIDRightAlt || hid == MCHIDRightCmd);
}

- (void)updateKeyItem:(InputItemID)item
{
    size_t count = 0;
    const MCKeyMapping *map = [self keyMap:&count];

    BOOL down = NO;
    for (size_t i = 0; i < count && !down; i++)
    {
        if ((map[i].item == item || map[i].mod == item)
            && _hidDown[map[i].hid] && ![self hidKeyIsJoystick:map[i].hid])
        {
            down = YES;
        }
    }

    // Apple II Control-Reset from the gamepad/controls binding.
    if (self.isApple2Family && _resetHeld && (item == InputItemID_LCONTROL || item == InputItemID_F12))
    {
        down = YES;
    }

    _keys[item] = down ? 1 : 0;
}

- (void)updateKeyItemsForHID:(NSUInteger)hid
{
    size_t count = 0;
    const MCKeyMapping *map = [self keyMap:&count];
    for (size_t i = 0; i < count; i++)
    {
        if (map[i].hid == hid)
        {
            [self updateKeyItem:map[i].item];
            if (map[i].mod != InputItemID_INVALID)
            {
                [self updateKeyItem:map[i].mod];
            }
        }
    }
}

- (void)setHIDKey:(NSUInteger)keyCode down:(BOOL)down
{
    if (keyCode >= 256)
    {
        return;
    }
    _hidDown[keyCode] = down;

    if ([self hidKeyIsJoystick:keyCode])
    {
        [self updateJoystickForPlayer:0];
        return;
    }
    [self updateKeyItemsForHID:keyCode];
}

- (void)releaseArrowKeys
{
    // Called when the arrow-key mode flips, so nothing stays stuck on either side.
    NSUInteger keys[] = { MCHIDRight, MCHIDLeft, MCHIDDown, MCHIDUp, MCHIDRightAlt, MCHIDRightCmd };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++)
    {
        _hidDown[keys[i]] = NO;
        [self updateKeyItemsForHID:keys[i]];
    }
    [self updateJoystickForPlayer:0];
}

- (oneway void)keyDown:(NSUInteger)keyCode
{
    [self setHIDKey:keyCode down:YES];
}

- (oneway void)keyUp:(NSUInteger)keyCode
{
    [self setHIDKey:keyCode down:NO];
}

- (void)updateC64Signals
{
    if (!self.isCommodore)
    {
        return;
    }
    _keys[C64SignalJoystickPort1] = (self.joystickPort == 1) ? 1 : 0;
    _keys[C64SignalNoAutostart]   = self.autostart ? 0 : 1;
}

#pragma mark - Input: joysticks

- (void)updateJoystickForPlayer:(NSUInteger)player
{
    if (player >= MCMaxPlayers)
    {
        return;
    }

    CGFloat x = _stick[player][MCDirRight] - _stick[player][MCDirLeft];
    CGFloat y = _stick[player][MCDirDown]  - _stick[player][MCDirUp];
    if (_jumpHeld[player])
    {
        y = -1.0;
    }
    BOOL fire = _padButton[player][0];

    // Arrow keys drive joystick 1 at full deflection when the gamepad is centred.
    if (player == 0 && !_menuMode && self.arrowKeysAreJoystick)
    {
        if (x == 0) x = (CGFloat)_hidDown[MCHIDRight] - (CGFloat)_hidDown[MCHIDLeft];
        if (y == 0) y = (CGFloat)_hidDown[MCHIDDown]  - (CGFloat)_hidDown[MCHIDUp];
        if (self.isCommodore)
        {
            fire = fire || _hidDown[MCHIDRightAlt] || _hidDown[MCHIDRightCmd];
        }
    }

    x = MAX(-1.0, MIN(1.0, x));
    y = MAX(-1.0, MIN(1.0, y));
    _axes[player][0] = (int32_t)(x * InputAbsoluteMax);
    _axes[player][1] = (int32_t)(y * InputAbsoluteMax);
    _buttons[player][0] = fire ? 1 : 0;
    _buttons[player][1] = _padButton[player][1] ? 1 : 0;
}

- (void)setDirection:(NSUInteger)direction value:(CGFloat)value forPlayer:(NSUInteger)player
{
    if (player < 1 || player > MCMaxPlayers || direction >= MCDirCount)
    {
        return;
    }
    _stick[player - 1][direction] = MAX(0.0, MIN(1.0, value));
    [self updateJoystickForPlayer:player - 1];
}

- (void)setPadButton:(NSUInteger)button pressed:(BOOL)pressed forPlayer:(NSUInteger)player
{
    if (player < 1 || player > MCMaxPlayers || button > 1)
    {
        return;
    }
    _padButton[player - 1][button] = pressed;
    [self updateJoystickForPlayer:player - 1];
}

- (void)setExtraButton:(NSUInteger)extra pressed:(BOOL)pressed forPlayer:(NSUInteger)player
{
    if (player < 1 || player > MCMaxPlayers || extra >= MCExtraButtons)
    {
        return;
    }
    _extras[player - 1][extra] = pressed ? 1 : 0;
}

- (void)menuControlPressed:(BOOL)pressed
{
    if (pressed)
    {
        _menuToggleRequested = YES;
    }
}

// Apple II

- (oneway void)didMoveApple2Joystick:(OEApple2Button)direction withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    [self setDirection:direction value:value forPlayer:player];
}

- (oneway void)didPushApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player
{
    [self setApple2Button:button pressed:YES forPlayer:player];
}

- (oneway void)didReleaseApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player
{
    [self setApple2Button:button pressed:NO forPlayer:player];
}

- (void)setApple2Button:(OEApple2Button)button pressed:(BOOL)pressed forPlayer:(NSUInteger)player
{
    switch (button)
    {
        case OEApple2Button0:
            [self setPadButton:0 pressed:pressed forPlayer:player];
            break;
        case OEApple2Button1:
            [self setPadButton:1 pressed:pressed forPlayer:player];
            break;
        case OEApple2Reset:
            _resetHeld = pressed;
            [self updateKeyItem:InputItemID_LCONTROL];
            [self updateKeyItem:InputItemID_F12];
            break;
        case OEApple2MAMEMenu:
            [self menuControlPressed:pressed];
            break;
        case OEApple2Extra1: case OEApple2Extra2: case OEApple2Extra3:
        case OEApple2Extra4: case OEApple2Extra5: case OEApple2Extra6:
            [self setExtraButton:button - OEApple2Extra1 pressed:pressed forPlayer:player];
            break;
        default:
            break;
    }
}

// Commodore 64

- (oneway void)didPushC64Button:(OEC64Button)button forPlayer:(NSUInteger)player
{
    [self setC64Button:button pressed:YES forPlayer:player];
}

- (oneway void)didReleaseC64Button:(OEC64Button)button forPlayer:(NSUInteger)player
{
    [self setC64Button:button pressed:NO forPlayer:player];
}

- (void)setC64Button:(OEC64Button)button pressed:(BOOL)pressed forPlayer:(NSUInteger)player
{
    switch (button)
    {
        case OEC64JoystickUp:
        case OEC64JoystickDown:
        case OEC64JoystickLeft:
        case OEC64JoystickRight:
            [self setDirection:button value:(pressed ? 1.0 : 0.0) forPlayer:player];
            break;
        case OEC64ButtonFire:
            [self setPadButton:0 pressed:pressed forPlayer:player];
            break;
        case OEC64MAMEMenu:
            [self menuControlPressed:pressed];
            break;
        case OEC64Extra1: case OEC64Extra2: case OEC64Extra3:
        case OEC64Extra4: case OEC64Extra5: case OEC64Extra6:
            [self setExtraButton:button - OEC64Extra1 pressed:pressed forPlayer:player];
            break;
        case OEC64ButtonJump:
            // "Jump" is joystick up, for games where up means jump.
            if (player >= 1 && player <= MCMaxPlayers)
            {
                _jumpHeld[player - 1] = pressed;
                [self updateJoystickForPlayer:player - 1];
            }
            break;
        default:
            break;
    }
}

- (oneway void)swapJoysticks
{
    [self setSetting:@(self.joystickPort == 1 ? 2 : 1) forKey:MCSettingJoystickPort];
    [self updateC64Signals];
}

// Apple IIgs

- (oneway void)didMoveApple2GSJoystick:(OEApple2GSButton)direction withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    // OEApple2GSButton has the same values as OEApple2Button.
    [self setDirection:direction value:value forPlayer:player];
}

- (oneway void)didPushApple2GSButton:(OEApple2GSButton)button forPlayer:(NSUInteger)player
{
    [self setApple2Button:(OEApple2Button)button pressed:YES forPlayer:player];
}

- (oneway void)didReleaseApple2GSButton:(OEApple2GSButton)button forPlayer:(NSUInteger)player
{
    [self setApple2Button:(OEApple2Button)button pressed:NO forPlayer:player];
}

// Commodore 128 (OEC128Button has the same values as OEC64Button)

- (oneway void)didPushC128Button:(OEC128Button)button forPlayer:(NSUInteger)player
{
    [self setC64Button:(OEC64Button)button pressed:YES forPlayer:player];
}

- (oneway void)didReleaseC128Button:(OEC128Button)button forPlayer:(NSUInteger)player
{
    [self setC64Button:(OEC64Button)button pressed:NO forPlayer:player];
}

// Macintosh

- (oneway void)didPushMacButton:(OEMacButton)button forPlayer:(NSUInteger)player
{
    [self setMacButton:button pressed:YES];
}

- (oneway void)didReleaseMacButton:(OEMacButton)button forPlayer:(NSUInteger)player
{
    [self setMacButton:button pressed:NO];
}

- (void)setMacButton:(OEMacButton)button pressed:(BOOL)pressed
{
    switch (button)
    {
        case OEMacMouseButton:
            // A gamepad button or key bound to the mouse button.
            _padMouseDown = pressed;
            _mouseButtons[0] = (_hostMouseDown || _padMouseDown) ? 1 : 0;
            break;
        case OEMacMAMEMenu:
            [self menuControlPressed:pressed];
            break;
        default:
            break;
    }
}

#pragma mark - Input: mouse

// The IIgs and Macintosh mouse. The C64 and C128 systems send mouse events
// too, but their mouse (the 1351) isn't wired up here, so they are ignored.

- (void)movePointerTo:(OEIntPoint)point
{
    if (!self.hasMouse)
        return;

    os_unfair_lock_lock(&_mouseLock);
    if (_mouseHasLast && _aspectSize.width > 0 && _aspectSize.height > 0)
    {
        // Points are in OpenEmu's aspect-corrected view units; convert the
        // movement to emulated screen pixels.
        _mouseAccum[0] += (point.x - _mouseLast.x) * (double)_screenRect.size.width  / _aspectSize.width;
        _mouseAccum[1] += (point.y - _mouseLast.y) * (double)_screenRect.size.height / _aspectSize.height;
    }
    _mouseLast = point;
    _mouseHasLast = YES;
    os_unfair_lock_unlock(&_mouseLock);
}

/*! Called on the emulation thread before each frame. */
- (void)latchMouse
{
    if (!self.hasMouse)
        return;

    os_unfair_lock_lock(&_mouseLock);
    for (int axis = 0; axis < 2; axis++)
    {
        _mouseDelta[axis] = (int32_t)(_mouseAccum[axis] * MCRelativePerPixel);
        _mouseAccum[axis] = 0;
    }
    os_unfair_lock_unlock(&_mouseLock);
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
    [self movePointerTo:point];
}

- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
    // Also sent while dragging.
    [self movePointerTo:point];
    _hostMouseDown = YES;
    _mouseButtons[0] = 1;
}

- (oneway void)leftMouseUp
{
    _hostMouseDown = NO;
    _mouseButtons[0] = _padMouseDown ? 1 : 0;
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
    [self movePointerTo:point];
    _mouseButtons[1] = 1;
}

- (oneway void)rightMouseUp
{
    _mouseButtons[1] = 0;
}

#pragma mark - Save states

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *error = nil;
    BOOL ok = _osd.supportsSave && [_osd saveStateFromFileAtPath:fileName error:&error];
    if (!_osd.supportsSave)
    {
        error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey: @"This machine does not support save states.",
        }];
    }
    block(ok, error);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *error = nil;
    BOOL ok = _osd.supportsSave && [_osd loadStateFromFileAtPath:fileName error:&error];
    if (!_osd.supportsSave)
    {
        error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:@{
            NSLocalizedDescriptionKey: @"This machine does not support save states.",
        }];
    }
    block(ok, error);
}

- (NSData *)serializeStateWithError:(NSError *__autoreleasing *)outError
{
    return [_osd serializeState];
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError *__autoreleasing *)outError
{
    return [_osd deserializeState:state];
}

- (BOOL)supportsRewinding
{
    return _supportsRewinding;
}

#pragma mark - Cheats

// Codes are ADDRESS:VALUE in hex (e.g. "0300:FF"), several joined with "+".
// Writes go through the CPU's address space, so they hit whatever memory is
// currently mapped at that address.
- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
    if (!_cheatList)
    {
        _cheatList = [NSMutableDictionary dictionary];
    }

    code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    code = [code stringByReplacingOccurrencesOfString:@" " withString:@""];
    code = [code stringByReplacingOccurrencesOfString:@"=" withString:@":"];

    if (enabled)
        _cheatList[code] = @{ @"enabled": @YES };
    else
        [_cheatList removeObjectForKey:code];

    for (uint32_t i = 0; i < 256; i++)
    {
        [_osd setCheat:i address:0 value:0 size:1 enabled:NO];
    }

    uint32_t idx = 0;
    for (NSString *key in _cheatList)
    {
        for (NSString *single in [key componentsSeparatedByString:@"+"])
        {
            if (idx >= 256) break;
            NSRange colon = [single rangeOfString:@":"];
            if (colon.location == NSNotFound) continue;

            unsigned int addr = 0, val = 0;
            if (![[NSScanner scannerWithString:[single substringToIndex:colon.location]] scanHexInt:&addr]) continue;
            if (![[NSScanner scannerWithString:[single substringFromIndex:colon.location + 1]] scanHexInt:&val]) continue;

            NSUInteger hexLength = single.length - colon.location - 1;
            uint8_t size = (uint8_t)MIN(4, MAX(1, (hexLength + 1) / 2));
            [_osd setCheat:idx address:addr value:val size:size enabled:YES];
            idx++;
        }
    }
}

@end

#pragma mark - Disk set implementation

@implementation MCDiskSet

/*! Disk/side markers commonly found in disk image names (TOSEC, Asimov,
 *  and hand-named files). Case-insensitive. */
+ (NSArray<NSRegularExpression *> *)markerExpressions
{
    static NSArray<NSRegularExpression *> *expressions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *patterns = @[
            // (Disk 1 of 4 Side A)  (Disk 2)  (Disk B)  (Disk 1 of 2)(Side A)
            @"\\s*\\((?:disk|disc)\\s*[0-9a-z]{1,2}(?:\\s*of\\s*[0-9]+)?(?:\\s*,?\\s*side\\s*[0-9a-z])?\\)",
            // (Side A)  (Side 2)
            @"\\s*\\(side\\s*[0-9a-z]\\)",
            // _disk1  Disk 2a  disk-3
            @"[\\s_-]*(?:disk|disc)[\\s_-]*[0-9]{1,2}[ab]?(?=$|[\\s_.()-])",
            // _side_a  Side B
            @"[\\s_-]*side[\\s_-]*[ab12](?=$|[\\s_.()-])",
        ];
        NSMutableArray *built = [NSMutableArray array];
        for (NSString *pattern in patterns)
        {
            [built addObject:[NSRegularExpression regularExpressionWithPattern:pattern
                                                                       options:NSRegularExpressionCaseInsensitive
                                                                         error:nil]];
        }
        expressions = built;
    });
    return expressions;
}

/*! Splits a file name (without extension) into the part shared by every disk
 *  of the game (normalized, for comparison) and the disk/side marker. */
+ (NSString *)groupKeyForName:(NSString *)name marker:(NSString **)outMarker
{
    NSMutableString *remaining = [name mutableCopy];
    NSMutableArray<NSString *> *markers = [NSMutableArray array];

    for (NSRegularExpression *re in [self markerExpressions])
    {
        NSArray<NSTextCheckingResult *> *matches = [re matchesInString:remaining options:0 range:NSMakeRange(0, remaining.length)];
        for (NSTextCheckingResult *match in matches.reverseObjectEnumerator)
        {
            NSString *text = [remaining substringWithRange:match.range];
            NSCharacterSet *trim = [NSCharacterSet characterSetWithCharactersInString:@" _-()"];
            [markers insertObject:[text stringByTrimmingCharactersInSet:trim] atIndex:0];
            [remaining deleteCharactersInRange:match.range];
        }
    }

    if (outMarker)
    {
        // Label in reading order: "Disk 1 of 2 Side A", not "Side A Disk 1 of 2".
        [markers sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSUInteger ia = [name rangeOfString:a].location, ib = [name rangeOfString:b].location;
            return ia < ib ? NSOrderedAscending : (ia > ib ? NSOrderedDescending : NSOrderedSame);
        }];
        *outMarker = [markers componentsJoinedByString:@" "];
    }

    // Normalize: lowercase, runs of punctuation/space collapsed.
    NSString *lower = remaining.lowercaseString;
    NSMutableString *key = [NSMutableString string];
    BOOL pendingSpace = NO;
    for (NSUInteger i = 0; i < lower.length; i++)
    {
        unichar c = [lower characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c])
        {
            if (pendingSpace && key.length > 0) [key appendString:@" "];
            [key appendFormat:@"%C", c];
            pendingSpace = NO;
        }
        else
        {
            pendingSpace = YES;
        }
    }
    return key;
}

+ (instancetype)diskSetForPath:(NSString *)path extensions:(NSSet<NSString *> *)extensions
{
    MCDiskSet *set = [self new];

    NSString *baseName = path.lastPathComponent.stringByDeletingPathExtension;
    NSString *marker = nil;
    NSString *key = [self groupKeyForName:baseName marker:&marker];

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:path];

    if (extensions.count > 0 && marker.length > 0 && key.length > 0)
    {
        NSString *dir = path.stringByDeletingLastPathComponent;
        NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in contents)
        {
            NSString *candidate = [dir stringByAppendingPathComponent:file];
            if ([candidate isEqualToString:path] || ![extensions containsObject:file.pathExtension.lowercaseString]) continue;

            NSString *otherMarker = nil;
            NSString *otherKey = [self groupKeyForName:file.stringByDeletingPathExtension marker:&otherMarker];
            if (otherMarker.length > 0 && [otherKey isEqualToString:key])
            {
                [paths addObject:candidate];
            }
        }
        [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
        }];
    }

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSString *p in paths)
    {
        NSString *m = nil;
        [self groupKeyForName:p.lastPathComponent.stringByDeletingPathExtension marker:&m];
        [labels addObject:(paths.count > 1 && m.length > 0) ? m : p.lastPathComponent.stringByDeletingPathExtension];
    }

    set->_paths = paths;
    set->_labels = labels;
    set->_launchedIndex = [paths indexOfObject:path];
    set->_settingsName = (paths.count > 1) ? key : baseName;
    return set;
}

@end
