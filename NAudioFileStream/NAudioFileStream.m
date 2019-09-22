//
//  NAudioFileStream.m
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioFileStream.h"
#import <AudioToolbox/AudioToolbox.h>
#import "NParseAudioData.h"

#define kAudioFileBufferSize 2048       //文件读取数据的缓冲区大小

#define  BitRateEstimationMaxPackets 5000
#define  BitRateEstimationMinPackets 10

@interface NAudioFileStream ()
{
@private
    BOOL _discontinuous;
    AudioFileStreamID _audioFileStreamID; ///
    
    SInt64 _dataOffset;
    NSTimeInterval _packetDuration; // 当前已读取了多少个packet
    UInt64 _audioDataByteCount;
    NSInteger _fileLength;        // Length of the file in bytes

    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;
    
    UInt64 _seekByteOffset;    // Seek offset within the file in bytes
    NSTimeInterval *_seekTime;
}

@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL readyToProducePackets;

@property (nonatomic, assign) AudioStreamBasicDescription audioStreamBasicDescription;
@property (nonatomic, strong) NSFileHandle *audioFileHandle;
@property (nonatomic, strong) NSData *audioFileData; // 每次读取到的文件数据

//@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign, readwrite) NSTimeInterval duration; /// 时长
@property (nonatomic, assign) UInt32 bitRate; /// 速率

@property (nonatomic, assign) UInt32 maxPacketSize;

@end

@implementation NAudioFileStream

- (instancetype)initWithFilePath:(NSString *)path;
{
    self = [super init];
    if (self) {
        self.path = path;
        self.audioFileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
        _fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        [self createAudioFileStream];
    }return self;
}

- (void)createAudioFileStream
{
    /*
         AudioFileStreamOpen的参数说明如下：
         1. inClientData：用户指定的数据，用于传递给回调函数，这里我们指定(__bridge LocalAudioPlayer*)self
         2. inPropertyListenerProc：当解析到一个音频信息时，将回调该方法
         3. inPacketsProc：当解析到一个音频帧时，将回调该方法
         4. inFileTypeHint：指明音频数据的格式，如果你不知道音频数据的格式，可以传0
         5. outAudioFileStream：AudioFileStreamID实例，需保存供后续使用
     */
    
    OSStatus status = AudioFileStreamOpen((__bridge void *)self, NAudioFileStreamPropertyListener, NAudioFileStreamPacketCallBack, 0, &_audioFileStreamID);
    
    if (status != noErr) {
        _audioFileStreamID = NULL;
    }
    
    NSError *error;
    
    [self _errorForOSStatus:status error:&error];
}

- (void)parseData
{
    /// 解析数据
    do {
        self.audioFileData = [self.audioFileHandle readDataOfLength:kAudioFileBufferSize];
        
        /*
            参数的说明如下：
            1. inAudioFileStream：AudioFileStreamID实例，由AudioFileStreamOpen打开
            2. inDataByteSize：此次解析的数据字节大小
            3. inData：此次解析的数据大小
            4. inFlags：数据解析标志，其中只有一个值kAudioFileStreamParseFlag_Discontinuity = 1，表示解析的数据是否是不连续的，目前我们可以传0。
        */
        
        OSStatus error = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)self.audioFileData.length, self.audioFileData.bytes, 0);
        
        if (error != noErr) {
            NSLog(@"AudioFileStreamParseBytes 失败");
        }
        
    } while (self.audioFileData != nil && self.audioFileData.length > 0);
    
    
    [self.audioFileHandle closeFile];
    [self close]; /// 关闭文件
}

