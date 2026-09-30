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

#import "OEApple2GSSystemController.h"

// 3.5" disks: 800K (double-sided) or 400K (single-sided) as raw blocks.
static const NSUInteger OEApple2GSDisk800K = 819200;
static const NSUInteger OEApple2GSDisk400K = 409600;

// WOZ images say in their INFO chunk whether they are 5.25" (1) or 3.5" (2).
static NSInteger OEWozDiskType(OEFile *file)
{
    NSString *magic = [file readASCIIStringInRange:NSMakeRange(0, 4)];
    if (![magic isEqualToString:@"WOZ1"] && ![magic isEqualToString:@"WOZ2"])
        return 0;
    if (![[file readASCIIStringInRange:NSMakeRange(12, 4)] isEqualToString:@"INFO"])
        return 0;
    NSData *type = [file readDataInRange:NSMakeRange(21, 1)];
    return type.length == 1 ? ((const uint8_t *)type.bytes)[0] : 0;
}

@implementation OEApple2GSSystemController

// The Apple IIgs library takes 3.5" disks; 5.25" disks go to the Apple IIe
// (whose controller claims only 5.25" sizes), so imports never have to ask.
// The 5.25" types are still listed in OEFileSuffixes so that a 5.25" disk
// dropped on the Apple IIgs in the library is imported there.
- (OEFileSupport)canHandleFile:(__kindof OEFile *)file
{
    NSString *ext = file.fileExtension.lowercaseString;
    NSUInteger size = file.fileSize;

    if ([ext isEqualToString:@"po"])
    {
        return (size == OEApple2GSDisk800K || size == OEApple2GSDisk400K) ? OEFileSupportYes : OEFileSupportNo;
    }

    if ([ext isEqualToString:@"2mg"])
    {
        // 2IMG header: block count (little-endian) at offset 0x14.
        if (![[file readASCIIStringInRange:NSMakeRange(0, 4)] isEqualToString:@"2IMG"])
            return OEFileSupportNo;
        NSData *data = [file readDataInRange:NSMakeRange(0x14, 4)];
        if (data.length != 4)
            return OEFileSupportNo;
        const uint8_t *b = data.bytes;
        uint32_t blocks = b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24);
        return (blocks == 1600 || blocks == 800) ? OEFileSupportYes : OEFileSupportNo;
    }

    if ([ext isEqualToString:@"woz"])
    {
        return OEWozDiskType(file) == 2 ? OEFileSupportYes : OEFileSupportNo;
    }

    if ([ext isEqualToString:@"dc"] || [ext isEqualToString:@"dc42"])
    {
        // DiskCopy 4.2: data size (big-endian) at 0x40, magic 0x0100 at 0x52.
        NSData *header = [file readDataInRange:NSMakeRange(0x40, 0x14)];
        if (header.length != 0x14)
            return OEFileSupportNo;
        const uint8_t *b = header.bytes;
        uint32_t dataSize = ((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
        BOOL magic = b[0x12] == 0x01 && b[0x13] == 0x00;
        return (magic && (dataSize == OEApple2GSDisk800K || dataSize == OEApple2GSDisk400K)) ? OEFileSupportYes : OEFileSupportNo;
    }

    return OEFileSupportNo;
}

@end
