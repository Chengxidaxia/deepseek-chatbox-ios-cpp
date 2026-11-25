//
//  DSTheme.m
//  ChatboxIOS
//

#import "DSTheme.h"

@interface DSTheme ()
+ (UIColor *)rgba:(uint32_t)value alpha:(CGFloat)alpha;
+ (NSMutableParagraphStyle *)paragraphWithLineHeight:(CGFloat)lineHeight;
@end

@implementation DSTheme

+ (UIColor *)hex:(uint32_t)value {
  return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                         green:((value >> 8) & 0xFF) / 255.0
                          blue:(value & 0xFF) / 255.0
                         alpha:1.0];
}

+ (UIColor *)rgba:(uint32_t)value alpha:(CGFloat)alpha {
  return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                         green:((value >> 8) & 0xFF) / 255.0
                          blue:(value & 0xFF) / 255.0
                         alpha:alpha];
}

/// 浅/深两套值，跟随系统外观
+ (UIColor *)dynamicLight:(UIColor *)light dark:(UIColor *)dark {
  return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
    return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
  }];
}

#pragma mark - 背景

+ (UIColor *)bgBase { return [self dynamicLight:[self hex:0xFFFFFF] dark:[self hex:0x151517]]; }
+ (UIColor *)bgLayer1 { return [self dynamicLight:[self hex:0xFFFFFF] dark:[self hex:0x232324]]; }
+ (UIColor *)bgHover {
  return [self dynamicLight:[self rgba:0x263148 alpha:0.06] dark:[self rgba:0xFFFFFF alpha:0.08]];
}
+ (UIColor *)bgActive {
  return [self dynamicLight:[self rgba:0x263148 alpha:0.10] dark:[self rgba:0xFFFFFF alpha:0.14]];
}

#pragma mark - 文字

+ (UIColor *)labelPrimary { return [self dynamicLight:[self hex:0x0F0F0F] dark:[self hex:0xF9FAFB]]; }
+ (UIColor *)labelSecondary { return [self dynamicLight:[self hex:0x7D7F85] dark:[self hex:0xCFD3D6]]; }
+ (UIColor *)labelTertiary { return [self dynamicLight:[self hex:0x8E9094] dark:[self hex:0xADB2B8]]; }
+ (UIColor *)labelCaption { return [self dynamicLight:[self hex:0xADB2B8] dark:[self hex:0x81858C]]; }

#pragma mark - 描边

+ (UIColor *)borderL2 {
  return [self dynamicLight:[self rgba:0x000000 alpha:0.10] dark:[self rgba:0xFFFFFF alpha:0.12]];
}
+ (UIColor *)borderL3 {
  return [self dynamicLight:[self rgba:0x000000 alpha:0.12] dark:[self rgba:0xFFFFFF alpha:0.16]];
}

#pragma mark - 品牌与气泡

+ (UIColor *)brand { return [self dynamicLight:[self hex:0x426EFE] dark:[self hex:0x5686FE]]; }
+ (UIColor *)userBubble { return [self dynamicLight:[self hex:0xEDF3FE] dark:[self hex:0x2C2C2E]]; }
+ (UIColor *)toolCardBG { return [self dynamicLight:[self hex:0xF9FAFB] dark:[self hex:0x232324]]; }
+ (UIColor *)danger { return [self dynamicLight:[self hex:0xEF4444] dark:[self hex:0xF25A5A]]; }

#pragma mark - 字体

+ (UIFont *)bodyFont { return [UIFont systemFontOfSize:16]; }

+ (UIFont *)thinkFont { return [UIFont systemFontOfSize:14]; }
+ (UIFont *)thinkHeadFont { return [UIFont systemFontOfSize:13]; }
+ (UIFont *)captionFont { return [UIFont systemFontOfSize:11]; }
+ (UIFont *)usageFont { return [UIFont systemFontOfSize:11]; }

#pragma mark - 排版

+ (NSMutableParagraphStyle *)paragraphWithLineHeight:(CGFloat)lineHeight {
  NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
  p.minimumLineHeight = lineHeight;
  p.maximumLineHeight = lineHeight;
  return p;
}

+ (NSAttributedString *)bodyText:(NSString *)text color:(UIColor *)color {
  NSDictionary *attrs = @{
    NSFontAttributeName: [self bodyFont],
    NSForegroundColorAttributeName: color ?: [self labelPrimary],
    NSParagraphStyleAttributeName: [self paragraphWithLineHeight:28],
  };
  return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:attrs];
}

+ (NSAttributedString *)thinkText:(NSString *)text color:(UIColor *)color {
  NSDictionary *attrs = @{
    NSFontAttributeName: [self thinkFont],
    NSForegroundColorAttributeName: color ?: [self labelTertiary],
    NSParagraphStyleAttributeName: [self paragraphWithLineHeight:24],
  };
  return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:attrs];
}

#pragma mark - 尺寸

+ (CGFloat)userBubbleRadius { return 18.0; }
+ (CGFloat)userBubbleMaxWidth { return 0.78; }
+ (UIEdgeInsets)userBubbleInsets { return UIEdgeInsetsMake(10, 14, 10, 14); }
+ (CGFloat)thinkBarWidth { return 2.0; }
+ (CGFloat)thinkBarGap { return 12.0; }
+ (CGFloat)messageListPadding { return 20.0; }

#pragma mark - 主题模式

+ (void)applyThemeMode:(NSString *)mode {
  UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
  if ([mode isEqualToString:@"light"]) style = UIUserInterfaceStyleLight;
  else if ([mode isEqualToString:@"dark"]) style = UIUserInterfaceStyleDark;
  // 其它值（含 nil）一律当「跟随系统」。

  // 必须落到 window 上：颜色是 colorWithDynamicProvider 生成的，
  // 只有 trait 变了它们才会重算。改颜色常量本身行不通，还会把「跟随系统」堵死。
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
      w.overrideUserInterfaceStyle = style;
    }
  }
}

+ (NSString *)displayNameForThemeMode:(NSString *)mode {
  if ([mode isEqualToString:@"light"]) return @"浅色";
  if ([mode isEqualToString:@"dark"]) return @"深色";
  return @"跟随系统";
}

@end
