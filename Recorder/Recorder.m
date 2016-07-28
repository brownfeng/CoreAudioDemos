//
//  main.m
//  Recorder
//
//  Created by brownfeng on 16/7/22.
//  Copyright © 2016年 brownfeng. All rights reserved.
//
#include <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#define kNumberRecordBuffers 3

#pragma mark user data struct 
// Insert Listing 4.3 here
typedef struct MyRecorder{
    AudioFileID recordFile;
    SInt64 recordPacket;
    Boolean running;
} MyRecorder;

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
// Insert Listings 4.20 and 4.21 here
//The first bit of work you put off in main() was to get a sample rate from the input hardware instead of just hard-coding a value that might not suit the current device.To inspect the current input device, you can use Audio Hardware Services.2 As with so much of Core Audio, you need to use a property getter. Actually, you’ll use two: First, in Listing 4.20, you use AudioHardwareServiceGetPropertyData() to get the kAudioHardwarePropertyDefaultInputDevice property.
//Listing 4.20 Getting Current Audio Input Device Info from Audio Hardware Services
OSStatus MyGetDefaultInputDeviceSampleRate(Float64 *outSampleRate) {
    OSStatus error;
    AudioDeviceID deviceID = 0;
    AudioObjectPropertyAddress propertyAddress;
    UInt32 propertySize;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(AudioDeviceID);
    error = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject,&propertyAddress, 0,NULL, &propertySize, &deviceID);
    if (error) return error;
    
    //Listing 4.21 Getting Input Device’s Sample Rate
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(Float64);
    error = AudioHardwareServiceGetPropertyData(deviceID,&propertyAddress,0,NULL, &propertySize, outSampleRate);
    return error;
}

//Listing 4.22 Copying Magic Cookie from Audio Queue to Audio File
static void MyCopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID theFile) {
    OSStatus error;
    UInt32 propertySize;
    error = AudioQueueGetPropertySize(queue, kAudioConverterCompressionMagicCookie,
                                      &propertySize);

    if (error == noErr && propertySize > 0){
        Byte *magicCookie = (Byte *)malloc(propertySize);
        CheckError(AudioQueueGetProperty(queue,kAudioQueueProperty_MagicCookie,magicCookie,&propertySize),"Couldn't get audio queue's magic cookie");
        CheckError(AudioFileSetProperty(theFile,kAudioFilePropertyMagicCookieData,propertySize,magicCookie),"Couldn't set audio file's magic cookie");
        free(magicCookie);
    }
    //As you can see, you copy over the magic cookie by first using AudioQueueGetPropertySize() to get the size of the kAudioConverterCompressionMagicCookie property from the queue. If the size is 0, no cookie exists and you’re done. Otherwise, you need to malloc() a byte buffer to hold the cookie, copy it to the buffer with AudioQueueGetProperty(), and then set the property on the file with AudioFileSetProperty(), sending the byte buffer as the property’s value.
}

