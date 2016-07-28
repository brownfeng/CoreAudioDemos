//
//  main.m
//  CAStreamFormatTester
//
//  Created by brownfeng on 16/7/22.
//  Copyright © 2016年 brownfeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/**
***different pairings of file type and data formats*****
 
 This tells you that AIFFs can handle only a small amount of variety in PCM formats, differing only in bit depth.The mFormatFlags are the same for every ASBD in the array. But what do they mean? The flags are a bit field, so with a value of 14, you know that the bits for 0x2, 0x4, and 0x8 are enabled (because 0x2 + 0x4 + 0x8 = 0xE, which is 14 in decimal).

 This shows that WAV files take a different style of PCM. The 0x2 bit of mFormatFlags is never set, which means that kAudioFormatFlagIsBigEndian is always false; that, in turn, means that WAV files always use little-endian PCM. Also, the last two results set the 0x1 bit, kAudioFormatFlagIsFloat, meaning that the format is not limited to just integer samples.
 
 This shows CAF taking a variety of formats, using both integer and floating-point samples (signaled by bit 0x1 being set) and signed and unsigned integers. It supports all but one of the formats provided by AIFF and WAV.

 */
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        //To use the property called kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, you have to pass Core Audio a structure called AudioFileTypeAndFormatID (getting this property seems to be the only use for the struct).This structure has two members, a file type and a data format, both of which you can set with Core Audio constants found in the documentation or the AudioFile.h and AudioFormat.h headers. For starters, let’s use an AIFF file with PCM, as you created in the previous chapter.
        AudioFileTypeAndFormatID fileTypeAndFormat;
        fileTypeAndFormat.mFileType = kAudioFileAIFFType;
        fileTypeAndFormat.mFormatID = kAudioFormatLinearPCM;
       
        //As before, you prepare an OSStatus to receive result codes from your Core Audio calls.You also prepare a UInt32 to hold the size of the info you’re interested in, which you have to negotiate before actually retrieving the info.
        OSStatus audioErr = noErr;
        UInt32 infoSize = 0;
        
        //Just as when you retrieved an audio file’s property in Listing 1.1, getting a global info property requires you to query in advance for the size of the property and to store the size in a pointer to a UInt32. The global info calls take a specifier, which acts like an argument to the property call and depends on the property you’re asking for (the docs for the properties describe what kind of specifier, if any, they expect). In the case of kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, you provide the AudioFileTypeAndFormatID.
        audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, sizeof(fileTypeAndFormat), &fileTypeAndFormat, &infoSize);
        assert(audioErr == noErr);
        
        //The AudioFileGetGlobalInfoSize calls tells you how much data you’ll receive when you actually get the global property, so you need to malloc some memory to hold the property.
        AudioStreamBasicDescription *asbds = malloc (infoSize);
        
        //With everything set up, you call AudioFileGetGlobalInfo to get the kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, passing in the AudioFileTypeAndFormatID and the size of the buffer you’ve set up, along with a pointer to the buffer itself.
        audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,sizeof(fileTypeAndFormat), &fileTypeAndFormat, &infoSize,asbds);
        
        assert (audioErr == noErr);
        
        int asbdCount = infoSize / sizeof (AudioStreamBasicDescription);
        //The docs tell you that the property call provides an array of AudioStreamBasicDescriptions, so you can figure out the length of the array by dividing the data size by the size of an ASBD.That enables you to set up a for loop to investigate the ASBDs.
        for(int i=0;i<asbdCount;i++){
            
            //The docs stated that the three ASBD fields that get filled in are mFormatID, mFormatFlags, and mBitsPerChannel. It’s handy to log the format ID, but to make it legible, you have to convert it out of the four-character code numeric for- mat and into a readable four-character string.You do this with an endian swap because the UInt32 representation will reorder the bits from their original pseudo- string representation.
            UInt32 format4cc = CFSwapInt32HostToBig(asbds[i].mFormatID);
            
            //To pretty print the mFormatId’s endian-swapped representation, you can use the format string %4.4s to force NSLog (or printf) to treat the pointer as an array of 8-bit characters that is exactly four characters long.The mFormatFlags and mBitsPerChannel members are a bit field and numeric value, so just print them as ints for now.
            NSLog (@"%d: mFormatId: %4.4s, mFormatFlags: %d, mBitsPerChannel: %d",i,(char*)&format4cc,asbds[i].mFormatFlags,asbds[i].mBitsPerChannel);
        }
        
        //Because you malloc()’d memory to hold the ASBD array, you need to be sure to free() it when you’re done with it so you don’t leak.
        free (asbds);
        NSLog(@"done!!!!");
    }
    return 0;
}
