//
//  SKDocumentController.m
//  Skim
//
//  Created by Christiaan Hofman on 5/21/07.
/*
 This software is Copyright (c) 2007-2008
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SKDocumentController.h"
#import "SKDocument.h"
#import "SKDownloadController.h"
#import "NSString_SKExtensions.h"
#import "NSURL_SKExtensions.h"
#import "SKStringConstants.h"
#import "OBUtilities.h"

// See CFBundleTypeName in Info.plist
NSString *SKPDFDocumentType = nil; /* set to NSPDFPboardType, not @"NSPDFPboardType" */
NSString *SKPDFBundleDocumentType = @"PDF Bundle";
NSString *SKEmbeddedPDFDocumentType = @"PDF With Embedded Notes";
NSString *SKBarePDFDocumentType = @"PDF Without Notes";
NSString *SKNotesDocumentType = @"Skim Notes";
NSString *SKNotesTextDocumentType = @"Notes as Text";
NSString *SKNotesRTFDocumentType = @"Notes as RTF";
NSString *SKNotesRTFDDocumentType = @"Notes as RTFD";
NSString *SKNotesFDFDocumentType = @"Notes as FDF";
NSString *SKPostScriptDocumentType = @"PostScript document";
NSString *SKDVIDocumentType = @"DVI document";

NSString *SKPDFDocumentUTI = @"com.adobe.pdf";
NSString *SKPDFBundleDocumentUTI = @"net.sourceforge.skim-app.pdfd";
NSString *SKEmbeddedPDFDocumentUTI = @"net.sourceforge.skim-app.embedded.pdf";
NSString *SKBarePDFDocumentUTI = @"net.sourceforge.skim-app.bare.pdf";
NSString *SKNotesDocumentUTI = @"net.sourceforge.skim-app.skimnotes";
NSString *SKTextDocumentUTI = @"public.plain-text";
NSString *SKRTFDocumentUTI = @"com.apple.rtf";
NSString *SKRTFDDocumentUTI = @"com.apple.rtfd";
NSString *SKFDFDocumentUTI = @"com.adobe.fdf"; // I don't know the UTI for fdf, is there one?
NSString *SKPostScriptDocumentUTI = @"com.adobe.postscript";
NSString *SKDVIDocumentUTI = @"net.sourceforge.skim-app.dvi"; // I don't know the UTI for dvi, is there one?

@implementation SKDocumentController

+ (void)initialize {
    OBINITIALIZE;
    
    if (nil == SKPDFDocumentType)
        SKPDFDocumentType = [NSPDFPboardType copy];
}

- (NSString *)typeFromFileExtension:(NSString *)fileExtensionOrHFSFileType {
	NSString *type = [super typeFromFileExtension:fileExtensionOrHFSFileType];
    if ([type isEqualToString:SKEmbeddedPDFDocumentType] || [type isEqualToString:SKBarePDFDocumentType]) {
        // fix of bug when reading a PDF file
        // this is interpreted as SKEmbeddedPDFDocumentType, even though we don't declare that as a readable type
        type = NSPDFPboardType;
    }
	return type;
}

static inline NSString *SKPDFDocumentTypeOrUTI(void) {
    return floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4 ? SKPDFDocumentType : SKPDFDocumentUTI;
}

static inline NSString *SKPostScriptDocumentTypeOrUTI(void) {
    return floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_4 ? SKPostScriptDocumentType : SKPostScriptDocumentUTI;
}

- (NSString *)typeForContentsOfURL:(NSURL *)inAbsoluteURL error:(NSError **)outError {
    unsigned int headerLength = 5;
    
    static NSData *pdfHeaderData = nil;
    if (nil == pdfHeaderData) {
        char *h = "%PDF-";
        pdfHeaderData = [[NSData alloc] initWithBytes:h length:headerLength];
    }
    static NSData *psHeaderData = nil;
    if (nil == psHeaderData) {
        char *h = "%!PS-";
        psHeaderData = [[NSData alloc] initWithBytes:h length:headerLength];
    }
    
    NSError *error = nil;
    NSString *type = [super typeForContentsOfURL:inAbsoluteURL error:&error];
    
    if (type == nil || [type isEqualToString:SKNotesTextDocumentType] || [type isEqualToString:SKTextDocumentUTI]) {
        if ([inAbsoluteURL isFileURL]) {
            NSString *fileName = [inAbsoluteURL path];
            NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:fileName];
            NSData *leadingData = [fh readDataOfLength:headerLength];
            if ([leadingData length] >= [pdfHeaderData length] && [pdfHeaderData isEqual:[leadingData subdataWithRange:NSMakeRange(0, [pdfHeaderData length])]]) {
                type = SKPostScriptDocumentTypeOrUTI();
            } else if ([leadingData length] >= [psHeaderData length] && [psHeaderData isEqual:[leadingData subdataWithRange:NSMakeRange(0, [psHeaderData length])]]) {
                type = SKPostScriptDocumentTypeOrUTI();
            }
        }
        if (type == nil && outError)
            *outError = error;
    }
    
    return type;
}

