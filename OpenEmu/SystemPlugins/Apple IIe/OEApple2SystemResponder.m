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

#import "OEApple2SystemResponder.h"
#import "OEApple2SystemResponderClient.h"

@implementation OEApple2SystemResponder
@dynamic client;

+ (Protocol *)gameSystemResponderClientProtocol
{
    return @protocol(OEApple2SystemResponderClient);
}

// The Apple IIe is a keyboard computer: every Mac key is forwarded to the core,
// which maps it onto the IIe keyboard (and, optionally, the arrow keys onto
// the joystick). Keys bound to a control in the controls preferences fire
// that control instead (see below).

// A key bound to a control in OpenEmu's Controls preferences (a joystick
// direction, MAME Menu, Reset...) does that job only; every other key is
// typed on the emulated keyboard.
- (void)HIDKeyDown:(OEHIDEvent *)theEvent
{
    [super HIDKeyDown:theEvent];
    if ([self.keyMap systemKeyForEvent:theEvent] == nil)
        [self.client keyDown:theEvent.keycode];
}

- (void)HIDKeyUp:(OEHIDEvent *)theEvent
{
    [super HIDKeyUp:theEvent];
    if ([self.keyMap systemKeyForEvent:theEvent] == nil)
        [self.client keyUp:theEvent.keycode];
}

- (void)changeAnalogEmulatorKey:(OESystemKey *)aKey value:(CGFloat)value
{
    [self.client didMoveApple2Joystick:(OEApple2Button)aKey.key withValue:value forPlayer:aKey.player];
}

- (void)pressEmulatorKey:(OESystemKey *)aKey
{
    OEApple2Button button = (OEApple2Button)aKey.key;
    switch (button)
    {
        case OEApple2JoystickUp:
        case OEApple2JoystickDown:
        case OEApple2JoystickLeft:
        case OEApple2JoystickRight:
            [self.client didMoveApple2Joystick:button withValue:1.0 forPlayer:aKey.player];
            break;
        default:
            [self.client didPushApple2Button:button forPlayer:aKey.player];
            break;
    }
}

- (void)releaseEmulatorKey:(OESystemKey *)aKey
{
    OEApple2Button button = (OEApple2Button)aKey.key;
    switch (button)
    {
        case OEApple2JoystickUp:
        case OEApple2JoystickDown:
        case OEApple2JoystickLeft:
        case OEApple2JoystickRight:
            [self.client didMoveApple2Joystick:button withValue:0.0 forPlayer:aKey.player];
            break;
        default:
            [self.client didReleaseApple2Button:button forPlayer:aKey.player];
            break;
    }
}

@end