/// 拖动进度条，需要到几分几秒，而我们实际上操作的是文件，即寻址到第几个字节开始播放音频数据
- (void)seekToTime:(NSTimeInterval *)newSeekTime
{
    if (_bitRate == 0.0 || _fileLength <= 0){
        NSLog(@"_bitRate, _fileLength is 0");
        return;
    }
    
    /// 近似seekByteOffset = 数据偏移 + seekToTime对应的近似字节数
    _seekByteOffset = _dataOffset + (*newSeekTime / _duration) * (_fileLength - _dataOffset);
    
//    if (_seekByteOffset > _fileLength - 2 * packetBufferSize){
//        _seekByteOffset = fileLength - 2 * packetBufferSize;
//    }
    
    _seekTime = newSeekTime;
    
    if (_packetDuration > 0) {
        /*
         1. 首先需要计算每个packet对应的时长_packetDuration
         2. 再然后计算_packetDuration位置seekToPacket
         */
        SInt64 seekToPacket = floor(*newSeekTime / _packetDuration);
        
        UInt32 ioFlags = 0;
        SInt64 outDataByteOffset;
        OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
        if ((status == noErr) && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated)){
            *_seekTime -= ((_seekByteOffset - _dataOffset) - outDataByteOffset) * 8.0 / _bitRate;
            _seekByteOffset = outDataByteOffset + _dataOffset;
        }
    }
    
    NSLog(@"_seekByteOffset: %llu", _seekByteOffset);
    
    /// 继续播放的操作, audioQueue处理
}

#pragma mark - open & close
- (void)_closeAudioFileStream
{
    if (self.available) {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
}

- (void)close
{
    [self _closeAudioFileStream];
}

/// 音频文件读取速率
- (void)calculateBitRate
{
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets && _processedPacketsCount <= BitRateEstimationMaxPackets){
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        _bitRate = 8.0 * averagePacketByteSize / _packetDuration;
    }
}

/// 音频文件总时长
- (void)calculateDuration
{
    if (_fileLength > 0 && _bitRate > 0){
        _duration = ((_fileLength - _dataOffset) * 8.0) / _bitRate;
    }
}

/// 首先需要计算每个packet对应的时长
- (void)calculatePacketDuration
{
    if (_audioStreamBasicDescription.mSampleRate > 0) {
        _packetDuration = _audioStreamBasicDescription.mFramesPerPacket / _audioStreamBasicDescription.mSampleRate;
    }
    
    NSLog(@"当前已读取了多少个packet, %.2f", _packetDuration);
}

#pragma mark - private method
- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
//    NSLog(@"handleAudioFileStreamProperty: %d", propertyID);

    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        /*
         该属性告诉我们，已经解析到完整的音频帧数据，准备产生音频帧，之后会调用到另外一个回调函数。之后便是音频数据帧的解析。
         */
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        
        if (status != noErr || _maxPacketSize == 0) {
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_ReadyToProducePackets, &sizeOfUInt32, &_maxPacketSize);
        }
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_ReadyToProducePackets <<<<<<<");
        
        NSLog(@">>>>>>> 准备音频数据帧的解析 <<<<<<<");

        /// 准备解析音频数据帧
        if (self.readyToParsedData) {
            self.readyToParsedData(self);
        }
        
    }else if (propertyID == kAudioFileStreamProperty_DataOffset){
        /*
    表示音频数据在整个音频文件的offset，因为大多数音频文件都会有一个文件头。个值在seek时会发挥比较大的作用，音频的seek并不是直接seek文件位置而seek时间（比如seek到2分10秒的位置），seek时会根据时间计算出音频数据的字节offset然后需要再加上音频数据的offset才能得到在文件中的真正offset。
         */
        
        SInt64 offset;
        UInt32 offsetSize = sizeof(offset);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
        if (status){
//            [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            return;
        }
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_DataOffset <<<<<<<");

        _dataOffset = offset; 
        
    }else if (propertyID == kAudioFileStreamProperty_AudioDataByteCount){
        UInt32 audioDataByteCount;
        UInt32 byteCountSize = sizeof(audioDataByteCount);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
        
        if (status == noErr) {
//            NSLog(@"audioDataByteCount : %u, byteCountSize: %u",audioDataByteCount,byteCountSize);
        }
        
        _audioDataByteCount = audioDataByteCount;

        NSLog(@">>>>>>> kAudioFileStreamProperty_AudioDataByteCount <<<<<<<");
    }else if (propertyID == kAudioFileStreamProperty_DataFormat){
        /*
         表示音频文件结构信息，是一个AudioStreamBasicDescription
         */
        if (_audioStreamBasicDescription.mSampleRate == 0){
            UInt32 asbdSize = sizeof(_audioStreamBasicDescription);
            
            // get the stream format.
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_audioStreamBasicDescription);
            
            if (status == noErr) {
                //            NSLog(@"audioDataByteCount : %u, byteCountSize: %u",audioDataByteCount,byteCountSize);
            }
            
            /// 首先需要计算每个packet对应的时长
            [self calculatePacketDuration];

            //        if (status){
            ////                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
            //            return;
            //        }
        }
    
        NSLog(@">>>>>>> kAudioFileStreamProperty_DataFormat <<<<<<<");
    } else if (propertyID == kAudioFileStreamProperty_FormatList){
        Boolean outWriteable;
        UInt32 formatListSize;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
        if (status == noErr){
            AudioFormatListItem *formatList = malloc(formatListSize);
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            if (status == noErr){
                UInt32 supportedFormatsSize;
                status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                if (status != noErr){
                    free(formatList);
                    return;
                }
                
                UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
                status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
                if (status != noErr){
                    free(formatList);
                    free(supportedFormats);
                    return;
                }
                
                for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem)){
                    AudioStreamBasicDescription format = formatList[i].mASBD;
                    for (UInt32 j = 0; j < supportedFormatCount; ++j){
                        if (format.mFormatID == supportedFormats[j]){
                            _audioStreamBasicDescription = format;
                            [self calculatePacketDuration];
                            break;
                        }
                    }
                }
                free(supportedFormats);
            }
            free(formatList);
        }
        
        NSLog(@">>>>>>> kAudioFileStreamProperty_FormatList <<<<<<<");
    }
    
}

