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

#import "OEApple2SystemController.h"

// 5.25" disk image sizes. A .dsk/.do/.po image is a raw sector dump:
// 35 tracks x 16 sectors x 256 bytes (DOS 3.3 / ProDOS), or 35 x 13 x 256
// for DOS 3.2-era disks. A .nib image is 35 tracks x 6656 nibbles.
static const NSUInteger OEApple2DiskSize16Sector = 143360;
static const NSUInteger OEApple2DiskSize13Sector = 116480;
static const NSUInteger OEApple2NibSize          = 232960;

@implementation OEApple2SystemController

// ".dsk" is shared with MSX, so claim only files whose size or header proves
// they are Apple II disks. Anything we answer "yes" to is imported straight
// into the Apple IIe library without asking; "no" leaves it to other systems.
- (OEFileSupport)canHandleFile:(__kindof OEFile *)file
{
    NSString *ext = file.fileExtension.lowercaseString;
    NSUInteger size = file.fileSize;

    if ([ext isEqualToString:@"dsk"] || [ext isEqualToString:@"do"] || [ext isEqualToString:@"po"])
    {
        if (size == OEApple2DiskSize16Sector || size == OEApple2DiskSize13Sector)
            return OEFileSupportYes;
        return OEFileSupportNo;
    }

    if ([ext isEqualToString:@"nib"])
    {
        return size == OEApple2NibSize ? OEFileSupportYes : OEFileSupportNo;
    }

    if ([ext isEqualToString:@"woz"])
    {
        // WOZ images say in their INFO chunk whether they are 5.25" (1) or
        // 3.5" (2); 3.5" disks belong to the Apple IIgs.
        NSString *magic = [file readASCIIStringInRange:NSMakeRange(0, 4)];
        if (![magic isEqualToString:@"WOZ1"] && ![magic isEqualToString:@"WOZ2"])
            return OEFileSupportNo;
        if (![[file readASCIIStringInRange:NSMakeRange(12, 4)] isEqualToString:@"INFO"])
            return OEFileSupportYes;
        NSData *type = [file readDataInRange:NSMakeRange(21, 1)];
        BOOL threeAndAHalf = type.length == 1 && ((const uint8_t *)type.bytes)[0] == 2;
        return threeAndAHalf ? OEFileSupportNo : OEFileSupportYes;
    }

    return OEFileSupportUncertain;
}

@end
