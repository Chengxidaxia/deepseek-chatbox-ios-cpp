//
//  DSAttachmentPanel.h
//  ChatboxIOS
//
//  对齐官方 UploadPanelView（相册 / 拍照 / 文件）与 InputFileContainerView（已选附件条）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSAttachSource) {
  DSAttachSourceAlbum = 0,
  DSAttachSourceCamera,
  DSAttachSourceFile,
};

#pragma mark - 选择面板

@interface DSAttachmentPanel : UIViewController

/// handler 在面板关闭后回调（相册/相机/文件）
+ (instancetype)panelWithHandler:(void (^)(DSAttachSource source))handler;

@end

#pragma mark - 附件条

@interface DSAttachmentItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *mime;
/// image / text / file
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, strong, nullable) UIImage *thumbnail;
@property (nonatomic, assign) NSInteger size;
+ (instancetype)itemWithData:(NSData *)data name:(NSString *)name mime:(NSString *)mime;
@end

@interface DSAttachmentStrip : UIView

/// 更新已选附件；点 × 删除时回调
- (void)setItems:(NSArray<DSAttachmentItem *> *)items;
@property (nonatomic, copy, nullable) void (^onRemove)(NSUInteger index);

@end

NS_ASSUME_NONNULL_END
