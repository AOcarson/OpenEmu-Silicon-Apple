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

#import <Foundation/Foundation.h>

@protocol OESystemResponderClient;

/*! Controls exposed to OpenEmu's controller preferences for the Apple IIe.
 *
 *  The joystick directions are declared analog in the system plist, so a
 *  gamepad's analog stick drives the Apple II's proportional joystick, while
 *  d-pads and keys give full deflection. Button 0 and Button 1 are wired to the
 *  same inputs as the Open Apple and Solid Apple keys, exactly like the real
 *  hardware. Reset presses Control-Reset. MAME Menu opens or closes MAME's
 *  menu. Extra 1-6 are spare joystick buttons for binding to keys in MAME's
 *  Input Settings (they appear there as Joy n Button 3-8). */
typedef enum
{
    OEApple2JoystickUp,
    OEApple2JoystickDown,
    OEApple2JoystickLeft,
    OEApple2JoystickRight,
    OEApple2Button0,
    OEApple2Button1,
    OEApple2Reset,
    OEApple2MAMEMenu,
    OEApple2Extra1,
    OEApple2Extra2,
    OEApple2Extra3,
    OEApple2Extra4,
    OEApple2Extra5,
    OEApple2Extra6,
    OEApple2ButtonCount
} OEApple2Button;

@protocol OEApple2SystemResponderClient <OESystemResponderClient, NSObject>

/*! value is 0.0 (released) to 1.0 (full deflection) for one direction. */
- (oneway void)didMoveApple2Joystick:(OEApple2Button)direction withValue:(CGFloat)value forPlayer:(NSUInteger)player;
- (oneway void)didPushApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player;
- (oneway void)didReleaseApple2Button:(OEApple2Button)button forPlayer:(NSUInteger)player;

/*! Raw Mac keyboard events, as USB HID keyboard usage codes. */
- (oneway void)keyDown:(NSUInteger)keyCode;
- (oneway void)keyUp:(NSUInteger)keyCode;

@end
