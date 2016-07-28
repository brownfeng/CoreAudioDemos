## Demo 概要

这个项目是`Learning core Audio`书中的内容,包括了5个小的Terminal Demo.

### CAMetadata 

一个简单的使用`AudioFile Service`对音频文件读取,使用`AudioFileGetPropertyInfo`获取音频文件属性的Demo.


### CAToneFileGenerator 

一个单频率声音的生成Demo.

主要使用`AudioStreamBasicDescription`进行音频数据format设置,然后通过`AudioFileCreateWithURL`创建音频文件,使用`AudioFileWriteBytes`直接将raw data写入`AudioFile`.

### CAStreamFormatTester

这个Demo主要用来显示: audio fileType和 [Audio file format](https://en.wikipedia.org/wiki/Audio_file_format) 的区别.

音频格式和文件格式是两个不同的概念.具体可以百度.

### Recorder

使用`AudioQueueService`进行录音.录音以后的数据直接通过`AudioFileWritePackets`写入文件系统.其实在回调函数中,对于录音的PCM数据可以进行其他的音频格式或者压缩算法的封装.在demo中还展示了如何进行AudioQueueBuffer的大小的合理计算方法.

### Player(不完整)

与前一个Recorder的Demo相反,使用`AudioQueueService`直接播放raw LPCM音频数据.具体的Demo可以看前面提到的书中的内容,里面的代码是完整的.

> 使用`AudioQueueService`进行录音和播放最好的实例是Apple官方的SpeakHere,现在官方已经下载不到了.

> 这里有一份可用的Demo: https://github.com/brownfeng/SpeakHere
