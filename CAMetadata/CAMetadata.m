//
//  main.m
//  CAMetadata
//
//  Created by brownfeng on 16/7/21.
//  Copyright © 2016年 brownfeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
/**
 你要随时做好准备应对未知结果，比如对MP3和AAC文件的不同级别的元数据支持。掌握CoreAudio并不仅仅是理解这些API，还包括提高实现的意识，这个库究竟是怎样工作的，它好在哪里，它的短处在哪。
 CoreAudio并不止是你调用它的语法，也包括它的语义。在某些情况下，语法正确的代码可能会在实践中出错，因为它违反了隐式协议、在不同的硬件中表现得不一样、又或者它在一个时间约束的回调中占用了太多的CPU时间。成功的CoreAudio程序猿在当事情并没有像他们预期的那样或者第一次运行时并不足够好的时候并不会鲁莽的继续下去。你必须尝试找出究竟发生了什么并想一个更好的方法。
 */

int main(int argc, const char * argv[]) {
    
    // argv表示传递给这个程序的参数数组，是一系列字符串
    // argc表示argv中元素的个数
    // 默认情况下argv只有一个元素：该程序本身的路径。而我们可以手动为其添加参数
    @autoreleasepool {
        if (argc < 2) {
            
            printf("Usage: no file !\n");
            return -1;
            
        }
        
        printf("%s",argv[0]);   // 1
        
        // 如果提供了路径，需要将它从c字符串转换成NSString或者CFStringRef这种苹果大多数框架都回用的。
        // stringByExpandingTildeInPath表示字符串会自动在前面加上~来代表根目录
        NSString * audioFilePath = [[NSString stringWithUTF8String:argv[1]] stringByExpandingTildeInPath];  // 2
        
        // AudioFile API使用的是URL来代表文件路径，所以把字符串再转换成URL
        NSURL * audioURL = [NSURL fileURLWithPath:audioFilePath];   // 3
        
        // CoreAuido使用AudioFileID类型来指代音频文件对象
        AudioFileID audioFile;  // 4
        
        // 大部分CoreAuido调用函数成功或失败的信号通过一个OSStatus类型的返回值来确认。
        // 除了noErr信号外的信号都代表发生了错误。
        // 我们应该在【所有的】CoreAuido函数调用后检查这个返回值因为前面已经发生错误了，后续的调用就显得毫无意义。
        // 比如，如果我们不能成功创建一个AuidoFileID对象，那么我们想从这个对象代表的那个文件中获取音频属性就完全是徒劳的。
        OSStatus theErr = noErr;    // 5
        
        // 来到了我们第一次调用的CoreAudio函数：AuidoFileOpenURL。它有4个参数：CFURLRef，文件权限的flag，文件类型提示和一个接收创建的AudioFileID对象的指针。
        // 第一个参数：我们可以直接通过强制类型转换把一个NSURL转换成CFURLRef（当然我们需要加上关键字__bridge。）
        // 第二个参数：文件操作权限，我们这里只需要读取数据的权限，所以传递一个枚举值（苹果一贯的命名规范）。
        // 第三个参数：我们不需要提供任何文件类型提示，所以传0，这样CoreAudio就会自己来解决（其实这个参数我都没搞懂是什么意思，反正一般传0就对了）
        // 第四个参数：传一个接收AudioFileID对象的指针，传入我们之前声明的AudioFileID类型的变量地址就行了。
        theErr = AudioFileOpenURL((__bridge CFURLRef)audioURL, kAudioFileReadPermission, 0, &audioFile); // 6
        
        // 如果上面的调用失败了，那么直接终止程序，因为以后的所有操作都没意义了。
        assert(theErr == noErr);    // 7
        
        // 为了拿到这个文件的元数据，我们将会被要求提供一个元数据属性，kAudioFilePropertyInfoDictionary。但是这个调用需要为返回的元数据分配内存。所以我们声明这么一个变量来接收我们需要分配的内存的size。
        UInt32 dictionarySize = 0;  // 8
        
        // 为了得到我们需要分配多少内存，我们调用AudioFileGetPropertyInfo函数，传入你想要拿到数据的那个文件的AudioFileID、你想要啥子信息、一个用来接收结果的指针、以及一个指向一个标识变量的指针用来指示这个属性是否是可写的（我们对此毫不在乎，所以传0）。
        theErr = AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyInfoDictionary, &dictionarySize, 0); // 9
        assert(theErr == noErr); // 10
        
        // 为了从一个音频文件获取属性（这里我们要的是这个音频文件的元数据）的调用，需要基于这个属性本身填充各种类型（这里是一个字典）。有的属性是数字，有的是字符串。文档和CoreAudio头文件描述了这些值。我们在第二个参数传入kAudioFilePropertyInfoDictionary就可以得到一个字典。所以我们声明这么一个变量它是CFDictionaryRef类型的对象（它可以随意转换成NSDictionary）。
        CFDictionaryRef dictionary; // 11
        
        // 啊，我们终于到了最终的时刻了，终于要开始获取属性了。调用AudioFileGetProperty函数，传入AudioFileID、一个常量（枚举类型，表示属性类型）、一个指向你准备好用来接收的size的指针、一个用来接收最终结果的指针（就是一个字典了）
        theErr = AudioFileGetProperty(audioFile, kAudioFilePropertyInfoDictionary, &dictionarySize, &dictionary); // 12
        
        assert(theErr == noErr); // 13
        
        // 我们来看看得到了什么。对任意的CoreFoundation或者Cocoa 对象都可以使用"%@"在格式化字符串里面来获取一个字典的字符串表示。
        NSLog(@"dictionary : %@", dictionary); // 14
        
        // Core Foundation没有提供自动内存释放，所以CFDictionaryRef对象在传入AudioFileGetProperty函数后它的retain count是1。我们用CFRelease函数来释放我们对这个对象的兴趣。
        CFRelease(dictionary); // 15
        
        // AudioFileID同样需要被清空。但是它本身并不是一个CoreFoundation对象，因此它不能通过调用CFRelease释放。取而代之的，它有自己的自杀方法：AudioFileClose()。
        theErr = AudioFileClose(audioFile); // 16
        assert(theErr == noErr); // 17
        
        // 结束了。我们用了二十多行代码，但是实际上都是为了调那么三个函数：打开一个文件、为元数据分配容器、获取元数据。
    }
    return 0;
}