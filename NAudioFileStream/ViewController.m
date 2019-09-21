//
//  ViewController.m
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "ViewController.h"
#import "NAudioFileStream.h"

@interface ViewController (){
    NAudioFileStream *audioFileStream;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"pf" ofType:@"mp3"];
    
    audioFileStream = [[NAudioFileStream alloc] initWithFilePath:path];
    /// 准备解析音频数据帧
    audioFileStream.readyToParsedData = ^(NAudioFileStream * _Nonnull audioFileStream) {
        NSLog(@">>>>>>>>>>> 准备解析音频数据帧 <<<<<<<<<<");
    };
    
    audioFileStream.parsedData = ^(NAudioFileStream * _Nonnull audioFileStream, NSArray * _Nonnull audioData) {
        NSLog(@">>>>>>>>>>> 解析音频数据帧 <<<<<<<<<<");
    };
    [audioFileStream parseData];
    
    NSLog(@"时长, %.2f", [audioFileStream duration]);
}

@end
