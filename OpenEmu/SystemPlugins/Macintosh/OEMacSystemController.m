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

#import "OEMacSystemController.h"

// Mac floppies: 400K (single-sided) and 800K (double-sided) as raw blocks,
// alone or after a DiskCopy 4.2 header. (1.4 MB HD disks need a later Mac
// than the Plus, so they aren't claimed yet.)
static const NSUInteger OEMacDisk400K  = 409600;
static const NSUInteger OEMacDisk800K  = 819200;
static const NSUInteger OEDiskCopyHeaderSize = 84;

@implementation OEMacSystemController

// Disk image extensions are shared with the Apple II family (and .dsk/.img
// with other systems), so claim only images that are Mac disks: an HFS or
// MFS volume, or Mac boot blocks. Everything else is left to other systems.
- (OEFileSupport)canHandleFile:(__kindof OEFile *)file
{
    NSString *ext = file.fileExtension.lowercaseString;

    if ([ext isEqualToString:@"moof"])
    {
        // Applesauce's bit-level format for Mac floppies.
        return [[file readASCIIStringInRange:NSMakeRange(0, 4)] isEqualToString:@"MOOF"] ? OEFileSupportYes : OEFileSupportNo;
    }

    NSUInteger offset = 0, size = file.fileSize;
    NSData *header = [file readDataInRange:NSMakeRange(0, OEDiskCopyHeaderSize)];
    if (header.length == OEDiskCopyHeaderSize)
    {
        // DiskCopy 4.2: name length (< 64) at 0, data size (big-endian) at
        // 0x40, magic 0x0100 at 0x52.
        const uint8_t *b = header.bytes;
        if (b[0] < 64 && b[0x52] == 0x01 && b[0x53] == 0x00)
        {
            offset = OEDiskCopyHeaderSize;
            size = ((NSUInteger)b[0x40] << 24) | ((NSUInteger)b[0x41] << 16) | ((NSUInteger)b[0x42] << 8) | b[0x43];
        }
    }
    if (size != OEMacDisk400K && size != OEMacDisk800K)
        return OEFileSupportNo;

    // Volume signature in block 2: "BD" for HFS, 0xD2D7 for MFS.
    NSData *volume = [file readDataInRange:NSMakeRange(offset + 1024, 2)];
    if (volume.length == 2)
    {
        const uint8_t *v = volume.bytes;
        if ((v[0] == 'B' && v[1] == 'D') || (v[0] == 0xD2 && v[1] == 0xD7))
            return OEFileSupportYes;
    }

    // Boot blocks ("LK") on a disk with its own file system.
    NSData *boot = [file readDataInRange:NSMakeRange(offset, 2)];
    if (boot.length == 2 && ((const uint8_t *)boot.bytes)[0] == 'L' && ((const uint8_t *)boot.bytes)[1] == 'K')
        return OEFileSupportYes;

    return OEFileSupportNo;
}

@end
