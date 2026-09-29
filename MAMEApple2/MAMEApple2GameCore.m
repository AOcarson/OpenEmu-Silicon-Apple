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

#import "MAMEApple2GameCore.h"

#import <OpenEmuBase/OERingBuffer.h>
#import <OpenGL/gl.h>
#import <os/log.h>

#pragma mark - Constants

// MAME drivers offered in the Machine menu. apple2ee is the enhanced //e
// (65C02, MouseText), which runs virtually everything; apple2e is the
// original 1983 //e for the rare title that trips over the enhanced ROM.
static NSString *const Apple2DefaultMachine = @"apple2ee";

// MAME option names. "flop1"/"flop2" are the two Disk II drives on the
// default slot 6 controller; "gameio" is the joystick port.
static NSString *const Apple2OptionGameIO = @"gameio";
static NSString *const Apple2OptionDrive1 = @"flop1";
static NSString *const Apple2OptionDrive2 = @"flop2";
static NSString *const Apple2GameIOJoystick = @"joy";

// Per-game settings file keys. These files live in
// <core support folder>/Game Settings/<game>.plist and can be edited by hand.
static NSString *const Apple2SettingJoystick     = @"JoystickConnected";          // BOOL, default YES
static NSString *const Apple2SettingArrowKeys    = @"ArrowKeysControlJoystick";   // BOOL, default NO
static NSString *const Apple2SettingMachine      = @"Machine";                    // MAME driver, default apple2ee
static NSString *const Apple2SettingMAMEOptions  = @"MAMEOptions";                // { option: value }, applied at boot
static NSString *const Apple2SettingMAMEPlugins  = @"MAMEPlugins";                // [ plugin folder name, ... ]

// Display-mode preference keys (identify menu entries; never saved by OpenEmu).
static NSString *const Apple2ModeJoystick  = @"apple2.joystick";
static NSString *const Apple2ModeArrowKeys = @"apple2.arrowkeys";
static NSString *const Apple2ModeMachine   = @"apple2.machine";
static NSString *const Apple2ModeDrive1    = @"apple2.drive1";
static NSString *const Apple2ModeDrive2    = @"apple2.drive2";

enum { Apple2MaxPlayers = 2 };
enum { Apple2Drive2Empty = -1 };

#pragma mark - Keyboard mapping

// USB HID keyboard usage (what OpenEmu delivers in keyDown:/keyUp:) to MAME
// keyboard item. MAME's Apple IIe keyboard matrix is defined in terms of
// these standard keycodes (Open Apple = left Alt, Solid Apple = right Alt,
// RESET = F12), so feeding them through reproduces MAME's own key layout.
typedef struct
{
    uint8_t     hid;
    InputItemID item;
    const char *name;
} Apple2KeyMapping;

