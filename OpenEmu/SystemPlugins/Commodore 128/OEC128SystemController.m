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

#import "OEC128SystemController.h"

@implementation OEC128SystemController

// The C128 shares every file type with the C64, and most files are C64
// software. OpenEmu gives a file to the one system that answers "yes"; the
// C64 answers "maybe" to everything, so the C128 answers "yes" only when the
// file (or its folder) is named as C128 software - "C128" or "128" as a word,
// as in TOSEC's "Commodore C128" sets - or is a 1571 double-sided disk.
// Everything else goes to the C64 without asking.
- (OEFileSupport)canHandleFile:(__kindof OEFile *)file
{
    if ([file.fileExtension.lowercaseString isEqualToString:@"d71"])
        return OEFileSupportYes;

    static NSRegularExpression *marker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        marker = [NSRegularExpression regularExpressionWithPattern:@"(^|[^0-9a-z])c?128([^0-9]|$)"
                                                           options:NSRegularExpressionCaseInsensitive error:nil];
    });

    NSURL *url = file.fileURL;
    for (NSString *name in @[ url.lastPathComponent, url.URLByDeletingLastPathComponent.lastPathComponent ])
    {
        if ([marker firstMatchInString:name options:0 range:NSMakeRange(0, name.length)] != nil)
            return OEFileSupportYes;
    }
    return OEFileSupportNo;
}

@end