//Listing 4.23 Computing Recording Buffer Size for an ASBD
static int MyComputeRecordBufferSize(const AudioStreamBasicDescription *format,AudioQueueRef queue,float seconds){
    // 重要的几个参数: 包, 帧, 字节
    /**
     - PCM，全称脉冲编码调制，是一种模拟信号的数字化的方法。
     - 采样精度（bit pre sample)，每个声音样本的采样位数。
     - 采样频率（sample rate）每秒钟采集多少个声音样本。
     - 声道（channel）：相互独立的音频信号数，单声道（mono）立体声（Stereo）
     - 语音帧（frame），In audio data a frame is one sample across all channels.
     - 数据包(packet), 封装的基本单元。通常一个Packet映射成一个Frame，但也有例外：一个packet包含多个frame。
     */
    int packets, frames, bytes;
    frames = (int)ceil(seconds * format->mSampleRate); //每个buffer中frames个数 = buffer时间 * sampleRate(采样率)
    //1. You first need to know how many frames (one sample for every channel) are in each buffer.You get this by multiplying the sample rate by the buffer duration. If the ASBD already has an mBytesPerFrame value, as in the case for constant bit rate formats such as PCM, you can trivially get the needed byte count by multiplying mBytesPerFrame by the frame count.
    if (format->mBytesPerFrame > 0){//如果bitRate(固定码率)是定值,那么 每个frame中的bytes就是固定的,因此一个buffer中的字节 = 帧数目 * 单帧bytes
        bytes = frames * format->mBytesPerFrame;
    }else{//如果是变化码率,就要从更高层去判断
        UInt32 maxPacketSize;
        //2. If that’s not the case, you need to work at the packet level.The easy case for this is a constant packet size, indicated by a nonzero mBytesPerPacket.
        if (format->mBytesPerPacket > 0){//如果每个packet的数据是确定的
           // Constant packet size
            maxPacketSize = format->mBytesPerPacket;
        } else {//如果每个pakect大小不固定,那么找到最大的packetSize
            //3. In the hard case, you get the audio queue property kAudioConverterPropertyMaximumOutputPacketSize, which gives you an upper bound to work with. Either way, you have a maxPacketSize, which you’ll need soon.

            // Get the largest single packet size possible
            UInt32 propertySize = sizeof(maxPacketSize);
            CheckError(AudioQueueGetProperty(queue,kAudioConverterPropertyMaximumOutputPacketSize,&maxPacketSize,&propertySize),"Couldn't get queue's maximum output packet size");
        }
        //4. But how many packets are there? The ASBD might provide a mFramesPerPacket value; in that case, you divide the frame count by mFramesPerPacket to get a packet count (packets).
        if (format->mFramesPerPacket > 0){
            packets = frames / format->mFramesPerPacket;//每个packet有多少frame -> 一共多少个packet
        }else{
            //5. Otherwise, assume the worst case of one frame per packet.
            // Worst-case scenario: 1 frame in a packet ,这是最坏的情况,一个packet中只有frame
            packets = frames;
        }
        //6. Finally, with a frames-per-packet value (which you force to be nonzero, just to be safe) and a maximum size per packet, you can multiply the two to get a maximum buffer size.
        // Sanity check
        if (packets == 0)
            packets = 1;
        bytes = packets * maxPacketSize; //那么就是最大的packetSize * packet
    }
    return bytes;
}



#pragma mark record callback function
// Replace with Listings 4.24-4.26
/**
When you created the audio queue with AudioQueueNewInput(), you passed in a function pointer to MyAQInputCallback, along with a user data pointer to recorder, which is the MyRecorder struct that we created in main().The callback is called every time the queue fills one of the buffers with freshly captured audio data; the callback function must do something interesting with this data. As long as the callback function is an empty stub, the program will run and the buffers will be delivered, but nothing inter- esting will happen because you’re not doing anything with the buffers.You need to take each buffer you receive from the queue and write it to the audio file.
 
 在record的回调方法中,需要获取其中从audio queue中传递过来的buffer,向buffer写入到file中(当然,也可以自己用方法存储其他的format)
 */

//Listing 4.24 Header for Audio Queue Callback and Casting of User Info Pointer
static void MyAQInputCallback(void *inUserData,
                              AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,//packets 个数
                              const AudioStreamPacketDescription *inPacketDesc)//packet信息
{
    MyRecorder *recorder = (MyRecorder *)inUserData;
    //Now you’re ready to write the audio data to the file.The audio data is provided by the callback parameter inBuffer (an AudioQueueBufferRef), with three other parameters providing a starting time stamp, a number of packets, and a pointer to packet descriptions.The latter two parameters are relevant only for variable bit rate formats, such as the AAC format you’re using. Fortunately, these parameters, along with the values you set aside in the MyRecorder struct, provide everything you need to call AudioFileWritePackets():
    /**
     - A file, which you put in the MyRecorder struct
     - A Boolean indicating whether you want to cache the data you’re writing (you
     don’t want to, in this case)
     - The size of the data buffer to write, which you get from the inBuffer parame-
     ter’s mAudioDataByteSize
     - Packet descriptions, provided by the callback’s inPacketDesc parameter
     - An index to which packet in the file to write, which is a running count that you keep track of in recorder’s recordPacket field
     - The number of packets to write, provided by the callback’s inNumPackets parameter
     - A pointer to the audio data, which is the inBuffer mAudioData pointer
     */
    
    //Listing 4.25 Writing Captured Packets to Audio File
    if (inNumPackets > 0){
        // Write packets to a file
        CheckError(AudioFileWritePackets(recorder->recordFile,FALSE,inBuffer->mAudioDataByteSize,inPacketDesc,recorder->recordPacket,&inNumPackets,inBuffer->mAudioData),"AudioFileWritePackets failed");
        // Increment the packet index
        recorder->recordPacket += inNumPackets;
    }
    //Now that you’ve used the buffer, you send it back to the queue (you re-enqueue it) in Listing 4.26 so it can be filled with newly captured audio data.
    
    //Listing 4.26 Re-enqueuing a Used Buffer
    if (recorder->running){
        CheckError(AudioQueueEnqueueBuffer(inQueue,inBuffer,0,NULL),"AudioQueueEnqueueBuffer failed");
    }
    
    //With this, you have completed your recording audio queue.To try it, launch System Preferences and go to the Sound panel. Make sure you have a working audio input device selected, such as an internal laptop microphone or an external USB microphone. Back in Xcode, bring up the Console window from the Run menu (Shift-„-R). Now build and run the application.You’ll see something like the following output:
    
}