static const Apple2KeyMapping Apple2KeyMap[] =
{
    { 0x04, InputItemID_A, "A" }, { 0x05, InputItemID_B, "B" }, { 0x06, InputItemID_C, "C" },
    { 0x07, InputItemID_D, "D" }, { 0x08, InputItemID_E, "E" }, { 0x09, InputItemID_F, "F" },
    { 0x0A, InputItemID_G, "G" }, { 0x0B, InputItemID_H, "H" }, { 0x0C, InputItemID_I, "I" },
    { 0x0D, InputItemID_J, "J" }, { 0x0E, InputItemID_K, "K" }, { 0x0F, InputItemID_L, "L" },
    { 0x10, InputItemID_M, "M" }, { 0x11, InputItemID_N, "N" }, { 0x12, InputItemID_O, "O" },
    { 0x13, InputItemID_P, "P" }, { 0x14, InputItemID_Q, "Q" }, { 0x15, InputItemID_R, "R" },
    { 0x16, InputItemID_S, "S" }, { 0x17, InputItemID_T, "T" }, { 0x18, InputItemID_U, "U" },
    { 0x19, InputItemID_V, "V" }, { 0x1A, InputItemID_W, "W" }, { 0x1B, InputItemID_X, "X" },
    { 0x1C, InputItemID_Y, "Y" }, { 0x1D, InputItemID_Z, "Z" },

    { 0x1E, InputItemID_1, "1" }, { 0x1F, InputItemID_2, "2" }, { 0x20, InputItemID_3, "3" },
    { 0x21, InputItemID_4, "4" }, { 0x22, InputItemID_5, "5" }, { 0x23, InputItemID_6, "6" },
    { 0x24, InputItemID_7, "7" }, { 0x25, InputItemID_8, "8" }, { 0x26, InputItemID_9, "9" },
    { 0x27, InputItemID_0, "0" },

    { 0x28, InputItemID_ENTER,      "Return" },
    { 0x29, InputItemID_ESC,        "Esc" },
    { 0x2A, InputItemID_BACKSPACE,  "Delete" },
    { 0x2B, InputItemID_TAB,        "Tab" },
    { 0x2C, InputItemID_SPACE,      "Space" },
    { 0x2D, InputItemID_MINUS,      "-" },
    { 0x2E, InputItemID_EQUALS,     "=" },
    { 0x2F, InputItemID_OPENBRACE,  "[" },
    { 0x30, InputItemID_CLOSEBRACE, "]" },
    { 0x31, InputItemID_BACKSLASH,  "\\" },
    { 0x32, InputItemID_BACKSLASH2, "Non-US #" },
    { 0x33, InputItemID_COLON,      ";" },
    { 0x34, InputItemID_QUOTE,      "'" },
    { 0x35, InputItemID_TILDE,      "`" },
    { 0x36, InputItemID_COMMA,      "," },
    { 0x37, InputItemID_STOP,       "." },
    { 0x38, InputItemID_SLASH,      "/" },
    { 0x39, InputItemID_CAPSLOCK,   "Caps Lock" },

    { 0x3A, InputItemID_F1,  "F1" },  { 0x3B, InputItemID_F2,  "F2" },  { 0x3C, InputItemID_F3,  "F3" },
    { 0x3D, InputItemID_F4,  "F4" },  { 0x3E, InputItemID_F5,  "F5" },  { 0x3F, InputItemID_F6,  "F6" },
    { 0x40, InputItemID_F7,  "F7" },  { 0x41, InputItemID_F8,  "F8" },  { 0x42, InputItemID_F9,  "F9" },
    { 0x43, InputItemID_F10, "F10" }, { 0x44, InputItemID_F11, "F11" }, { 0x45, InputItemID_F12, "F12 (Reset)" },

    // fn-Delete (Forward Delete) toggles MAME's UI keys on and off, as with
    // MAME's own Scroll Lock / fn-Delete. While on, Tab opens MAME's menu.
    { 0x4C, InputItemID_SCRLOCK, "Toggle MAME UI (fn-Delete)" },

    { 0x4F, InputItemID_RIGHT, "Right" },
    { 0x50, InputItemID_LEFT,  "Left" },
    { 0x51, InputItemID_DOWN,  "Down" },
    { 0x52, InputItemID_UP,    "Up" },

    { 0x53, InputItemID_NUMLOCK,    "Clear" },
    { 0x54, InputItemID_SLASH_PAD,  "Keypad /" },
    { 0x55, InputItemID_ASTERISK,   "Keypad *" },
    { 0x56, InputItemID_MINUS_PAD,  "Keypad -" },
    { 0x57, InputItemID_PLUS_PAD,   "Keypad +" },
    { 0x58, InputItemID_ENTER_PAD,  "Keypad Enter" },
    { 0x59, InputItemID_1_PAD, "Keypad 1" }, { 0x5A, InputItemID_2_PAD, "Keypad 2" },
    { 0x5B, InputItemID_3_PAD, "Keypad 3" }, { 0x5C, InputItemID_4_PAD, "Keypad 4" },
    { 0x5D, InputItemID_5_PAD, "Keypad 5" }, { 0x5E, InputItemID_6_PAD, "Keypad 6" },
    { 0x5F, InputItemID_7_PAD, "Keypad 7" }, { 0x60, InputItemID_8_PAD, "Keypad 8" },
    { 0x61, InputItemID_9_PAD, "Keypad 9" }, { 0x62, InputItemID_0_PAD, "Keypad 0" },
    { 0x63, InputItemID_DEL_PAD, "Keypad ." },

    // Modifiers. Both Controls act as the IIe's single Control key. Option and
    // Command both act as the Apple keys (left = Open Apple, right = Solid
    // Apple), since the original Mac Command key *was* the Apple key.
    { 0xE0, InputItemID_LCONTROL, "Control" },
    { 0xE1, InputItemID_LSHIFT,   "Left Shift" },
    { 0xE2, InputItemID_LALT,     "Open Apple" },
    { 0xE3, InputItemID_LALT,     "Open Apple" },
    { 0xE4, InputItemID_LCONTROL, "Control" },
    { 0xE5, InputItemID_RSHIFT,   "Right Shift" },
    { 0xE6, InputItemID_RALT,     "Solid Apple" },
    { 0xE7, InputItemID_RALT,     "Solid Apple" },
};

