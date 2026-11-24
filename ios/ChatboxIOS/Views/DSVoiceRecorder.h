//
//  DSVoiceRecorder.h
//  ChatboxIOS
//
//  按住说话的录音器。输出 16kHz/16bit 单声道 WAV，
//  与 core 的 ASR 接口（multipart，audio/wav）直接对接，不需要转码。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSVoiceRecorder : NSObject

/// 开始录音（会配置 AVAudioSession 为 playAndRecord）
- (BOOL)startWithError:(NSError **)error;
/// 结束并保留文件，返回文件路径（过短会返回 nil）
- (nullable NSString *)finish;
/// 取消并删除临时文件
- (void)cancel;

/// 0..1 的输入音量，用于波形动画
@property (nonatomic, readonly) CGFloat level;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly, getter=isRecording) BOOL recording;

@end

NS_ASSUME_NONNULL_END
