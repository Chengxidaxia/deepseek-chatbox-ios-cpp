//
//  DSToggleButtonGroup.h
//  ChatboxIOS
//
//  对齐官方 `InputAreaView.ToggleButtonGroup` / `ToggleButtonContainer` / `ToggleButton`
//  这三层里最外面那层：把「深度思考」「智能搜索」这类开关收进一个分组容器，
//  由容器统一管间距和排列，而不是把它们一个个直接塞进工具条。
//
//  为什么值得单独建一层：官方这一组按钮是**有分组语义的**（同一类开关、可多选、
//  状态互不干扰）。散着放的话，以后要加第三个开关（比如「联网」）就得改工具条的
//  排列，还会把「开关组」和「操作按钮」混在一条线上。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSButton;

@interface DSToggleButtonGroup : UIView

/// 按钮按传入顺序横向排列，间距由容器统一给。
- (instancetype)initWithButtons:(NSArray<DSButton *> *)buttons;

/// 组内间距，默认 6。
@property (nonatomic, assign) CGFloat spacing;

/// 组内按钮（只读，方便外部按序取用）。
@property (nonatomic, copy, readonly) NSArray<DSButton *> *buttons;

@end

NS_ASSUME_NONNULL_END