static const size_t Apple2KeyMapCount = sizeof(Apple2KeyMap) / sizeof(Apple2KeyMap[0]);

// HID usages of the arrow keys, used when "Arrow Keys Control Joystick" is on.
enum
{
    Apple2HIDRight = 0x4F,
    Apple2HIDLeft  = 0x50,
    Apple2HIDDown  = 0x51,
    Apple2HIDUp    = 0x52,
};

static int32_t apple2_get_state(void *device_internal, void *item_internal)
{
    return *(int32_t *)item_internal;
}

static os_log_t OE_CORE_LOG;

#pragma mark - Disk sets

/*! A game's disk images: the launched file plus sibling images in the same
 *  folder that share its name apart from a disk/side marker, e.g.
 *  "Ultima IV (Disk 1 of 4 Side A).woz", "Ultima IV (Disk 1 of 4 Side B).woz". */
@interface MAMEApple2DiskSet : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *paths;
@property (nonatomic, readonly) NSArray<NSString *> *labels;
@property (nonatomic, readonly) NSUInteger launchedIndex;
/*! Stable name shared by every disk of the set; used for per-game settings. */
@property (nonatomic, readonly) NSString *settingsName;
+ (instancetype)diskSetForPath:(NSString *)path;
@end

#pragma mark - Core

@interface MAMEApple2GameCore () <OEApple2SystemResponderClient>
{
    // input state read by MAME through apple2_get_state
    int32_t _keys[InputItemID_ABSOLUTE_MAXIMUM];
    int32_t _axes[Apple2MaxPlayers][2];
    int32_t _buttons[Apple2MaxPlayers][2];

    // raw input, combined into the above
    BOOL    _hidDown[256];
    BOOL    _resetHeld;
    CGFloat _stick[Apple2MaxPlayers][4];   // gamepad, per OEApple2Joystick* direction, 0...1

    uint32_t  *_buffer;
    OEIntSize  _bufferSize;
    OEIntRect  _screenRect;
    OEIntSize  _aspectSize;
    NSTimeInterval _frameInterval;

    OSD *_osd;
    BOOL _supportsRewinding;
    BOOL _machineRunning;   // NO after a failed restart; frames are skipped

    MAMEApple2DiskSet *_disks;
    NSUInteger _drive1Index;
    NSInteger  _drive2Index;
    NSString  *_drive1Path;   // may be a file inserted from outside the set

    NSString *_settingsPath;
    NSMutableDictionary<NSString *, id> *_settings;

    NSMutableDictionary<NSString *, NSDictionary *> *_cheatList;
}
@end

@implementation MAMEApple2GameCore

#pragma mark - Lifecycle