- (void)handleAudioFileStreamPackets:(const void *)packets numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescription:(AudioStreamPacketDescription *)packetDescriptions
{
    if (_discontinuous) {
        _discontinuous = NO;
    }
    
    if (numberOfBytes == 0 || numberOfPackets == 0) {
        return;
    }
    
//    NSLog(@">>>>>>> handleAudioFileStreamPackets <<<<<<<");

    BOOL deletePackDesc = NO;
    
    if (packetDescriptions == NULL) {
        deletePackDesc = YES;
        UInt32 packetSize = numberOfBytes / numberOfPackets;
        AudioStreamPacketDescription *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*numberOfPackets);
        for (int i = 0; i < numberOfPackets; i++) {
            UInt32 packetOffset = packetSize * i;
            descriptions[i].mStartOffset  = packetOffset;
            descriptions[i].mVariableFramesInPacket = 0;
            if (i == numberOfPackets-1) {
                descriptions[i].mDataByteSize = numberOfPackets-packetOffset;
            }else{
                descriptions[i].mDataByteSize = packetSize;
            }
        }
        packetDescriptions = descriptions;
    }
    
    NSMutableArray *parseDataArray = [NSMutableArray array];
    
    for (int i = 0; i < numberOfPackets; i++) {
        SInt64 packetOffset = packetDescriptions[i].mStartOffset;
        NParseAudioData *parsedData = [NParseAudioData parsedAudioDataWithBytes:packets+packetOffset packetDescription:packetDescriptions[i]];
//        NSLog(@"packetdata : %@",parsedData.data);
        [parseDataArray addObject:parsedData];

        if (_processedPacketsCount < BitRateEstimationMaxPackets) {
            _processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
            _processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
    }
    
    /// 解析音频数据帧
    if (self.parsedData) {
        self.parsedData(self, parseDataArray);
    }
    
    if (deletePackDesc) {
        free(packetDescriptions);
    }
}

#pragma mark - static callbacks
static void NAudioFileStreamPropertyListener(void *inClientData,AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *inFlags)
{
    NAudioFileStream *audioFileStream = (__bridge NAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}

static void NAudioFileStreamPacketCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescrrptions)
{
    NAudioFileStream *audioFileStream = (__bridge NAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamPackets:inInputData numberOfBytes:inNumberBytes numberOfPackets:inNumberPackets packetDescription:inPacketDescrrptions];
}

@end
