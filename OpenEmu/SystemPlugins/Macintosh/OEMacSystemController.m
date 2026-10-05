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

// Mac floppies: 400K (single-sided), 800K (double-sided) and 1.4 MB (the
// LC II's SuperDrive) as raw blocks, alone or after a DiskCopy 4.2 header;
// whole SCSI hard drives (raw or MAME CHD); empty drive images to set up;
// and bare volumes, which the core explains it can't start (they need
// converting). CD images are only inserted into a running Mac, not imported.
static const NSUInteger OEMacDisk400K  = 409600;
static const NSUInteger OEMacDisk800K  = 819200;
static const NSUInteger OEMacDisk1440K = 1474560;
static const NSUInteger OEDiskCopyHeaderSize = 84;

@implementation OEMacSystemController

static BOOL OEMacIsFloppySize(NSUInteger size)
{
    return size == OEMacDisk400K || size == OEMacDisk800K || size == OEMacDisk1440K;
}

// Disk image extensions are shared with the Apple II family (and .dsk/.img
// with other systems), so claim only images that are Mac disks. Everything
// else is left to other systems.
- (OEFileSupport)canHandleFile:(__kindof OEFile *)file
{
    NSString *ext = file.fileExtension.lowercaseString;

    if ([ext isEqualToString:@"moof"])
    {
        // Applesauce's bit-level format for Mac floppies.
        return [[file readASCIIStringInRange:NSMakeRange(0, 4)] isEqualToString:@"MOOF"] ? OEFileSupportYes : OEFileSupportNo;
    }
    if ([ext isEqualToString:@"iso"] || [ext isEqualToString:@"cdr"] || [ext isEqualToString:@"toast"])
        return OEFileSupportNo;  // inserted while running, not games of their own

    if ([ext isEqualToString:@"chd"])
    {
        // A MAME CHD holding a hard disk: its first metadata entry is "GDDD"
        // (CDs are CHT2/CHCD/CHGD, and belong to other systems).
        if (![[file readASCIIStringInRange:NSMakeRange(0, 8)] isEqualToString:@"MComprHD"])
            return OEFileSupportNo;
        NSData *offsetData = [file readDataInRange:NSMakeRange(0x30, 8)];
        if (offsetData.length != 8)
            return OEFileSupportNo;
        uint64_t metaOffset = 0;
        for (int i = 0; i < 8; i++)
            metaOffset = (metaOffset << 8) | ((const uint8_t *)offsetData.bytes)[i];
        NSString *tag = [file readASCIIStringInRange:NSMakeRange((NSUInteger)metaOffset, 4)];
        return [tag isEqualToString:@"GDDD"] ? OEFileSupportYes : OEFileSupportNo;
    }

    NSUInteger offset = 0, size = file.fileSize;
    BOOL diskCopy = NO;
    NSData *header = [file readDataInRange:NSMakeRange(0, OEDiskCopyHeaderSize)];
    if (header.length == OEDiskCopyHeaderSize)
    {
        // DiskCopy 4.2: name length (< 64) at 0, data size (big-endian) at
        // 0x40, magic 0x0100 at 0x52.
        const uint8_t *b = header.bytes;
        if (b[0] < 64 && b[0x52] == 0x01 && b[0x53] == 0x00)
        {
            diskCopy = YES;
            offset = OEDiskCopyHeaderSize;
            size = ((NSUInteger)b[0x40] << 24) | ((NSUInteger)b[0x41] << 16) | ((NSUInteger)b[0x42] << 8) | b[0x43];
        }
    }

    NSData *start = [file readDataInRange:NSMakeRange(offset, 2)];
    NSData *volume = [file readDataInRange:NSMakeRange(offset + 1024, 2)];
    const uint8_t *s = start.length == 2 ? start.bytes : NULL;
    const uint8_t *v = volume.length == 2 ? volume.bytes : NULL;
    BOOL hfsOrMFS = v && ((v[0] == 'B' && v[1] == 'D') || (v[0] == 0xD2 && v[1] == 0xD7));
    BOOL bootBlocks = s && s[0] == 'L' && s[1] == 'K';

    if (diskCopy || OEMacIsFloppySize(size))
    {
        // Volume signature in block 2 ("BD" HFS, 0xD2D7 MFS), or boot blocks
        // on a disk with its own file system.
        return (hfsOrMFS || bootBlocks) ? OEFileSupportYes : OEFileSupportNo;
    }

    // Larger than a floppy: a hard drive. Only extensions hard drives use.
    if (![@[ @"hda", @"hd", @"img", @"dsk", @"image" ] containsObject:ext])
        return OEFileSupportNo;
    if (size % 512 != 0 || size < 2 * 1024 * 1024)
        return OEFileSupportNo;

    // A whole drive: Driver Descriptor Map ("ER") then a partition map ("PM").
    NSData *pm = [file readDataInRange:NSMakeRange(512, 2)];
    if (s && s[0] == 'E' && s[1] == 'R' && pm.length == 2 &&
        ((const uint8_t *)pm.bytes)[0] == 'P' && ((const uint8_t *)pm.bytes)[1] == 'M')
        return OEFileSupportYes;

    // A Basilisk II / Mini vMac volume (the core says how to convert it).
    if (hfsOrMFS)
        return OEFileSupportYes;

    // An empty image to set up as a drive (made with `mkfile`): .hda/.hd
    // only, since an empty .img or .dsk could be anything.
    if ([ext isEqualToString:@"hda"] || [ext isEqualToString:@"hd"])
    {
        NSData *first = [file readDataInRange:NSMakeRange(0, 1024)];
        const uint8_t *f = first.bytes;
        BOOL blank = first.length == 1024;
        for (NSUInteger i = 0; blank && i < 1024; i++)
            blank = (f[i] == 0);
        if (blank)
            return OEFileSupportYes;
    }
    return OEFileSupportNo;
}

@end