+ (void)initialize
{
    if (self == [MAMEApple2GameCore class])
    {
        OE_CORE_LOG = os_log_create("org.openemu.MAMEApple2", "");
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
    _drive2Index   = Apple2Drive2Empty;

    _osd = [OSD shared];
    _osd.delegate = self;

    return self;
}

#pragma mark - Settings

- (BOOL)boolSetting:(NSString *)key fallback:(BOOL)fallback
{
    id value = _settings[key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

- (BOOL)joystickConnected   { return [self boolSetting:Apple2SettingJoystick fallback:YES]; }
- (BOOL)arrowKeysAreJoystick { return [self boolSetting:Apple2SettingArrowKeys fallback:NO]; }

- (NSString *)machine
{
    id value = _settings[Apple2SettingMachine];
    return ([value isKindOfClass:[NSString class]] && [value length] > 0) ? value : Apple2DefaultMachine;
}

- (void)loadSettingsForDiskSet:(MAMEApple2DiskSet *)disks
{
    NSString *dir = [self.supportDirectoryPath stringByAppendingPathComponent:@"Game Settings"];
    NSString *name = [[disks.settingsName stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                      stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    _settingsPath = [[dir stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plist"];

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

    for (int player = 0; player < Apple2MaxPlayers; player++)
    {
        NSString *name = [NSString stringWithFormat:@"OpenEmu Joystick %d", player + 1];
        InputDevice *dev = [_osd.joystick addDeviceNamed:name];
        [dev addItemNamed:@"X Axis"   id:InputItemID_XAXIS   getter:apple2_get_state context:&_axes[player][0]];
        [dev addItemNamed:@"Y Axis"   id:InputItemID_YAXIS   getter:apple2_get_state context:&_axes[player][1]];
        [dev addItemNamed:@"Button 0" id:InputItemID_BUTTON1 getter:apple2_get_state context:&_buttons[player][0]];
        [dev addItemNamed:@"Button 1" id:InputItemID_BUTTON2 getter:apple2_get_state context:&_buttons[player][1]];
    }

    InputDevice *kb = [_osd.keyboard addDeviceNamed:@"OpenEmu Keyboard"];
    BOOL added[InputItemID_ABSOLUTE_MAXIMUM] = { NO };
    for (size_t i = 0; i < Apple2KeyMapCount; i++)
    {
        InputItemID item = Apple2KeyMap[i].item;
        if (added[item])
        {
            continue; // several Mac keys can share one IIe key
        }
        added[item] = YES;
        [kb addItemNamed:@(Apple2KeyMap[i].name) id:item getter:apple2_get_state context:&_keys[item]];
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
    // MAME looks for apple2ee.zip / apple2e.zip / a2diskiing.zip here.
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
    _disks = [MAMEApple2DiskSet diskSetForPath:path];
    _drive1Index = _disks.launchedIndex;
    _drive1Path  = _disks.paths[_drive1Index];
    _drive2Index = Apple2Drive2Empty;

    [self loadSettingsForDiskSet:_disks];

    os_log_info(OE_CORE_LOG, "loading %{public}@ (%lu disk(s) in set), machine %{public}@, settings %{public}@",
                path.lastPathComponent, (unsigned long)_disks.paths.count, self.machine, _settingsPath);

    return [self startMachineWithError:error];
}

/*! Selects the driver, applies every option and boots. Used for the first
 *  boot and for restarts after a setting that changes the hardware. */
- (BOOL)startMachineWithError:(NSError **)error
{
    Options *opts = _osd.options;
    [opts setBasePath:self.supportDirectoryPath];
    opts.romsPath = [self romSearchPath];
    opts.cheat = NO;
    opts.autoStretchXY = NO;
    opts.unevenStretchX = NO;
    opts.unevenStretchY = NO;
    opts.unevenStretch = NO;
    opts.keepAspect = YES;
    _osd.verboseOutput = NO;

    NSString *machine = self.machine;
    AuditResult *audit = nil;
    if (![_osd setDriver:machine withAuditResult:&audit error:nil])
    {
        if (error)
        {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey: @"Unknown Apple II model.",
                NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:
                    @"\"%@\" is not a machine this core can emulate. Check the \"%@\" entry in:\n\n%@",
                    machine, Apple2SettingMachine, _settingsPath],
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

    // Slot options must be set before the media options their cards provide.
    NSMutableArray<NSString *> *rejected = [NSMutableArray array];
    NSError *optionError = nil;

    // Esc with MAME's UI keys on asks before "quitting" (which restarts the
    // machine here, since OpenEmu owns the window).
    [opts setValue:@"1" forOptionNamed:@"confirm_quit" error:NULL];

    // Lua plugins. MAME starts them once, with the first machine of this game
    // session, so changes to the list apply the next time the game is opened.
    NSString *pluginsDir = [self.supportDirectoryPath stringByAppendingPathComponent:@"plugins"];
    [opts setValue:self.supportDirectoryPath forOptionNamed:@"homepath" error:NULL];
    [opts setValue:@"1" forOptionNamed:@"plugins" error:NULL];
    [opts setValue:[self pluginListInDirectory:pluginsDir] forOptionNamed:@"plugin" error:NULL];

    if (![opts setValue:(self.joystickConnected ? Apple2GameIOJoystick : @"") forOptionNamed:Apple2OptionGameIO error:&optionError])
    {
        [rejected addObject:optionError.localizedDescription ?: @"unknown option error"];
    }

    NSDictionary *custom = _settings[Apple2SettingMAMEOptions];
    if ([custom isKindOfClass:[NSDictionary class]])
    {
        for (NSString *name in custom)
        {
            id value = custom[name];
            if (![name isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]])
            {
                continue;
            }
            if (![opts setValue:value forOptionNamed:name error:&optionError])
            {
                [rejected addObject:optionError.localizedDescription ?: @"unknown option error"];
            }
        }
    }

    if (![opts setValue:_drive1Path forOptionNamed:Apple2OptionDrive1 error:&optionError])
    {
        // Without drive 1 there is nothing to boot.
        if (error)
        {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey: @"Could not insert the disk.",
                NSLocalizedRecoverySuggestionErrorKey: optionError.localizedDescription ?: @"",
            }];
        }
        return NO;
    }

    NSString *drive2Path = (_drive2Index == Apple2Drive2Empty) ? @"" : _disks.paths[_drive2Index];
    if (![opts setValue:drive2Path forOptionNamed:Apple2OptionDrive2 error:&optionError])
    {
        [rejected addObject:optionError.localizedDescription ?: @"unknown option error"];
    }

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

/*! The game's MAMEPlugins setting as MAME's comma-separated "plugin" option,
 *  keeping only plugins that are actually installed (an unknown name would
 *  otherwise stop MAME from starting any plugin). */
- (NSString *)pluginListInDirectory:(NSString *)pluginsDir
{
    id requested = _settings[Apple2SettingMAMEPlugins];
    NSArray *names = nil;
    if ([requested isKindOfClass:[NSArray class]])
    {
        names = requested;
    }
    else if ([requested isKindOfClass:[NSString class]])
    {
        names = [requested componentsSeparatedByString:@","];
    }

    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (id item in names)
    {
        if (![item isKindOfClass:[NSString class]])
        {
            continue;
        }
        NSString *name = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0)
        {
            continue;
        }
        NSString *manifest = [[pluginsDir stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"plugin.json"];
        if ([fm fileExistsAtPath:manifest])
        {
            [valid addObject:name];
        }
        else
        {
            os_log_error(OE_CORE_LOG, "MAME plugin \"%{public}@\" not found (expected %{public}@)", name, manifest);
        }
    }

    if (valid.count > 0 && ![fm fileExistsAtPath:[pluginsDir stringByAppendingPathComponent:@"boot.lua"]])
    {
        os_log_error(OE_CORE_LOG, "MAME plugins need boot.lua in %{public}@; run Scripts/build-mame-apple2-core.sh to install it", pluginsDir);
    }

    return [valid componentsJoinedByString:@","];
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
                // ROMs belonging to a card (e.g. the Disk II controller) are
                // in that card's own set; the machine's are in its own set,
                // or its parent's for a merged ROM set.
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
        driver.fullName ?: @"The Apple IIe", list, self.biosDirectoryPath ?: @"the OpenEmu BIOS folder"];

    return [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
        NSLocalizedDescriptionKey: @"Apple IIe system ROMs are missing.",
        NSLocalizedRecoverySuggestionErrorKey: suggestion,
    }];
}

- (void)resetEmulation
{
    // A cold boot, like power-cycling the machine, with the current disks.
    [self restartMachine];
}

#pragma mark - Disks

- (NSUInteger)discCount
{
    return _disks.paths.count;
}

- (void)setDisc:(NSUInteger)discNumber
{
    // OpenEmu numbers discs from 1.
    if (discNumber >= 1 && discNumber <= _disks.paths.count)
    {
        [self insertDiskAtIndex:discNumber - 1 intoDrive2:NO];
    }
}

- (BOOL)insertDiskAtIndex:(NSUInteger)index intoDrive2:(BOOL)drive2
{
    NSString *path = _disks.paths[index];
    NSString *device = drive2 ? Apple2OptionDrive2 : Apple2OptionDrive1;

    NSError *error = nil;
    if (![_osd loadMediaAtPath:path forDevice:device error:&error])
    {
        os_log_error(OE_CORE_LOG, "could not insert %{public}@: %{public}@", path.lastPathComponent, error);
        return NO;
    }

    if (drive2)
    {
        _drive2Index = (NSInteger)index;
    }
    else
    {
        _drive1Index = index;
        _drive1Path  = path;
    }
    return YES;
}

- (void)insertFileAtURL:(NSURL *)url completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *error = nil;
    BOOL ok = [_osd loadMediaAtPath:url.path forDevice:Apple2OptionDrive1 error:&error];
    if (ok)
    {
        _drive1Path = url.path;
        NSUInteger index = [_disks.paths indexOfObject:url.path];
        _drive1Index = (index == NSNotFound) ? _drive1Index : index;
    }
    if (block)
    {
        block(ok, error);
    }
}

#pragma mark - Display modes (per-game settings menu)

static NSDictionary *Apple2Toggle(NSString *name, NSString *prefKey, BOOL state)
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

static NSDictionary *Apple2Choice(NSString *name, NSString *prefKey, NSString *value, BOOL state)
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

static NSDictionary *Apple2Group(NSString *name, NSArray *items)
{
    return @{ OEGameCoreDisplayModeGroupNameKey: name, OEGameCoreDisplayModeGroupItemsKey: items };
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayModes
{
    NSMutableArray *modes = [NSMutableArray array];

    [modes addObject:Apple2Toggle(@"Joystick Connected (restarts)", Apple2ModeJoystick, self.joystickConnected)];
    [modes addObject:Apple2Toggle(@"Arrow Keys Control Joystick", Apple2ModeArrowKeys, self.arrowKeysAreJoystick)];

    NSString *machine = self.machine;
    NSArray *machines = @[
        Apple2Choice(@"Apple //e (Enhanced)", Apple2ModeMachine, @"apple2ee", [machine isEqualToString:@"apple2ee"]),
        Apple2Choice(@"Apple //e (Original)", Apple2ModeMachine, @"apple2e",  [machine isEqualToString:@"apple2e"]),
    ];
    [modes addObject:Apple2Group(@"Machine (restarts)", machines)];

    if (_disks.paths.count > 1)
    {
        NSMutableArray *drive1 = [NSMutableArray array];
        NSMutableArray *drive2 = [NSMutableArray array];
        [drive2 addObject:Apple2Choice(@"Drive 2: Empty", Apple2ModeDrive2, @"-1", _drive2Index == Apple2Drive2Empty)];
        // What MAME actually has mounted; MAME's File Manager can change it.
        NSString *mounted = [_osd mediaPathForDevice:Apple2OptionDrive1] ?: _drive1Path;

        for (NSUInteger i = 0; i < _disks.paths.count; i++)
        {
            NSString *label = _disks.labels[i];
            NSString *value = [NSString stringWithFormat:@"%lu", (unsigned long)i];
            BOOL inDrive1 = [mounted isEqualToString:_disks.paths[i]];
            [drive1 addObject:Apple2Choice([NSString stringWithFormat:@"Drive 1: %@", label], Apple2ModeDrive1, value, inDrive1)];
            [drive2 addObject:Apple2Choice([NSString stringWithFormat:@"Drive 2: %@", label], Apple2ModeDrive2, value, _drive2Index == (NSInteger)i)];
        }
        [modes addObject:Apple2Group(@"Drive 1", drive1)];
        [modes addObject:Apple2Group(@"Drive 2", drive2)];
    }

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

    if ([key isEqualToString:Apple2ModeJoystick])
    {
        [self setSetting:@(!state) forKey:Apple2SettingJoystick];
        [self restartMachine];
    }
    else if ([key isEqualToString:Apple2ModeArrowKeys])
    {
        [self setSetting:@(!state) forKey:Apple2SettingArrowKeys];
        [self releaseArrowKeys];
    }
    else if ([key isEqualToString:Apple2ModeMachine])
    {
        if (!state)
        {
            // If the other model can't start (usually its ROM set is
            // missing), fall back to the one that was running.
            NSString *previous = self.machine;
            [self setSetting:value forKey:Apple2SettingMachine];
            if (![self restartMachine])
            {
                [self setSetting:previous forKey:Apple2SettingMachine];
                [self restartMachine];
            }
        }
    }
    else if ([key isEqualToString:Apple2ModeDrive1])
    {
        [self insertDiskAtIndex:(NSUInteger)value.integerValue intoDrive2:NO];
    }
    else if ([key isEqualToString:Apple2ModeDrive2])
    {
        NSInteger index = value.integerValue;
        if (index == Apple2Drive2Empty)
        {
            [_osd unloadMediaForDevice:Apple2OptionDrive2];
            _drive2Index = Apple2Drive2Empty;
        }
        else
        {
            [self insertDiskAtIndex:(NSUInteger)index intoDrive2:YES];
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
    if (_machineRunning)
    {
        [_osd execute];
    }
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

- (void)updateKeyItem:(InputItemID)item
{
    BOOL down = NO;
    for (size_t i = 0; i < Apple2KeyMapCount && !down; i++)
    {
        if (Apple2KeyMap[i].item == item && _hidDown[Apple2KeyMap[i].hid] && ![self hidKeyIsJoystick:Apple2KeyMap[i].hid])
        {
            down = YES;
        }
    }

    // Control-Reset from the gamepad/controls binding.
    if (_resetHeld && (item == InputItemID_LCONTROL || item == InputItemID_F12))
    {
        down = YES;
    }

    _keys[item] = down ? 1 : 0;
}

- (BOOL)hidKeyIsJoystick:(NSUInteger)hid
{
    if (!self.arrowKeysAreJoystick)
    {
        return NO;
    }
    return hid == Apple2HIDUp || hid == Apple2HIDDown || hid == Apple2HIDLeft || hid == Apple2HIDRight;
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
        [self updateAxesForPlayer:0];
        return;
    }

    for (size_t i = 0; i < Apple2KeyMapCount; i++)
    {
        if (Apple2KeyMap[i].hid == keyCode)
        {
            [self updateKeyItem:Apple2KeyMap[i].item];
            return;
        }
    }
}

- (void)releaseArrowKeys
{
    // Called when the arrow-key mode flips, so nothing stays stuck on either side.
    for (NSUInteger hid = Apple2HIDRight; hid <= Apple2HIDUp; hid++)
    {
        _hidDown[hid] = NO;
    }
    [self updateKeyItem:InputItemID_UP];
    [self updateKeyItem:InputItemID_DOWN];
    [self updateKeyItem:InputItemID_LEFT];
    [self updateKeyItem:InputItemID_RIGHT];
    [self updateAxesForPlayer:0];
}

- (oneway void)keyDown:(NSUInteger)keyCode
{
    [self setHIDKey:keyCode down:YES];
}

- (oneway void)keyUp:(NSUInteger)keyCode
{
    [self setHIDKey:keyCode down:NO];
}

#pragma mark - Input: joystick

- (void)updateAxesForPlayer:(NSUInteger)player
{
    CGFloat x = _stick[player][OEApple2JoystickRight] - _stick[player][OEApple2JoystickLeft];
    CGFloat y = _stick[player][OEApple2JoystickDown]  - _stick[player][OEApple2JoystickUp];

    // Arrow keys drive joystick 1 at full deflection when the gamepad is centred.
    if (player == 0 && self.arrowKeysAreJoystick)
    {
        if (x == 0) x = (CGFloat)_hidDown[Apple2HIDRight] - (CGFloat)_hidDown[Apple2HIDLeft];
        if (y == 0) y = (CGFloat)_hidDown[Apple2HIDDown]  - (CGFloat)_hidDown[Apple2HIDUp];
    }

    x = MAX(-1.0, MIN(1.0, x));
    y = MAX(-1.0, MIN(1.0, y));
    _axes[player][0] = (int32_t)(x * InputAbsoluteMax);
    _axes[player][1] = (int32_t)(y * InputAbsoluteMax);
}

- (oneway void)didMoveApple2Joystick:(OEApple2Button)direction withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    if (player < 1 || player > Apple2MaxPlayers || direction > OEApple2JoystickRight)
    {
        return;
    }
    _stick[player - 1][direction] = MAX(0.0, MIN(1.0, value));
    [self updateAxesForPlayer:player - 1];
}

- (oneway void)didPushApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player
{
    [self setButton:button pressed:YES forPlayer:player];
}

- (oneway void)didReleaseApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player
{
    [self setButton:button pressed:NO forPlayer:player];
}

- (void)setButton:(OEApple2Button)button pressed:(BOOL)pressed forPlayer:(NSUInteger)player
{
    if (player < 1 || player > Apple2MaxPlayers)
    {
        return;
    }

    switch (button)
    {
        case OEApple2Button0:
            _buttons[player - 1][0] = pressed ? 1 : 0;
            break;
        case OEApple2Button1:
            _buttons[player - 1][1] = pressed ? 1 : 0;
            break;
        case OEApple2Reset:
            _resetHeld = pressed;
            [self updateKeyItem:InputItemID_LCONTROL];
            [self updateKeyItem:InputItemID_F12];
            break;
        default:
            break;
    }
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
// Writes go through the 65C02's address space, so they hit whatever memory
// bank is currently mapped at that address.
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

@implementation MAMEApple2DiskSet

/*! Disk/side markers commonly found in Apple II image names (TOSEC, Asimov,
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

+ (BOOL)isDiskImagePath:(NSString *)path
{
    // Keep in sync with OEFileSuffixes in the Apple IIe system plugin.
    static NSSet<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [NSSet setWithObjects:@"dsk", @"do", @"po", @"nib", @"woz", nil];
    });
    return [extensions containsObject:path.pathExtension.lowercaseString];
}

+ (instancetype)diskSetForPath:(NSString *)path
{
    MAMEApple2DiskSet *set = [self new];

    NSString *baseName = path.lastPathComponent.stringByDeletingPathExtension;
    NSString *marker = nil;
    NSString *key = [self groupKeyForName:baseName marker:&marker];

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:path];

    if (marker.length > 0 && key.length > 0)
    {
        NSString *dir = path.stringByDeletingLastPathComponent;
        NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in contents)
        {
            NSString *candidate = [dir stringByAppendingPathComponent:file];
            if ([candidate isEqualToString:path] || ![self isDiskImagePath:candidate]) continue;

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