static NSData *convertTIFFDataToPDF(NSData *tiffData)
{
    // this should accept any image data types we're likely to run across, but PICT returns a zero size image
    CGImageSourceRef imsrc = CGImageSourceCreateWithData((CFDataRef)tiffData, (CFDictionaryRef)[NSDictionary dictionaryWithObject:(id)kUTTypeTIFF forKey:(id)kCGImageSourceTypeIdentifierHint]);

    NSMutableData *pdfData = nil;
    
    if (CGImageSourceGetCount(imsrc)) {
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imsrc, 0, NULL);

        pdfData = [NSMutableData dataWithCapacity:[tiffData length]];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)pdfData);
        
        // create full size image, assuming pixel == point
        const CGRect rect = CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
        
        CGContextRef ctxt = CGPDFContextCreate(consumer, &rect, NULL);
        CGPDFContextBeginPage(ctxt, NULL);
        CGContextDrawImage(ctxt, rect, cgImage);
        CGPDFContextEndPage(ctxt);
        
        CGContextFlush(ctxt);

        CGDataConsumerRelease(consumer);
        CGContextRelease(ctxt);
        CGImageRelease(cgImage);
    }
    
    CFRelease(imsrc);

    return pdfData;
}

- (id)openDocumentWithContentsOfPasteboard:(NSPasteboard *)pboard typesMask:(int)mask error:(NSError **)outError {
    // allow any filter services to convert to TIFF data if we can't get PDF or PS directly
    pboard = [NSPasteboard pasteboardByFilteringTypesInPasteboard:pboard];
    NSString *pboardType;
    id document = nil;
    
    if ((mask & SKImagePboardTypesMask) && (pboardType = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSPDFPboardType, NSPostScriptPboardType, NSTIFFPboardType, nil]])) {
        
        NSData *data = [pboard dataForType:pboardType];
        
        // if it's image data, convert to PDF, then explicitly set the pboard type to PDF
        if ([pboardType isEqualToString:NSTIFFPboardType]) {
            data = convertTIFFDataToPDF(data);
            pboardType = NSPDFPboardType;
        }
        
        NSString *type = [pboardType isEqualToString:NSPostScriptPboardType] ? SKPostScriptDocumentTypeOrUTI() : SKPDFDocumentTypeOrUTI();
        NSError *error = nil;
        
        document = [self makeUntitledDocumentOfType:type error:&error];
        
        if ([document readFromData:data ofType:type error:&error]) {
            [self addDocument:document];
            [document makeWindowControllers];
            [document showWindows];
        } else {
            document = nil;
            if (outError)
                *outError = error;
        }
        
    } else if ((mask & SKURLPboardTypesMask) && (pboardType = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSURLPboardType, SKWeblocFilePboardType, NSStringPboardType, nil]])) {
        
        NSURL *theURL = [NSURL URLFromPasteboardAnyType:pboard];
        if ([theURL isFileURL]) {
            document = [self openDocumentWithContentsOfURL:theURL display:YES error:outError];
        } else if (theURL) {
            [[SKDownloadController sharedDownloadController] addDownloadForURL:theURL];
            if ([[NSUserDefaults standardUserDefaults] boolForKey:SKAutoOpenDownloadsWindowKey])
                [[SKDownloadController sharedDownloadController] showWindow:self];
            if (outError)
                *outError = nil;
        } else if (outError) {
            *outError = [NSError errorWithDomain:SKDocumentErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to load data from clipboard", @"Error description"), NSLocalizedDescriptionKey, nil]];
        }
        
    } else if (outError) {
        *outError = [NSError errorWithDomain:SKDocumentErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to load data from clipboard", @"Error description"), NSLocalizedDescriptionKey, nil]];
    }
    
    return document;
}

- (void)newDocumentFromClipboard:(id)sender {
    NSError *error = nil;
    id document = [self openDocumentWithContentsOfPasteboard:[NSPasteboard generalPasteboard] typesMask:SKImagePboardTypesMask | SKURLPboardTypesMask error:&error];
    
    if (document == nil && error)
        [NSApp presentError:error];
}

- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)outError {
    NSString *type = [self typeForContentsOfURL:absoluteURL error:NULL];
    if ([type isEqualToString:SKNotesDocumentType] || [type isEqualToString:SKNotesDocumentUTI]) {
        NSAppleEventDescriptor *event = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];
        if ([event eventID] == kAEOpenDocuments && [event descriptorForKeyword:keyAESearchText]) {
            NSString *pdfFile = [[absoluteURL path] stringByReplacingPathExtension:@"pdf"];
            BOOL isDir;
            if ([[NSFileManager defaultManager] fileExistsAtPath:pdfFile isDirectory:&isDir] && isDir == NO)
                absoluteURL = [NSURL fileURLWithPath:pdfFile];
        }
    }
    return [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument error:outError];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
    if ([anItem action] == @selector(newDocumentFromClipboard:)) {
        NSPasteboard *pboard = [NSPasteboard pasteboardByFilteringTypesInPasteboard:[NSPasteboard generalPasteboard]];
        return ([pboard availableTypeFromArray:[NSArray arrayWithObjects:NSPDFPboardType, NSPostScriptPboardType, NSTIFFPboardType, NSURLPboardType, SKWeblocFilePboardType, NSStringPboardType, nil]] != nil);
    } else if ([[SKDocumentController superclass] instancesRespondToSelector:_cmd]) {
        return [super validateUserInterfaceItem:anItem];
    } else
        return YES;
}

@end
