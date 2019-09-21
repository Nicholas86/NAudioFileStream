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
@protocol NAudioFileStreamDelegate <NSObject>
@required
- (void)audioFileStream:(NAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData;
@optional
- (void)audioFileStreamReadyToProducePackets:(NAudioFileStream *)audioFileStream;
@end

typedef void(^ReadyToProducePackets)(NAudioFileStream *audioFileStream); /// 准备解析音频数据帧

typedef void(^AudioDataParsed)(NAudioFileStream *audioFileStream, NSArray *audioData); /// 解析音频数据帧

@interface NAudioFileStream : NSObject

@property (nonatomic, copy) ReadyToProducePackets readyToParsedData;

@property (nonatomic, copy) AudioDataParsed parsedData;

@property (nonatomic, assign, readonly) NSTimeInterval duration; /// 时长

- (instancetype)initWithFilePath:(NSString *)path;

- (void)parseData;

@end

NS_ASSUME_NONNULL_END