//Listing 4.19 Function Definitions for Convenience Routines


#pragma mark main function
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MyRecorder recorder = {0};
        
        // Set up format
        AudioStreamBasicDescription recordFormat;
        memset(&recordFormat, 0, sizeof(recordFormat));
        //you use the mFormatID and mChannelsPerFrame field to indicate that you want to record as stereo AAC
        recordFormat.mFormatID = kAudioFormatMPEG4AAC;
        recordFormat.mChannelsPerFrame = 2;
        //You also need to define a sample rate.You could hardcode 44,100 Hz as you did in the previous chapters. However, because different input devices have different default sample rates, just imposing a value could force Core Audio to do a sample rate conversion you don’t need. If your input device could only capture at 8,000 Hz, forcing the ASBD to use 44,100 Hz would just cause Core Audio to do extra work in resampling the input audio—and it still wouldn’t sound any better.
        
        MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate);
        
        //For encoded formats, this is really all you need to fill in for the ASBD.You can’t know some of the ASBD fields, such as mBytesPerPacket, because they might depend on details of the encoding format or might even be variable. For formats other than PCM, fill in what you can and let Core Audio do the rest.  -- 其他的参数如果不是PCM,那么就让CoreAudio去设置就好.如果你需要自己encode format,ASBD都要设置
        //4.7 Filling in ASBD with AudioFormatGetProperty() - 因为format只传递了几个参数,其他的参数可以让coreAudio去设置,这里可以获取系统设置以后的参数
        UInt32 propSize = sizeof(recordFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &propSize, &recordFormat), "AudioFormatGetProperty failed!!");
        
        //4.8 Creating New Audio Queue for Input
        AudioQueueRef queue = {0};
        CheckError(AudioQueueNewInput(&recordFormat, MyAQInputCallback, &recorder, NULL, NULL, 0, &queue), "AudioQueueNewInput Error!!!");
        
        //A side effect of creating the queue is that it can provide you with a more complete AudioStreamBasicDescription than the one you set it up with.This happens because some of the fields can’t be filled in until Core Audio readies a codec for the queue.You can retrieve this ASBD from the queue by getting the property
        
        //4.9 Retrieving Filled-Out ASBD from Audio Queue
        
        UInt32 size = sizeof(recordFormat);
        
        CheckError(AudioQueueGetProperty(queue, kAudioConverterCurrentOutputStreamDescription, &recordFormat, &size), "Could't get queue property");
        
        //With this more detailed ASBD, you can now create the file into which you record the captured audio.You already used AudioFileCreateWithURL() to do this in Chapter 2; it takes a CFURLRef, a file type, an ASBD, some flags, and a pointer to receive the created AudioFileID. One change is needed for the version in Listing 4.10: Because this exam- ple hasn’t imported the Foundation framework (and doesn’t really need to), you’ll stick with the Core Foundation conventions for creating URLs instead of using NSURL and the toll-free bridge.
        //4.10 Creating Audio File for Output
        
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("output.caf"), kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileCreateWithURL(myFileURL, kAudioFileCAFType, &
                                          recordFormat, kAudioFileFlags_EraseFile, &recorder.recordFile), "AudioFileCreateWithURL failed!!");
        CFRelease(myFileURL);
        
        //The queue also gives you a magic cookie. As covered in Chapter 3, “Audio Processing with Core Audio,” a magic cookie is an opaque block of data that contains values that are unique to a given codec and that the ASBD hasn’t already accounted for. Some com- pressed formats use cookies; some don’t. Because your code might encounter new for- mats that use cookies, it’s wise to always be able to handle them. AAC is one format that uses magic cookies, so you need to get it from the audio queue and set it on the audio file. But this is a distraction from setting up the audio queue, so Listing 4.11 can just be a call to a convenience function that you’ll write later.
        //4.11 Calling a Convenience Method to Handle Magic Cookie
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        //With a queue and an audio file set up, you’re getting closer.The next item to think about is the buffers that the queue works with. In the recording case, the queue fills these buffers with captured audio and sends them to the callback function. However, you’re still responsible for creating these buffers and providing them to the queue before you start. And that begs an interesting question: How big are the buffers supposed to be? With constant bit rate encoding, such as PCM, you could multiply the bit rate by a buffer duration to figure out a good buffer size. For example, 44,100 samples/second × 2 channels × 2 bytes/channel × 1 second would mean you’d need 176,400 bytes to hold a second of 16-bit stereo PCM at 44.1 KHz. For a compressed format such as AAC, how- ever, you don’t know how effective the compression will be.Therefore, you don’t know how big a buffer to allocate.
        //The audio queue can give you this information, but because it’s a big job, you can set it aside with another convenience function that you’ll have to come back to.Assume that MyComputeRecordBufferSize() will take an ASBD, an audio queue, and a buffer duration in seconds and return an optimal size, and call this in Listing 4.12.
        //4.12 Calling a Convenience Function to Compute Recording Buffer Size
        int bufferByteSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5);
        
        //Assuming that works, let’s create some buffers and provide them to the queue, an action called enqueuing. At the top of the file, define the number of buffers to use. In Core Audio, including Apple’s examples, it’s common practice to use three buffers.The idea is, one buffer is being filled, one buffer is being drained, and the other is sitting in the queue as a spare, to account for lag.
        //You can use more—you’re welcome to recompile this program using a greater value for kNumberRecordBuffers when you’re finished writing it—but using less than three could get you in trouble.With two buffers, you’d risk dropouts by not having a spare buffer while the other two are being used.With only one buffer, you’ll almost certainly have dropouts because the one buffer the queue needs to record into will be unavailable as your callback processes it.
        
        //4.13 Allocating and Enqueuing Buffers
        int bufferIndex;
        for(bufferIndex = 0; bufferIndex< kNumberRecordBuffers;bufferIndex++) {
            AudioQueueBufferRef buffer;
            CheckError(AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer), "AudioQueueAllocateBuffer failed!");
            CheckError(AudioQueueEnqueueBuffer(queue, buffer, 0, NULL), "AudioQueueEnqueBuffer failed");
        }
        
        //Now that you have a queue with a set of buffers enqueued, you can start the queue, which starts recording.You do this with a call to AudioQueueStart(), shown in Listing 4.14, which takes the queue to start and an optional start time (use NULL to start immediately).
        //Listing 4.14 Starting the Audio Queue
        recorder.running = TRUE;
        CheckError(AudioQueueStart(queue, NULL), "AudioQueueStart failed");
        
        //Because you’re writing a command-line application, your UI will simply be to stop recording when the user presses a key on the keyboard, a behavior we implement in Listing 4.15.
        //Listing 4.15 Blocking on stdin to Continue Recording
        printf("Recording, press <return> to stop:\n");
        getchar();
        
        //When the user is done recording, you need to stop the queue so it can finish its work.You do this with AudioQueueStop(), in Listing 4.16.
        
        //Listing 4.16 Stopping the Audio Queue
        printf("* recording done *\n");
        recorder.running = FALSE;
        CheckError(AudioQueueStop(queue,TRUE),"AudioQueueStop failed");
        
        //You have a little more cleanup to do before main() can exit. In some cases, the magic cookie is updated during the recording process. Reset the cookie on the file before closing it.To do this, you can use your yet-to-be-written convenience function again, as shown in Listing 4.17.
        //Listing 4.17 Recalling the Magic Cookie Convenience Function
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        //Finally, you clean up by disposing of all resources allocated by the audio queue and closing the audio file. Listing 4.18 shows these clean-up calls.
        //Listing 4.18 Cleaning Up the Audio Queue and Audio File
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(recorder.recordFile);
    }
    return 0;
}
