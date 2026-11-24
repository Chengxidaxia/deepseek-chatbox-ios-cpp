//
//  DSIcon.m
//  ChatboxIOS
//

#import "DSIcon.h"

@implementation DSIcon

+ (UIImage *)image:(DSIconName)name size:(CGFloat)size {
  // 图标随文字色走：用 tintColor 渲染，避免每个调用点都传颜色
  return [[self image:name size:size color:UIColor.blackColor lineWidth:1.6]
      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (UIImage *)image:(DSIconName)name
              size:(CGFloat)size
             color:(UIColor *)color
         lineWidth:(CGFloat)lineWidth {
  // 官方 SVG 是 20×20 视口、描边 1.6，按目标尺寸等比缩放
  const CGFloat grid = 20.0;
  CGFloat scale = size / grid;
  UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
  fmt.opaque = NO;
  fmt.scale = 0;  // 跟随屏幕
  UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc]
      initWithSize:CGSizeMake(size, size) format:fmt];

  return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    CGContextRef c = ctx.CGContext;
    CGContextScaleCTM(c, scale, scale);
    CGContextSetStrokeColorWithColor(c, color.CGColor);
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextSetLineWidth(c, lineWidth);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);

    UIBezierPath *(^circle)(CGFloat, CGFloat, CGFloat) = ^UIBezierPath *(CGFloat x, CGFloat y, CGFloat rad) {
      return [UIBezierPath bezierPathWithArcCenter:CGPointMake(x, y) radius:rad
                                          startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    };
    void (^line)(CGFloat, CGFloat, CGFloat, CGFloat) = ^(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
      UIBezierPath *p = [UIBezierPath bezierPath];
      [p moveToPoint:CGPointMake(x1, y1)];
      [p addLineToPoint:CGPointMake(x2, y2)];
      [p stroke];
    };
    void (^poly)(NSArray<NSValue *> *) = ^(NSArray<NSValue *> *pts) {
      UIBezierPath *p = [UIBezierPath bezierPath];
      for (NSUInteger i = 0; i < pts.count; i++) {
        CGPoint pt = pts[i].CGPointValue;
        if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
      }
      [p stroke];
    };

    switch (name) {
      case DSIconGlobe: {
        [circle(10, 10, 7.4) stroke];
        // 经线（椭圆）+ 赤道
        UIBezierPath *meridian = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(5.6, 2.6, 8.8, 14.8)];
        [meridian stroke];
        line(2.6, 10, 17.4, 10);
        break;
      }
      case DSIconDoc: {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.2, 2.6, 11.6, 14.8)
                                                        cornerRadius:2.4];
        [p stroke];
        line(6.8, 7.4, 13.2, 7.4);
        line(6.8, 10.4, 13.2, 10.4);
        line(6.8, 13.4, 11.0, 13.4);
        break;
      }
      case DSIconChevronDown: poly(@[[NSValue valueWithCGPoint:CGPointMake(6.2, 8.2)],
                                     [NSValue valueWithCGPoint:CGPointMake(10, 12)],
                                     [NSValue valueWithCGPoint:CGPointMake(13.8, 8.2)]]); break;
      case DSIconChevronLeft: poly(@[[NSValue valueWithCGPoint:CGPointMake(12.2, 5.4)],
                                     [NSValue valueWithCGPoint:CGPointMake(7.6, 10)],
                                     [NSValue valueWithCGPoint:CGPointMake(12.2, 14.6)]]); break;
      case DSIconChevronRight: poly(@[[NSValue valueWithCGPoint:CGPointMake(7.8, 5.4)],
                                      [NSValue valueWithCGPoint:CGPointMake(12.4, 10)],
                                      [NSValue valueWithCGPoint:CGPointMake(7.8, 14.6)]]); break;
      case DSIconCopy: {
        UIBezierPath *back = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.4, 3.4, 9.4, 9.4)
                                                           cornerRadius:2.2];
        [back stroke];
        UIBezierPath *front = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.2, 7.2, 9.4, 9.4)
                                                            cornerRadius:2.2];
        [front stroke];
        break;
      }
      case DSIconRefresh: {
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(10, 10) radius:6.4
                                                        startAngle:-M_PI * 0.35 endAngle:M_PI * 1.15
                                                         clockwise:YES];
        [arc stroke];
        // 箭头
        poly(@[[NSValue valueWithCGPoint:CGPointMake(13.2, 1.8)],
               [NSValue valueWithCGPoint:CGPointMake(14.6, 5.6)],
               [NSValue valueWithCGPoint:CGPointMake(10.8, 6.2)]]);
        break;
      }
      case DSIconPlus: {
        line(10, 4.4, 10, 15.6);
        line(4.4, 10, 15.6, 10);
        break;
      }
      case DSIconMic: {
        UIBezierPath *cap = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.5, 2.4, 5.0, 9.2)
                                                          cornerRadius:2.5];
        [cap stroke];
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(10, 9.6) radius:4.6
                                                        startAngle:0 endAngle:M_PI clockwise:YES];
        [arc stroke];
        line(10, 14.2, 10, 17.2);
        break;
      }
      case DSIconCamera: {
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.6, 5.6, 14.8, 11.0)
                                                           cornerRadius:3.0];
        [body stroke];
        // 顶部取景凸起
        poly(@[[NSValue valueWithCGPoint:CGPointMake(7.2, 5.6)],
               [NSValue valueWithCGPoint:CGPointMake(8.4, 3.1)],
               [NSValue valueWithCGPoint:CGPointMake(11.6, 3.1)],
               [NSValue valueWithCGPoint:CGPointMake(12.8, 5.6)]]);
        [circle(10, 11.1, 3.0) stroke];
        break;
      }
      case DSIconPhoto: {
        UIBezierPath *frame = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.8, 4.0, 14.4, 12.0)
                                                            cornerRadius:2.6];
        [frame stroke];
        // 山峰
        poly(@[[NSValue valueWithCGPoint:CGPointMake(5.0, 13.6)],
               [NSValue valueWithCGPoint:CGPointMake(8.6, 9.6)],
               [NSValue valueWithCGPoint:CGPointMake(11.4, 13.6)]]);
        poly(@[[NSValue valueWithCGPoint:CGPointMake(10.0, 13.6)],
               [NSValue valueWithCGPoint:CGPointMake(12.8, 10.6)],
               [NSValue valueWithCGPoint:CGPointMake(15.4, 13.6)]]);
        [circle(13.4, 7.4, 1.3) fill];
        break;
      }
      case DSIconFile: {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(5.0, 2.8)];
        [p addLineToPoint:CGPointMake(11.6, 2.8)];
        [p addLineToPoint:CGPointMake(15.2, 6.6)];
        [p addLineToPoint:CGPointMake(15.2, 17.2)];
        [p addLineToPoint:CGPointMake(5.0, 17.2)];
        [p closePath];
        [p stroke];
        poly(@[[NSValue valueWithCGPoint:CGPointMake(11.4, 2.9)],
               [NSValue valueWithCGPoint:CGPointMake(11.4, 6.8)],
               [NSValue valueWithCGPoint:CGPointMake(15.0, 6.8)]]);
        break;
      }
      case DSIconSend: {
        line(10, 16.4, 10, 4.2);
        poly(@[[NSValue valueWithCGPoint:CGPointMake(5.2, 8.8)],
               [NSValue valueWithCGPoint:CGPointMake(10, 4.0)],
               [NSValue valueWithCGPoint:CGPointMake(14.8, 8.8)]]);
        break;
      }
      case DSIconStop: {
        UIBezierPath *sq = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6.2, 6.2, 7.6, 7.6)
                                                         cornerRadius:2.0];
        [sq fill];
        break;
      }
      case DSIconSpeaker: {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(3.6, 8.0)];
        [p addLineToPoint:CGPointMake(6.4, 8.0)];
        [p addLineToPoint:CGPointMake(9.8, 4.8)];
        [p addLineToPoint:CGPointMake(9.8, 15.2)];
        [p addLineToPoint:CGPointMake(6.4, 12.0)];
        [p addLineToPoint:CGPointMake(3.6, 12.0)];
        [p closePath];
        [p stroke];
        UIBezierPath *w1 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(11.6, 10) radius:2.8
                                                       startAngle:-M_PI * 0.32 endAngle:M_PI * 0.32
                                                        clockwise:YES];
        [w1 stroke];
        UIBezierPath *w2 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(11.6, 10) radius:5.4
                                                       startAngle:-M_PI * 0.32 endAngle:M_PI * 0.32
                                                        clockwise:YES];
        [w2 stroke];
        break;
      }
      case DSIconCheck: poly(@[[NSValue valueWithCGPoint:CGPointMake(4.6, 10.6)],
                               [NSValue valueWithCGPoint:CGPointMake(8.4, 14.2)],
                               [NSValue valueWithCGPoint:CGPointMake(15.4, 6.2)]]); break;
      case DSIconClose: {
        line(5.4, 5.4, 14.6, 14.6);
        line(14.6, 5.4, 5.4, 14.6);
        break;
      }
      case DSIconLightning: {
        // 闪电：官方快速模式图标（实心折线）
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(11.8, 2.4)];
        [p addLineToPoint:CGPointMake(5.0, 11.2)];
        [p addLineToPoint:CGPointMake(9.4, 11.2)];
        [p addLineToPoint:CGPointMake(8.2, 17.6)];
        [p addLineToPoint:CGPointMake(15.0, 8.8)];
        [p addLineToPoint:CGPointMake(10.6, 8.8)];
        [p closePath];
        [p fill];
        break;
      }
      case DSIconBrain: {
        // 专家模式：简化脑形（左右两瓣 + 中线）
        UIBezierPath *l = [UIBezierPath bezierPath];
        [l moveToPoint:CGPointMake(10, 4.2)];
        [l addCurveToPoint:CGPointMake(3.6, 10.0) controlPoint1:CGPointMake(6.2, 3.4) controlPoint2:CGPointMake(3.6, 6.4)];
        [l addCurveToPoint:CGPointMake(10, 16.4) controlPoint1:CGPointMake(3.6, 13.6) controlPoint2:CGPointMake(6.6, 16.4)];
        [l stroke];
        UIBezierPath *rr = [UIBezierPath bezierPath];
        [rr moveToPoint:CGPointMake(10, 4.2)];
        [rr addCurveToPoint:CGPointMake(16.4, 10.0) controlPoint1:CGPointMake(13.8, 3.4) controlPoint2:CGPointMake(16.4, 6.4)];
        [rr addCurveToPoint:CGPointMake(10, 16.4) controlPoint1:CGPointMake(16.4, 13.6) controlPoint2:CGPointMake(13.4, 16.4)];
        [rr stroke];
        line(10, 4.4, 10, 16.2);
        break;
      }
      case DSIconSearch: {
        [circle(9.0, 9.0, 5.6) stroke];
        line(13.2, 13.2, 17.0, 17.0);
        break;
      }
    }
  }];
}

@end
