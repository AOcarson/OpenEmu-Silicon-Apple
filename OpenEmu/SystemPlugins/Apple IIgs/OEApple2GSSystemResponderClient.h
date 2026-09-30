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

/*! Controls exposed to OpenEmu's controller preferences for the Apple IIgs.
 *
 *  Same layout as the Apple IIe's (the values match OEApple2Button): an
 *  analog joystick, buttons 0 and 1, Control-Reset, the MAME menu and six
 *  spare buttons for MAME's Input Settings. The IIgs also takes the Mac's
 *  mouse, forwarded by the responder. */
typedef enum
{
    OEApple2GSJoystickUp,
    OEApple2GSJoystickDown,
    OEApple2GSJoystickLeft,
    OEApple2GSJoystickRight,
    OEApple2GSButton0,
    OEApple2GSButton1,
    OEApple2GSReset,
    OEApple2GSMAMEMenu,
    OEApple2GSExtra1,
    OEApple2GSExtra2,
    OEApple2GSExtra3,
    OEApple2GSExtra4,
    OEApple2GSExtra5,
    OEApple2GSExtra6,
    OEApple2GSButtonCount
} OEApple2GSButton;

@protocol OEApple2GSSystemResponderClient <OESystemResponderClient, NSObject>

/*! value is 0.0 (released) to 1.0 (full deflection) for one direction. */
- (oneway void)didMoveApple2GSJoystick:(OEApple2GSButton)direction withValue:(CGFloat)value forPlayer:(NSUInteger)player;
- (oneway void)didPushApple2GSButton:(OEApple2GSButton)button forPlayer:(NSUInteger)player;
- (oneway void)didReleaseApple2GSButton:(OEApple2GSButton)button forPlayer:(NSUInteger)player;

/*! Raw Mac keyboard events, as USB HID keyboard usage codes. */
- (oneway void)keyDown:(NSUInteger)keyCode;
- (oneway void)keyUp:(NSUInteger)keyCode;

/*! The Mac pointer over the game, in OpenEmu's game-view coordinates (the
 *  core turns successive points into mouse movement). */
- (oneway void)mouseMovedAtPoint:(OEIntPoint)point;
- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point;
- (oneway void)leftMouseUp;
- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point;
- (oneway void)rightMouseUp;

@end
