//
//  main.m
//  CAToneFileGenerator
//
//  Created by brownfeng on 16/7/21.
//  Copyright © 2016年 brownfeng. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

// 把文件名define到一个宏里面，这样一会可以改名字。
// 这里我们创建一个方波，是最简单的一种波的形式
#define FILENAME_FORMAT @"%0.3f-square.aif"

#define SAMPLE_RATE 44100               // define一个44100采样每秒的采样率
#define DURATION    5.0                 // define你想要创建多少秒的音频

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf ("Usage: CAToneFileGenerator n\n(where n is tone in Hz)");
            return -1;
        }
        
        // 和上次一样，我们需要一个命令行参数
        // 这一次是一个浮点型数作为你想要生成的音的频率
        // 如果你想要运行这个程序，就要到Scheme Editor里面去像上次那样设置参数。
        // 你可以把音符频率设置成261.626，这是钢琴上中央C的频率，或者440，是在C之上的A（叫做中央A）
        double hz = atof(argv[1]);
        assert(hz > 0);
        NSLog(@"generating %f hz tone", hz);
        
        // 这两行代码生成一个文件路径，使用了我们的宏和频率来生成名字文件名，比如261.626-square.aif
        // 然后它们来生成一个NSURL因为Audio File Services函数要的是URL而不是文件路径
        NSString * fileName = [NSString stringWithFormat:FILENAME_FORMAT,hz];
        NSString * filePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:fileName];
        NSLog(@"%@",filePath);
        NSURL * fileURL = [NSURL fileURLWithPath:filePath];
        
        // prepare the format
        // 要创建一个音频文件，你必须要提供一个这个文件包含的音频的描述。
        // 你要用到的可能是CoreAudio最重要和最常见的数据结构，AudioStreamBasicDescription
        // 这个结构体定义了一个音频流最普遍的特征：它有多少声道，它在什么格式下，比特率等等
        AudioStreamBasicDescription asbd;
        
        // 在有些情况下，CoreAudio会为一个AudioStreamBasicDescription填充一些区域而你在编程的时候完全不知道
        // 要这样做，这些区域必须被初始化为0。作为一次普通的实践，请一直要在设置它们任何一个之前使用memset()把ASBD的区域清空
        memset(&asbd, 0, sizeof(asbd));
        // 接下来的8行代码使用ASBD各自的区域来描述你要写入文件的数据。
        // 这里，它们描述了一个流：
        // 只有一个声道（单声道）的PCM，数据率为44100
        // 使用16位采样（再说一次，和CD一样），所以每一帧为2个字节（1声道*2字节的采样数据）
        // LPCM不使用分组（它们只对可变比特率格式有用）所以bytesPerFrame和bytesPerPackt相等。
        // 其他针对一个音符的区域是mFormatFlags，它的内容是不同的，基于你用的格式
        // 对于PCM，你必须表明你的采样是大端模式（字节或者文字的的高位在数字上对其意义的影响更大）亦或相反。
        // 这里你要写入一个AIFF文件，它可以只取大端模式的PCM，所以你需要在你的ASBD中设置它。
        // 你同样需要表明采样的数值格式（kAudioFormatFlagIsSignedInteger）
        // 以及，你传入的第三个标识来表明你的采样值使用每一个字节的所有可用位(kAudioFormatFlagIsPacked)。
        // mFormatFlags是一个bit区域，所以你可以使用算术或运算符（|）把这些标识结合到一起
        asbd.mSampleRate = SAMPLE_RATE;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        asbd.mBitsPerChannel = 16;
        asbd.mChannelsPerFrame = 1;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerFrame = 2;
        asbd.mBytesPerPacket = 2;
        
        // set up the file
        AudioFileID audioFile;
        OSStatus audioErr = noErr;
        
        // 现在你可以让CoreAudio创建一个AudioFileID了，准备用来写在你设置好的URL
        // AudioFileCreateWithURL()函数接受一个URL（注意到你再次使用桥接来从一个Cocoa NSURL转换到CoreFoundation CFURLRef）
        // 一个用来描述AIFF文件格式的常量
        // 一个指向描述音频数据的AudioStreamBasicDescription的指针
        // 一个行为标识（在这里，表明你希望如果已存在同名的文件就把它覆盖掉）
        // 一个用来填充我们创建的AudioFileID的指针
        audioErr = AudioFileCreateWithURL((__bridge CFURLRef)fileURL,
                                          kAudioFileAIFFType,
                                          &asbd,
                                          kAudioFileFlags_EraseFile,
                                          &audioFile);
        assert(audioErr == noErr);
        
        // start writing samples
        // 你马上就可以准备完毕写采样了。
        // 在我们进入这个写采样的循环之前，你要计算一下在每秒SAMPLE_RATE个采样下对于DURATION秒的声音需要多少采样
        // 随着一个计数变量，sampleCount
        // 你定义了bytesToWrite作为局部变量，只因为写采样的调用需要一个纸箱UInt32的指针。
        // 你不能就直接把这个值放进参数
        long maxSampleCount = SAMPLE_RATE * DURATION;
        long sampleCount = 0;
        UInt32 bytesToWrite = 2;
        
        // 你需要跟踪在一个波长里面有多少采样
        // 然后你就可以计算组成一个波需要多少采样值
        double wavelengthInSamples = SAMPLE_RATE / hz;
        
        while (sampleCount < maxSampleCount) {
            
            
            for (int i = 0; i < wavelengthInSamples; i++) {
                // Square wave
                SInt16 sample;
                
                // 对于第一个例子，你将会写最简单的波之一，方波。其采样是非常简单的
                // 对于波长的前半部分，你要提供一个最大值，对于波长的剩下部分，你提供一个最小值
                // 所以仅有两个可能的采样值可能会呗用到：一个高的和一个低的。
                // 对于16位有符号整数，你要使用C常量来代表最大值和最小值：SHRT_MAX和SHRT_MIN
                if (i < wavelengthInSamples/2) {
                    
                    // 你在ASBD中声明了将大端有符号整数作为音频格式，所以你不得不在这个格式中小心地持有者2字节的采样
                    // 现代Mac运行中小端模式的Intel CPU上，而且iPhone的ARM处理器也是小端的
                    // 所以你需要把CPU表示的字符切换为大端模式。CoreFoundation函数CFSwapInt16HostToBig()会帮到你。
                    // 这个调用同样可以在大端模式的CPU上，比如老Mac上的PowerPC，因为它会意识到主机的格式是大端模式然后就什么也不做
                    sample = CFSwapInt16HostToBig(SHRT_MAX);
                } else {
                    sample = CFSwapInt16HostToBig(SHRT_MIN);
                }
                
                // 已经计算好了你的采样，使用AudioFileWriteBytes()把它写进文件。
                // 这个调用接受5个参数：AudioFileID用来写入、缓存标识、你要写的音频数据的偏移量
                // 你要写的字符数和一个指向被写入字符的指针。
                // 你可以使用这个函数因为你拥有常量比特率数据。
                // 在更多的一般情况下，比如写一个有损格式，你必须使用更负责的AudioFileWritePackets()
                
                audioErr = AudioFileWriteBytes(audioFile, false, sampleCount*2, &bytesToWrite, &sample);
                assert(audioErr == noErr);
                
                // 增量sampleCount，然后你就一点点地将新数据写进文件
                sampleCount ++;
            }
        }
        
        
        // 最后调用AudioFileClose()来完成并关闭文件
        audioErr = AudioFileClose(audioFile); 
        assert(audioErr == noErr);
        NSLog(@"wrote %ld samples",sampleCount);
        
    }
    return 0;
}