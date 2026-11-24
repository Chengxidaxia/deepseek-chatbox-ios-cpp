//
//  DSTheme.h
//  ChatboxIOS
//
//  设计令牌。取值来源（全部为实测，非主观调整）：
//  - 颜色：deepseek-chatbox/public/css/tokens.css（该文件注释声明取自
//    chat.deepseek.com 的 main.css，变量值未做调整）
//  - 字号/圆角/间距：deepseek-chatbox/public/css/app.css（.md / .msg.user .bubble / .think）
//  - 深色模式配对值：tokens.css 的 body[data-ds-dark-theme] 块
//  - 官方 iOS App（DeepSeek-2.7.1.ipa）内嵌 SVG 的描边色 #0F0F0F 与浅色 --label-primary
//    基本一致，可交叉印证
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSTheme : NSObject

/// 0xRRGGBB
+ (UIColor *)hex:(uint32_t)value;

#pragma mark - 背景
+ (UIColor *)bgBase;        // 浅 #FFFFFF / 深 #151517
+ (UIColor *)bgLayer1;      // 浅 #FFFFFF / 深 #232324
+ (UIColor *)bgHover;       // 浅 rgba(38,49,72,.06) / 深 rgba(255,255,255,.08)
+ (UIColor *)bgActive;      // 浅 rgba(38,49,72,.10) / 深 rgba(255,255,255,.14)

#pragma mark - 文字
+ (UIColor *)labelPrimary;   // 浅 #0F1115 / 深 #F9FAFB
+ (UIColor *)labelSecondary; // 浅 #61666B / 深 #CFD3D6
+ (UIColor *)labelTertiary;  // 浅 #81858C / 深 #ADB2B8
+ (UIColor *)labelCaption;   // 浅 #ADB2B8 / 深 #81858C

#pragma mark - 描边
+ (UIColor *)borderL2;  // 浅 rgba(0,0,0,.10) / 深 rgba(255,255,255,.12)
+ (UIColor *)borderL3;  // 浅 rgba(0,0,0,.12) / 深 rgba(255,255,255,.16)

#pragma mark - 品牌与气泡
+ (UIColor *)brand;       // 浅 #3964FE / 深 #5686FE
+ (UIColor *)userBubble;  // 浅 #EDF3FE / 深 #2C2C2E
+ (UIColor *)toolCardBG;  // 浅 #F9FAFB / 深 #232324
+ (UIColor *)danger;      // 浅 #EC1313 / 深 #F25A5A

#pragma mark - 字体（字号取自 app.css）
/// 正文 16px、行高 28px
+ (UIFont *)bodyFont;
/// 思考正文 14px
+ (UIFont *)thinkFont;
/// 思考头部 13px
+ (UIFont *)thinkHeadFont;
/// 辅助说明 11px
+ (UIFont *)captionFont;
/// 用量行 11px
+ (UIFont *)usageFont;

#pragma mark - 排版
/// 正文段落样式：行高 28（对齐 .md { line-height: 28px }）
+ (NSAttributedString *)bodyText:(NSString *)text color:(UIColor *)color;
/// 思考正文：14px / 24px（对齐 .think { font-size:14px; line-height:24px }）
+ (NSAttributedString *)thinkText:(NSString *)text color:(UIColor *)color;

#pragma mark - 尺寸（取自 app.css）
+ (CGFloat)userBubbleRadius;      // 18
+ (CGFloat)userBubbleMaxWidth;    // 0.78
+ (UIEdgeInsets)userBubbleInsets; // 10 / 14
+ (CGFloat)thinkBarWidth;         // 2
+ (CGFloat)thinkBarGap;           // 12
+ (CGFloat)messageListPadding;    // 20（移动端）

@end

NS_ASSUME_NONNULL_END
