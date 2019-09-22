//
//  NAudioFileStream.h
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NAudioFileStream;

typedef void(^ReadyToProducePackets)(NAudioFileStream *audioFileStream); /// 准备解析音频数据帧

typedef void(^AudioDataParsed)(NAudioFileStream *audioFileStream, NSArray *audioData); /// 解析音频数据帧

@interface NAudioFileStream : NSObject

@property (nonatomic, copy) ReadyToProducePackets readyToParsedData;

@property (nonatomic, copy) AudioDataParsed parsedData;

@property (nonatomic, assign, readonly) NSTimeInterval duration; /// 时长

- (instancetype)initWithFilePath:(NSString *)path;

- (void)parseData;

/// 拖动进度条，需要到几分几秒，而我们实际上操作的是文件，即寻址到第几个字节开始播放音频数据
- (void)seekToTime:(NSTimeInterval *)newSeekTime;

@end

NS_ASSUME_NONNULL_END
