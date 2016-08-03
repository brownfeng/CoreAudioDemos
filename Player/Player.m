//
//  main.m
//  Player

//With the exception of the callback function’s signature, this is identical to the previous chapter’s example.The other big difference is that the comment “open audio file” appears before you set up the audio format and queue.That’s because, instead of choos- ing a format to record to, you need to discover the format of the file you want to play and set up your queue accordingly.

//  Created by brownfeng on 16/7/23.
//  Copyright © 2016年 brownfeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>

#define kPlaybackFileLocation CFSTR("./output.caf")
#define kNumberPlaybackBuffers 3


#pragma mark utility functions
// Insert Listing 4.2 here

static void CheckError(OSStatus error, const char *operation) {
    if(error == noErr) return;
    
    char errorString[20];
    
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
        
    } else { // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

#pragma mark user data struct
//Listing 5.2 User Info Struct for Playback Audio Queue Callbacks
typedef struct MyPlayer {
    AudioFileID playbackFile;
    SInt64 packetPosition;
    UInt32 numPacketsToRead;
    AudioStreamPacketDescription *packetDescs;
    Boolean isDone;
} MyPlayer;

static void MyCopyEncoderCookieToQueue(AudioFileID theFile,AudioQueueRef queue ) {
    UInt32 propertySize;
    OSStatus result = AudioFileGetPropertyInfo (theFile,kAudioFilePropertyMagicCookieData, &propertySize,NULL);
    if (result == noErr && propertySize > 0) {
        Byte* magicCookie = (UInt8*)malloc(sizeof(UInt8) * propertySize);
        CheckError(AudioFileGetProperty (theFile,kAudioFilePropertyMagicCookieData,&propertySize, magicCookie),"Get cookie from file failed");
        CheckError(AudioQueueSetProperty(queue,kAudioQueueProperty_MagicCookie, magicCookie,propertySize),"Set cookie on queue failed");
        free(magicCookie);
    }
}

void CalculateBytesForTime (AudioFileID inAudioFile, AudioStreamBasicDescription inDesc,Float64 inSeconds, UInt32 *outBufferSize, UInt32 *outNumPackets){
    UInt32 maxPacketSize;
    UInt32 propSize = sizeof(maxPacketSize);
    CheckError(AudioFileGetProperty(inAudioFile,kAudioFilePropertyPacketSizeUpperBound,&propSize,&maxPacketSize),"Couldn't get file's max packet size");
    
    static const int maxBufferSize = 0x10000; static const int minBufferSize = 0x4000;
    if (inDesc.mFramesPerPacket) {
        Float64 numPacketsForTime = inDesc.mSampleRate /inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    }else{
        *outBufferSize = maxBufferSize > maxPacketSize ?maxBufferSize : maxPacketSize;
    }
    
    
    if (*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize){
        *outBufferSize = maxBufferSize;
    }
    else {
        if (*outBufferSize < minBufferSize){
            *outBufferSize = minBufferSize;
        }
    }
    *outNumPackets = *outBufferSize / maxPacketSize;
}
#pragma mark playback callback function
// Replace with Listings 5.16-5.19
static void MyAQOutputCallback(void *inUserData, AudioQueueRef inAQ,AudioQueueBufferRef inCompleteAQBuffer)
{
    MyPlayer *aqp = (MyPlayer*)inUserData; if (aqp->isDone) return;

    UInt32 numBytes;
    UInt32 nPackets = aqp->numPacketsToRead;
    CheckError(AudioFileReadPackets(aqp->playbackFile,false,&numBytes,aqp->packetDescs, aqp->packetPosition,&nPackets, inCompleteAQBuffer->mAudioData),"AudioFileReadPackets failed");
    if (nPackets > 0) {
        inCompleteAQBuffer->mAudioDataByteSize = numBytes;
        AudioQueueEnqueueBuffer(inAQ,inCompleteAQBuffer, (aqp->packetDescs ? nPackets : 0), aqp->packetDescs);
        aqp->packetPosition += nPackets;
    }else {
        CheckError(AudioQueueStop(inAQ, false),
                   "AudioQueueStop failed"); aqp->isDone = true;
    }
}

#pragma mark main function
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MyPlayer player = {0};
        //Next, you need to find the audio file you’re working with. Use a #define at the top of the file to create a string with the full path to an audio file on your hard drive. It can be in any of the formats Core Audio understands, such as .mp3, .aac, .m4a, .wav, .aif, and so on. However, Core Audio cannot read files in the iTunes “protected” format (.m4p).
        
        //Listing 5.4 Opening an Audio File for Input
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,kPlaybackFileLocation,kCFURLPOSIXPathStyle,false);
        
        CheckError(AudioFileOpenURL(myFileURL,kAudioFileReadPermission,0,&player.playbackFile),"AudioFileOpenURL failed");
        CFRelease(myFileURL);
        
        //Now that you’ve opened the audio file, you can inspect its properties. In Listing 5.5, you need to get the format of the file’s audio as an AudioStreamBasicDescription so you can set up a playback queue with that format.
        //Listing 5.5 Getting the ASBD from an Audio File
        AudioStreamBasicDescription dataFormat;
        UInt32 propSize = sizeof(dataFormat);
        CheckError(AudioFileGetProperty(player.playbackFile, kAudioFilePropertyDataFormat,&propSize, &dataFormat),"Couldn't get file's data format");
        
        //Now that you have the dataFormat, you’re ready to create the audio queue for play- back with the AudioQueueNewOutput() function, as shown in Listing 5.6.
        
        //Listing 5.6 Creating a New Audio Queue for Output
        AudioQueueRef queue;
        CheckError(AudioQueueNewOutput(&dataFormat,MyAQOutputCallback,&player,NULL,NULL,0,&queue),"AudioQueueNewOutput failed");
        //Again, this is just like how you set up the recording queue, except that the callback function (MyAQOutputCallback) has a much different signature.You’ll write the callback later; all that’s needed now is a no-op implementation, which you sketched out earlier.
        
        //Setting Up the Playback Buffers
        //The next few steps all involve setting up the buffers that the queue uses.This is an involved process because you have to account for the encoding characteristics of the audio in the file you’re opening: whether it’s compressed or uncompressed, variable or constant bit rate, and so on.
        //Part of the challenge here comes from working with packets, which wasn’t a concern with LPCM and which you basically just passed from queue to file in the last chapter.To refresh your memory, a packet is a collection of frames, which, in turn, are collections of samples. Because the frame size is variable in a packet, you can’t just encounter a buffer of audio data and know what to do with it, as you can with LPCM, in which every frame has a fixed size.With encoded formats such as MP3 and AAC, you need an array of AudioStreamPacketDescriptions to provide a map of the contents of the audio buffer, to tell you where each packet begins and what’s in it.
        //To be able to allocate the buffers the queue will use, you need to inspect the file and its audio encoding to figure out how big of a data buffer you’ll need and how many packets you will be reading on each callback.This will be a distraction from setting up the audio queue, so put it aside as a utility function that you’ll write a little later.
        //5.7 Calling a Convenience Function to Calculate Playback Buffer Size and Number of Packets to Read
        UInt32 bufferByteSize;
        CalculateBytesForTime(player.playbackFile,dataFormat,0.5,&bufferByteSize,&player.numPacketsToRead);
        //As you can see, this function takes the file to read, the ASBD, and a buffer duration in seconds, and populates variables representing an appropriate buffer size and how many packets of audio you will want to read from the file in each callback.You’ll see how this function works later.
        
        //Listing 5.8 Allocating Memory for Packet Descriptions Array
        bool isFormatVBR = (dataFormat.mBytesPerPacket == 0 ||dataFormat.mFramesPerPacket == 0);
        if (isFormatVBR){
            player.packetDescs = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription) *player.numPacketsToRead);
        }else {
            player.packetDescs = NULL;
        }
        
        //You’re almost ready to create and use the buffers, but first you have to set up the magic cookie on the queue. As with recording, the audio format might have some magic cookie data that you need to preserve. For playback, you read the magic cookie as a property of the audio file and write it to the queue. But let’s put that off for a bit by just having Listing 5.9 call a utility function that you’ll come back to write later.
        
        //Listing 5.9 Calling a Convenience Method to Handle Magic Cookie
        MyCopyEncoderCookieToQueue(player.playbackFile, queue);
        
        //Now that the queue has been configured and you know how big your buffers need to be, you can create and enqueue some buffers. Start with a #define at the top of the file of how many buffers you want to use; again, 3 is often an appropriate value—you have one buffer being played, one filled, and one in the queue to account for lag:
        
        //Listing 5.10 Allocating and Enqueuing Playback Buffers
        AudioQueueBufferRef buffers[kNumberPlaybackBuffers];
        player.isDone = false;
        player.packetPosition = 0;
        int i;
        for (i = 0; i < kNumberPlaybackBuffers; ++i){
            CheckError(AudioQueueAllocateBuffer(queue,bufferByteSize,&buffers[i]),"AudioQueueAllocateBuffer failed");
            MyAQOutputCallback(&player, queue, buffers[i]);
            if (player.isDone){
                break;
            }
        }
        
        //As in the recording example, you create new buffers with AudioQueueAllocate Buffer(), passing in the queue, the buffer size, and a pointer to receive the created buffer.Then you fill the buffer by manually calling your yet-to-be-written callback.You might wonder why you’re not enqueuing the buffers in this loop.Your callback will have to do because the queue will be sending it drained buffers to fill and enqueue.You can count on that enqueuing behavior here, too.
        //The callback also must check to see whether it has exhausted all the audio in the file. If so, it sets the isDone variable in the MyPlayer struct. If that happens when you’re priming the queue, stop filling buffers—there’s no more data available for them. Of course, that would happen for only a tiny file, less than 1.5 seconds (3 buffers × 0.5 seconds each).
        
        //At this point, the audio queue has three buffers of audio data ready to play.You can now start the queue with AudioQueueStart(), as shown in Listing 5.11. As it starts playing, the queue plays the contents of each buffer and calls the callback function MyAQOutputCallback() to refill the buffer with new audio from the file. The main() function doesn’t need to do anything here but wait for the end of the audio.
        
        //Listing 5.11 Starting the Playback Audio Queue
        
        CheckError(AudioQueueStart(queue,NULL),"AudioQueueStart failed");
        printf("Playing...\n");
        do
        {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
        } while (!player.isDone);
        
        
        //When this loop exits, you’re done reading audio from the file. However, some buffers in the queue might still have data to be played out.With three 0.5-second buffers, con- tinuing playback for another 2 seconds ensures that everything in the queue gets played. Listing 5.12 provides this wait.
        
        //Listing 5.12 Delaying to Ensure Queue Plays Out Buffered Audio
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false);
        
        //When you’re done, Listing 5.13 cleans up the queue as before, by stopping the queue and cleaning up the queue and the audio file.
        //Listing 5.13 Cleaning Up the Audio Queue and Audio File
        player.isDone = true;
        CheckError(AudioQueueStop(queue,TRUE),"AudioQueueStop failed");
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(player.playbackFile);
    }
    return 0;
}
