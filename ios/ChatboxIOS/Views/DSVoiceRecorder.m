//
//  DSVoiceRecorder.m
//  ChatboxIOS
//

#import "DSVoiceRecorder.h"
#import <AVFoundation/AVFoundation.h>

@interface DSVoiceRecorder () <AVAudioRecorderDelegate>
@property (nonatomic, strong, nullable) AVAudioRecorder *recorder;
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic, strong, nullable) NSTimer *meter;
@property (nonatomic, assign, readwrite) CGFloat level;
@property (nonatomic, assign, readwrite) BOOL recording;
@end

@implementation DSVoiceRecorder

- (BOOL)startWithError:(NSError **)error {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  // 录音需要 playAndRecord + 允许蓝牙（与官方语音输入一致）
  if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                      error:error]) return NO;
  if (![session setActive:YES error:error]) return NO;

  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"voice-%lld.wav", (long long)([NSDate date].timeIntervalSince1970 * 1000)]];
  NSDictionary *settings = @{
    AVFormatIDKey: @(kAudioFormatLinearPCM),
    AVSampleRateKey: @16000,
    AVNumberOfChannelsKey: @1,
    AVLinearPCMBitDepthKey: @16,
    AVLinearPCMIsFloatKey: @NO,
    AVLinearPCMIsBigEndianKey: @NO,
  };
  NSError *e = nil;
  AVAudioRecorder *rec = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path]
                                                     settings:settings
                                                        error:&e];
  if (!rec) {
    if (error) *error = e ?: [NSError errorWithDomain:@"DSVoice" code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"无法创建录音器"}];
    return NO;
  }
  rec.meteringEnabled = YES;
  rec.delegate = self;
  if (![rec record]) {
    if (error) *error = [NSError errorWithDomain:@"DSVoice" code:-2
                                           userInfo:@{NSLocalizedDescriptionKey: @"录音启动失败"}];
    return NO;
  }

  _recorder = rec;
  _path = path;
  _recording = YES;
  _level = 0;
  __weak __typeof(self) ws = self;
  _meter = [NSTimer scheduledTimerWithTimeInterval:0.06 repeats:YES block:^(NSTimer *t) {
    [ws pollLevel];
  }];
  return YES;
}

- (void)pollLevel {
  AVAudioRecorder *rec = self.recorder;
  if (!rec) return;
  [rec updateMeters];
  float db = [rec averagePowerForChannel:0];   // -160..0
  // 线性映射到 0..1，-50dB 以下当作静音
  CGFloat v = (CGFloat)((db + 50.0) / 50.0);
  if (v < 0) v = 0;
  if (v > 1) v = 1;
  // 平滑，避免波形抖动
  self.level = self.level * 0.55 + v * 0.45;
}

- (NSTimeInterval)duration {
  return self.recorder ? self.recorder.currentTime : 0;
}

- (NSString *)finish {
  [self.meter invalidate];
  self.meter = nil;
  if (!self.recorder) return nil;
  NSTimeInterval dur = self.recorder.currentTime;
  [self.recorder stop];
  self.recorder = nil;
  self.recording = NO;
  // 太短（不到 0.6s）视为误触
  if (dur < 0.6) {
    [self removeFile];
    return nil;
  }
  return self.path;
}

- (void)cancel {
  [self.meter invalidate];
  self.meter = nil;
  if (self.recorder) {
    [self.recorder stop];
    self.recorder = nil;
  }
  self.recording = NO;
  [self removeFile];
}

- (void)removeFile {
  if (self.path.length) [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
  self.path = nil;
}

- (void)dealloc {
  [_meter invalidate];
  [_recorder stop];
}

@end
