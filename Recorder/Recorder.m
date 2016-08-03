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
typedef struct MyRecorder{
    AudioFileID recordFile;
    SInt64 recordPacket;
    Boolean running;
} MyRecorder;

#pragma mark utility functions
static void CheckError(OSStatus error, const char *operation) {
    if(error == noErr) return;
    
    char errorString[20];
    
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
        
    } else {
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

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
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(Float64);
    error = AudioHardwareServiceGetPropertyData(deviceID,&propertyAddress,0,NULL, &propertySize, outSampleRate);
    return error;
}

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
}

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
    if (format->mBytesPerFrame > 0){//如果bitRate(固定码率)是定值,那么 每个frame中的bytes就是固定的,因此一个buffer中的字节 = 帧数目 * 单帧bytes
        bytes = frames * format->mBytesPerFrame;
    }else{
        UInt32 maxPacketSize;
        if (format->mBytesPerPacket > 0){//如果每个packet的数据是确定的
            maxPacketSize = format->mBytesPerPacket;
        } else {
            UInt32 propertySize = sizeof(maxPacketSize);
            CheckError(AudioQueueGetProperty(queue,kAudioConverterPropertyMaximumOutputPacketSize,&maxPacketSize,&propertySize),"Couldn't get queue's maximum output packet size");
        }
        if (format->mFramesPerPacket > 0){
            packets = frames / format->mFramesPerPacket;//每个packet有多少frame -> 一共多少个packet
        }else{
            packets = frames;
        }
        if (packets == 0)
            packets = 1;
        bytes = packets * maxPacketSize; //那么就是最大的packetSize * packet
    }
    return bytes;
}



#pragma mark record callback function
static void MyAQInputCallback(void *inUserData,
                              AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,//packets 个数
                              const AudioStreamPacketDescription *inPacketDesc)//packet信息
{
    MyRecorder *recorder = (MyRecorder *)inUserData;
    if (inNumPackets > 0){
        CheckError(AudioFileWritePackets(recorder->recordFile,FALSE,inBuffer->mAudioDataByteSize,inPacketDesc,recorder->recordPacket,&inNumPackets,inBuffer->mAudioData),"AudioFileWritePackets failed");
        recorder->recordPacket += inNumPackets;
    }
    if (recorder->running){
        CheckError(AudioQueueEnqueueBuffer(inQueue,inBuffer,0,NULL),"AudioQueueEnqueueBuffer failed");
    }
}

#pragma mark main function
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MyRecorder recorder = {0};
        
        // Set up format
        AudioStreamBasicDescription recordFormat;
        memset(&recordFormat, 0, sizeof(recordFormat));
        recordFormat.mFormatID = kAudioFormatMPEG4AAC;
        recordFormat.mChannelsPerFrame = 2;
        
        MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate);
        
        UInt32 propSize = sizeof(recordFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &propSize, &recordFormat), "AudioFormatGetProperty failed!!");
        
        AudioQueueRef queue = {0};
        CheckError(AudioQueueNewInput(&recordFormat, MyAQInputCallback, &recorder, NULL, NULL, 0, &queue), "AudioQueueNewInput Error!!!");
        
        UInt32 size = sizeof(recordFormat);
        
        CheckError(AudioQueueGetProperty(queue, kAudioConverterCurrentOutputStreamDescription, &recordFormat, &size), "Could't get queue property");
        
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("output.caf"), kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileCreateWithURL(myFileURL, kAudioFileCAFType, &
                                          recordFormat, kAudioFileFlags_EraseFile, &recorder.recordFile), "AudioFileCreateWithURL failed!!");
        CFRelease(myFileURL);
        
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        int bufferByteSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5);
        int bufferIndex;
        for(bufferIndex = 0; bufferIndex< kNumberRecordBuffers;bufferIndex++) {
            AudioQueueBufferRef buffer;
            CheckError(AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer), "AudioQueueAllocateBuffer failed!");
            CheckError(AudioQueueEnqueueBuffer(queue, buffer, 0, NULL), "AudioQueueEnqueBuffer failed");
        }
        
        recorder.running = TRUE;
        CheckError(AudioQueueStart(queue, NULL), "AudioQueueStart failed");
        
        printf("Recording, press <return> to stop:\n");
        getchar();
        
        printf("* recording done *\n");
        recorder.running = FALSE;
        CheckError(AudioQueueStop(queue,TRUE),"AudioQueueStop failed");
        
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        //Finally, you clean up by disposing of all resources allocated by the audio queue and closing the audio file. Listing 4.18 shows these clean-up calls.
        //Listing 4.18 Cleaning Up the Audio Queue and Audio File
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(recorder.recordFile);
    }
    return 0;
}
