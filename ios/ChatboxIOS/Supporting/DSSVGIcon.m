//
//  DSSVGIcon.m
//  ChatboxIOS
//

#import "DSSVGIcon.h"
#import "DSIconAssets.h"

#import <ctype.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#pragma mark - 扫描工具

static inline BOOL DSIsSpace(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/// 取下一个标签（不含尖括号）。指针前移到标签之后；没有标签返回 nil。
static NSString *_Nullable DSNextTag(const char **_pp) {
  const char *p = *_pp;
  while (*p && *p != '<') p++;
  if (*p == '\0') {
    *_pp = p;
    return nil;
  }
  p++;  // 跳过 '<'
  const char *start = p;
  char quote = 0;
  while (*p) {
    if (quote) {
      if (*p == quote) quote = 0;
    } else if (*p == '"' || *p == '\'') {
      quote = *p;
    } else if (*p == '>') {
      break;
    }
    p++;
  }
  NSString *tag = [[NSString alloc] initWithBytes:start
                                           length:(NSUInteger)(p - start)
                                         encoding:NSUTF8StringEncoding];
  if (*p) p++;  // 跳过 '>'
  *_pp = p;
  return tag ?: @"";
}

/// 把标签拆成名字 + 属性表。名字统一小写；自闭合标签返回时末尾带 '/'，由调用方判空。
static NSString *DSParseTag(NSString *tag, NSMutableDictionary<NSString *, NSString *> *attrs) {
  NSUInteger n = tag.length, i = 0;
  unichar (^at)(NSUInteger) = ^unichar(NSUInteger k) { return k < n ? [tag characterAtIndex:k] : 0; };

  if (at(i) == '/') i++;  // 闭合标签
  NSUInteger nameStart = i;
  while (i < n && !DSIsSpace((char)at(i)) && at(i) != '/') i++;
  NSString *name = [[tag substringWithRange:NSMakeRange(nameStart, i - nameStart)] lowercaseString];

  while (i < n) {
    while (i < n && (DSIsSpace((char)at(i)) || at(i) == '/')) i++;
    if (i >= n) break;
    NSUInteger keyStart = i;
    while (i < n && at(i) != '=' && !DSIsSpace((char)at(i))) i++;
    NSString *key = [[tag substringWithRange:NSMakeRange(keyStart, i - keyStart)] lowercaseString];
    while (i < n && DSIsSpace((char)at(i))) i++;
    if (at(i) != '=') {
      if (key.length) attrs[key] = @"";
      continue;
    }
    i++;  // '='
    while (i < n && DSIsSpace((char)at(i))) i++;
    NSString *value = @"";
    if (at(i) == '"' || at(i) == '\'') {
      unichar q = at(i++);
      NSUInteger vs = i;
      while (i < n && at(i) != q) i++;
      value = [tag substringWithRange:NSMakeRange(vs, i - vs)];
      if (i < n) i++;
    } else {
      NSUInteger vs = i;
      while (i < n && !DSIsSpace((char)at(i))) i++;
      value = [tag substringWithRange:NSMakeRange(vs, i - vs)];
    }
    if (key.length) attrs[key] = value;
  }
  return name;
}

#pragma mark - 颜色

static UIColor *_Nullable DSSVGColor(NSString *value, UIColor *tint) {
  if (value.length == 0) return nil;
  NSString *v = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  v = [v lowercaseString];
  if ([v isEqualToString:@"none"] || [v isEqualToString:@"transparent"]) return nil;
  // url(#…) 是渐变/图案引用：官方图标里只有 Loading 的环形进度用到，降级成纯色即可。
  if ([v hasPrefix:@"url("]) {
    return tint ?: [UIColor whiteColor];
  }
  if (tint) return tint;

  if ([v isEqualToString:@"white"]) return [UIColor whiteColor];
  if ([v isEqualToString:@"black"]) return [UIColor blackColor];
  if ([v isEqualToString:@"currentcolor"]) return [UIColor blackColor];

  if ([v hasPrefix:@"#"]) {
    unsigned long long raw = 0;
    if (v.length == 4) {  // #RGB
      unsigned int r = 0, g = 0, b = 0;
      sscanf(v.UTF8String, "#%1x%1x%1x", &r, &g, &b);
      return [UIColor colorWithRed:r / 15.0 green:g / 15.0 blue:b / 15.0 alpha:1.0];
    }
    if (v.length == 7 || v.length == 9) {
      if (sscanf(v.UTF8String, "#%llx", &raw) != 1) return nil;
      CGFloat a = v.length == 9 ? ((raw >> 24) & 0xFF) / 255.0 : 1.0;
      return [UIColor colorWithRed:((raw >> 16) & 0xFF) / 255.0
                             green:((raw >> 8) & 0xFF) / 255.0
                              blue:(raw & 0xFF) / 255.0
                             alpha:a];
    }
  }
  return nil;
}

#pragma mark - path 的 d 解析

static void DSSkipSeparators(const char **p) {
  while (**p && (DSIsSpace(**p) || **p == ',')) (*p)++;
}

static CGFloat DSSVGNumber(const char **p) {
  DSSkipSeparators(p);
  char *end = NULL;
  double v = strtod(*p, &end);
  if (end == *p) {
    // 解不出数字（例如孤立的 '-'）：吃掉一个字符再返回 0，
    // 否则外层 while (DSSVGHasNumber(&p)) 会原地打转。
    if (**p) (*p)++;
    return 0.0;
  }
  *p = end;
  return (CGFloat)v;
}

static BOOL DSSVGHasNumber(const char **p) {
  const char *q = *p;
  DSSkipSeparators(&q);
  return (*q >= '0' && *q <= '9') || *q == '-' || *q == '+' || *q == '.';
}

/// SVG 椭圆弧 → 三次贝塞尔（按 90° 一段切分）。
static void DSAppendArc(CGMutablePathRef path, CGFloat rx, CGFloat ry, CGFloat xRot,
                        BOOL largeArc, BOOL sweep, CGFloat x, CGFloat y) {
  CGPoint p0 = CGPathGetCurrentPoint(path);
  if (rx == 0.0 || ry == 0.0 || (p0.x == x && p0.y == y)) {
    CGPathAddLineToPoint(path, NULL, x, y);
    return;
  }
  rx = fabs(rx);
  ry = fabs(ry);
  CGFloat phi = xRot * M_PI / 180.0;
  CGFloat cosPhi = cos(phi), sinPhi = sin(phi);
  CGFloat dx2 = (p0.x - x) / 2.0, dy2 = (p0.y - y) / 2.0;
  CGFloat x1p = cosPhi * dx2 + sinPhi * dy2;
  CGFloat y1p = -sinPhi * dx2 + cosPhi * dy2;

  CGFloat lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1.0) {
    CGFloat s = sqrt(lambda);
    rx *= s;
    ry *= s;
  }
  CGFloat num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  CGFloat den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  CGFloat coef = (den > 0.0 ? sqrt(MAX(0.0, num / den)) : 0.0);
  if (largeArc == sweep) coef = -coef;
  CGFloat cxp = coef * rx * y1p / ry;
  CGFloat cyp = -coef * ry * x1p / rx;
  CGFloat cx = cosPhi * cxp - sinPhi * cyp + (p0.x + x) / 2.0;
  CGFloat cy = sinPhi * cxp + cosPhi * cyp + (p0.y + y) / 2.0;

  CGFloat ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
  CGFloat vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
  CGFloat theta1 = atan2(uy, ux);
  CGFloat dTheta = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
  if (!sweep && dTheta > 0) dTheta -= 2 * M_PI;
  if (sweep && dTheta < 0) dTheta += 2 * M_PI;

  int segments = (int)ceil(fabs(dTheta) / (M_PI / 2.0));
  if (segments < 1) segments = 1;
  CGFloat delta = dTheta / segments;
  CGFloat k = 4.0 / 3.0 * tan(delta / 4.0);
  CGFloat t = theta1;
  for (int i = 0; i < segments; i++) {
    CGFloat c1 = cos(t), s1 = sin(t);
    CGFloat t2 = t + delta;
    CGFloat c2 = cos(t2), s2 = sin(t2);
    CGPoint q1 = CGPointMake(cosPhi * (rx * (c1 - k * s1)) - sinPhi * (ry * (s1 + k * c1)) + cx,
                             sinPhi * (rx * (c1 - k * s1)) + cosPhi * (ry * (s1 + k * c1)) + cy);
    CGPoint q2 = CGPointMake(cosPhi * (rx * (c2 + k * s2)) - sinPhi * (ry * (s2 - k * c2)) + cx,
                             sinPhi * (rx * (c2 + k * s2)) + cosPhi * (ry * (s2 - k * c2)) + cy);
    CGPoint q3 = CGPointMake(cosPhi * (rx * c2) - sinPhi * (ry * s2) + cx,
                             sinPhi * (rx * c2) + cosPhi * (ry * s2) + cy);
    CGPathAddCurveToPoint(path, NULL, q1.x, q1.y, q2.x, q2.y, q3.x, q3.y);
    t = t2;
  }
}

static CGMutablePathRef DSCreatePathFromData(NSString *data) {
  CGMutablePathRef path = CGPathCreateMutable();
  if (data.length == 0) return path;

  const char *p = data.UTF8String;
  char cmd = 0;
  CGPoint cur = CGPointZero, start = CGPointZero;
  CGPoint lastCubic = CGPointZero, lastQuad = CGPointZero;
  BOOL hasCubic = NO, hasQuad = NO;

  while (YES) {
    DSSkipSeparators(&p);
    if (*p == '\0') break;
    if (isalpha((unsigned char)*p)) {
      cmd = *p;
      p++;
      DSSkipSeparators(&p);
    } else if (cmd == 0) {
      break;  // 没有命令就出现数字，非法
    }

    BOOL rel = islower((unsigned char)cmd);
    char c = (char)toupper((unsigned char)cmd);
    BOOL first = YES;

    switch (c) {
      case 'M': {
        do {
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x += cur.x; y += cur.y; }
          if (first) {
            CGPathMoveToPoint(path, NULL, x, y);
            start = CGPointMake(x, y);
            first = NO;
          } else {
            CGPathAddLineToPoint(path, NULL, x, y);
          }
          cur = CGPointMake(x, y);
        } while (DSSVGHasNumber(&p));
        hasCubic = hasQuad = NO;
        // 后续隐式命令按 L 处理
        cmd = rel ? 'l' : 'L';
        break;
      }
      case 'L': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x += cur.x; y += cur.y; }
          CGPathAddLineToPoint(path, NULL, x, y);
          cur = CGPointMake(x, y);
        }
        hasCubic = hasQuad = NO;
        break;
      }
      case 'H': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x = DSSVGNumber(&p);
          if (rel) x += cur.x;
          CGPathAddLineToPoint(path, NULL, x, cur.y);
          cur.x = x;
        }
        hasCubic = hasQuad = NO;
        break;
      }
      case 'V': {
        while (DSSVGHasNumber(&p)) {
          CGFloat y = DSSVGNumber(&p);
          if (rel) y += cur.y;
          CGPathAddLineToPoint(path, NULL, cur.x, y);
          cur.y = y;
        }
        hasCubic = hasQuad = NO;
        break;
      }
      case 'C': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x1 = DSSVGNumber(&p), y1 = DSSVGNumber(&p);
          CGFloat x2 = DSSVGNumber(&p), y2 = DSSVGNumber(&p);
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) {
            x1 += cur.x; y1 += cur.y; x2 += cur.x; y2 += cur.y; x += cur.x; y += cur.y;
          }
          CGPathAddCurveToPoint(path, NULL, x1, y1, x2, y2, x, y);
          lastCubic = CGPointMake(x2, y2);
          hasCubic = YES;
          hasQuad = NO;
          cur = CGPointMake(x, y);
        }
        break;
      }
      case 'S': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x2 = DSSVGNumber(&p), y2 = DSSVGNumber(&p);
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x2 += cur.x; y2 += cur.y; x += cur.x; y += cur.y; }
          CGPoint c1 = hasCubic ? CGPointMake(2 * cur.x - lastCubic.x, 2 * cur.y - lastCubic.y) : cur;
          CGPathAddCurveToPoint(path, NULL, c1.x, c1.y, x2, y2, x, y);
          lastCubic = CGPointMake(x2, y2);
          hasCubic = YES;
          hasQuad = NO;
          cur = CGPointMake(x, y);
        }
        break;
      }
      case 'Q': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x1 = DSSVGNumber(&p), y1 = DSSVGNumber(&p);
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x1 += cur.x; y1 += cur.y; x += cur.x; y += cur.y; }
          CGPathAddQuadCurveToPoint(path, NULL, x1, y1, x, y);
          lastQuad = CGPointMake(x1, y1);
          hasQuad = YES;
          hasCubic = NO;
          cur = CGPointMake(x, y);
        }
        break;
      }
      case 'T': {
        while (DSSVGHasNumber(&p)) {
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x += cur.x; y += cur.y; }
          CGPoint c1 = hasQuad ? CGPointMake(2 * cur.x - lastQuad.x, 2 * cur.y - lastQuad.y) : cur;
          CGPathAddQuadCurveToPoint(path, NULL, c1.x, c1.y, x, y);
          lastQuad = c1;
          hasQuad = YES;
          hasCubic = NO;
          cur = CGPointMake(x, y);
        }
        break;
      }
      case 'A': {
        while (DSSVGHasNumber(&p)) {
          CGFloat rx = DSSVGNumber(&p), ry = DSSVGNumber(&p);
          CGFloat rot = DSSVGNumber(&p);
          CGFloat large = DSSVGNumber(&p), sweep = DSSVGNumber(&p);
          CGFloat x = DSSVGNumber(&p), y = DSSVGNumber(&p);
          if (rel) { x += cur.x; y += cur.y; }
          DSAppendArc(path, rx, ry, rot, large != 0, sweep != 0, x, y);
          cur = CGPointMake(x, y);
        }
        hasCubic = hasQuad = NO;
        break;
      }
      case 'Z': {
        CGPathCloseSubpath(path);
        cur = start;
        hasCubic = hasQuad = NO;
        // Z 之后不该再有数字；把 cmd 清掉，让外层的「没有命令却出现数字」直接退出，
        // 避免 cmd 仍是 'Z' 时原地死循环。
        cmd = 0;
        break;
      }
      default:
        // 未知命令：跳过，避免死循环
        p++;
        break;
    }
  }
  return path;
}

#pragma mark - transform

static CGAffineTransform DSParseTransform(NSString *value) {
  CGAffineTransform t = CGAffineTransformIdentity;
  if (value.length == 0) return t;
  const char *p = value.UTF8String;
  while (*p) {
    while (*p && !isalpha((unsigned char)*p)) p++;
    if (!*p) break;
    char name[16] = {0};
    int i = 0;
    while (*p && isalpha((unsigned char)*p) && i < 15) name[i++] = *p++;
    while (*p && *p != '(') p++;
    if (*p == '(') p++;
    CGFloat a = 0, b = 0, c = 0, d = 0, e = 0, f = 0;
    int got = 0;
    CGFloat vals[6] = {0};
    while (*p && *p != ')') {
      if (DSSVGHasNumber(&p)) {
        vals[got < 6 ? got : 5] = DSSVGNumber(&p);
        if (got < 6) got++;
      } else {
        p++;
      }
    }
    if (*p == ')') p++;
    a = vals[0]; b = vals[1]; c = vals[2]; d = vals[3]; e = vals[4]; f = vals[5];

    if (strcmp(name, "translate") == 0) {
      t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(a, got > 1 ? b : 0));
    } else if (strcmp(name, "scale") == 0) {
      t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(a, got > 1 ? b : a));
    } else if (strcmp(name, "rotate") == 0) {
      if (got >= 3) {
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(b, c));
        t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(a * M_PI / 180.0));
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(-b, -c));
      } else {
        t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(a * M_PI / 180.0));
      }
    } else if (strcmp(name, "matrix") == 0 && got == 6) {
      t = CGAffineTransformConcat(t, CGAffineTransformMake(a, b, c, d, e, f));
    }
  }
  return t;
}

#pragma mark - 渲染

/// 需要整段跳过的容器（图标里只用到 clipPath/defs/gradient，都不影响图形本身）
static BOOL DSIsSkippedContainer(NSString *name) {
  static NSSet<NSString *> *set = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    set = [NSSet setWithArray:@[ @"defs", @"clippath", @"lineargradient", @"radialgradient",
                                 @"style", @"title", @"desc", @"mask", @"filter", @"symbol" ]];
  });
  return [set containsObject:name];
}

/// 样式表（g 上继承）
static NSMutableDictionary<NSString *, NSString *> *DSMergeStyle(NSDictionary *parent,
                                                                NSDictionary *own) {
  NSMutableDictionary *m = parent ? [parent mutableCopy] : [NSMutableDictionary dictionary];
  for (NSString *k in own) {
    NSString *v = own[k];
    if (v.length) m[k] = v;
  }
  return m;
}

static void DSDrawSVG(NSString *svg, CGFloat size, UIColor *tint, CGContextRef ctx) {
  // 先找 viewBox
  CGFloat vbX = 0, vbY = 0, vbW = 0, vbH = 0;
  {
    const char *p = svg.UTF8String;
    NSString *tag;
    while ((tag = DSNextTag(&p))) {
      NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
      NSString *name = DSParseTag(tag, attrs);
      if (![name isEqualToString:@"svg"]) continue;
      NSString *vb = attrs[@"viewbox"];   // DSParseTag 会把属性名统一小写
      if (vb.length) {
        sscanf(vb.UTF8String, "%lf %lf %lf %lf", &vbX, &vbY, &vbW, &vbH);
      }
      if (vbW <= 0) vbW = [attrs[@"width"] doubleValue];
      if (vbH <= 0) vbH = [attrs[@"height"] doubleValue];
      break;
    }
  }
  if (vbW <= 0 || vbH <= 0) { vbW = vbH = 24.0; vbX = vbY = 0; }

  CGFloat sx = size / vbW, sy = size / vbH;
  CGContextTranslateCTM(ctx, 0, size);
  CGContextScaleCTM(ctx, sx, -sy);
  CGContextTranslateCTM(ctx, -vbX, -vbY);

  const char *p = svg.UTF8String;
  NSMutableArray<NSDictionary *> *stack = [NSMutableArray array];
  NSString *skipName = nil;
  int skipDepth = 0;

  NSString *tag;
  while ((tag = DSNextTag(&p))) {
    if (tag.length == 0) continue;
    BOOL closing = [tag characterAtIndex:0] == '/';
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    NSString *name = DSParseTag(tag, attrs);

    if (skipDepth > 0) {
      if ([name isEqualToString:skipName]) {
        if (closing) skipDepth--; else skipDepth++;
      }
      continue;
    }
    if (!closing && DSIsSkippedContainer(name)) {
      // 自闭合就不用进栈
      NSString *last = tag.length ? [tag substringFromIndex:tag.length - 1] : @"";
      if (![last isEqualToString:@"/"]) {
        skipName = name;
        skipDepth = 1;
      }
      continue;
    }
    if ([name isEqualToString:@"svg"]) {
      if (closing) {
        if (stack.count) [stack removeLastObject];
      } else {
        [stack addObject:DSMergeStyle(stack.lastObject, attrs)];
      }
      continue;
    }
    if ([name isEqualToString:@"g"]) {
      if (closing) {
        if (stack.count) [stack removeLastObject];
      } else {
        [stack addObject:DSMergeStyle(stack.lastObject, attrs)];
      }
      continue;
    }
    if (closing) continue;

    // 必须写成带泛型的字典：不带泛型时下标返回 id，后面 style[@"x"] 之类
    // 调 doubleValue / length 会直接编译失败（-Werror 下就是 error）。
    NSDictionary<NSString *, NSString *> *style = DSMergeStyle(stack.lastObject, attrs);

    // ---- 构造几何 ----
    CGMutablePathRef path = NULL;
    if ([name isEqualToString:@"path"]) {
      NSString *d = style[@"d"];
      if (d.length) path = DSCreatePathFromData(d);
    } else if ([name isEqualToString:@"rect"]) {
      CGFloat x = [style[@"x"] doubleValue], y = [style[@"y"] doubleValue];
      CGFloat w = [style[@"width"] doubleValue], h = [style[@"height"] doubleValue];
      CGFloat rx = [style[@"rx"] doubleValue], ry = [style[@"ry"] doubleValue];
      if (w > 0 && h > 0) {
        CGRect r = CGRectMake(x, y, w, h);
        if (rx > 0 || ry > 0) {
          if (rx <= 0) rx = ry;
          if (ry <= 0) ry = rx;
          path = CGPathCreateMutable();
          // CGPath 只有统一圆角，取较小的那个，官方图标里 rx==ry
          CGPathAddRoundedRect(path, NULL, r, MIN(rx, ry), MIN(rx, ry));
        } else {
          path = CGPathCreateMutable();
          CGPathAddRect(path, NULL, r);
        }
      }
    } else if ([name isEqualToString:@"circle"]) {
      CGFloat cx = [style[@"cx"] doubleValue], cy = [style[@"cy"] doubleValue];
      CGFloat r = [style[@"r"] doubleValue];
      if (r > 0) {
        path = CGPathCreateMutable();
        CGPathAddEllipseInRect(path, NULL, CGRectMake(cx - r, cy - r, 2 * r, 2 * r));
      }
    } else if ([name isEqualToString:@"ellipse"]) {
      CGFloat cx = [style[@"cx"] doubleValue], cy = [style[@"cy"] doubleValue];
      CGFloat rx = [style[@"rx"] doubleValue], ry = [style[@"ry"] doubleValue];
      if (rx > 0 && ry > 0) {
        path = CGPathCreateMutable();
        CGPathAddEllipseInRect(path, NULL, CGRectMake(cx - rx, cy - ry, 2 * rx, 2 * ry));
      }
    } else if ([name isEqualToString:@"line"]) {
      path = CGPathCreateMutable();
      CGPathMoveToPoint(path, NULL, [style[@"x1"] doubleValue], [style[@"y1"] doubleValue]);
      CGPathAddLineToPoint(path, NULL, [style[@"x2"] doubleValue], [style[@"y2"] doubleValue]);
    }
    if (path == NULL) continue;

    // ---- 上色 ----
    // fill 缺省是黑（SVG 默认），但官方图标根节点写了 fill="none"，所以这里严格按属性走。
    NSString *fillAttr = style[@"fill"];
    NSString *strokeAttr = style[@"stroke"];
    UIColor *fillColor = DSSVGColor(fillAttr, tint);
    UIColor *strokeColor = DSSVGColor(strokeAttr, tint);
    if (fillAttr.length == 0 && strokeAttr.length == 0) fillColor = tint ?: [UIColor blackColor];
    NSString *sw = style[@"stroke-width"];
    CGFloat strokeWidth = sw.length ? sw.doubleValue : 1.0;
    BOOL evenOdd = [style[@"fill-rule"] isEqualToString:@"evenodd"] ||
                   [style[@"clip-rule"] isEqualToString:@"evenodd"];

    CGContextSaveGState(ctx);
    NSString *tf = style[@"transform"];
    if (tf.length) CGContextConcatCTM(ctx, DSParseTransform(tf));
    NSString *op = style[@"opacity"];
    if (op.length) CGContextSetAlpha(ctx, [op doubleValue]);

    if (fillColor) CGContextSetFillColorWithColor(ctx, fillColor.CGColor);
    if (strokeColor) {
      CGContextSetStrokeColorWithColor(ctx, strokeColor.CGColor);
      CGContextSetLineWidth(ctx, strokeWidth);
      NSString *cap = style[@"stroke-linecap"];
      CGContextSetLineCap(ctx, [cap isEqualToString:@"round"] ? kCGLineCapRound
                            : [cap isEqualToString:@"square"] ? kCGLineCapSquare
                                                             : kCGLineCapButt);
      NSString *join = style[@"stroke-linejoin"];
      CGContextSetLineJoin(ctx, [join isEqualToString:@"round"] ? kCGLineJoinRound
                             : [join isEqualToString:@"bevel"] ? kCGLineJoinBevel
                                                              : kCGLineJoinMiter);
    }

    CGContextAddPath(ctx, path);
    if (fillColor && strokeColor) {
      CGContextDrawPath(ctx, evenOdd ? kCGPathEOFillStroke : kCGPathFillStroke);
    } else if (fillColor) {
      CGContextDrawPath(ctx, evenOdd ? kCGPathEOFill : kCGPathFill);
    } else if (strokeColor) {
      CGContextDrawPath(ctx, kCGPathStroke);
    }

    CGContextRestoreGState(ctx);
    CGPathRelease(path);
  }
}

#pragma mark - 实现

@implementation DSSVGIcon

+ (NSCache<NSString *, UIImage *> *)cache {
  static NSCache *cache = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 256;
  });
  return cache;
}

+ (nullable UIImage *)imageNamed:(NSString *)key size:(CGFloat)size {
  return [self imageNamed:key size:size tint:nil];
}

+ (nullable UIImage *)imageNamed:(NSString *)key size:(CGFloat)size tint:(nullable UIColor *)tint {
  if (key.length == 0 || size <= 0) return nil;
  const char *src = DSIconAssetSource(key.UTF8String);
  if (src == NULL) return nil;
  NSString *svg = [NSString stringWithUTF8String:src];
  if (svg.length == 0) return nil;

  CGFloat r = 0, g = 0, b = 0, a = 0;
  [tint getRed:&r green:&g blue:&b alpha:&a];
  NSString *cacheKey = [NSString stringWithFormat:@"%@|%.1f|%@", key, size,
                                                  tint ? [NSString stringWithFormat:@"%02X%02X%02X",
                                                          (int)(r * 255), (int)(g * 255), (int)(b * 255)]
                                                       : @"-"];
  UIImage *hit = [[self cache] objectForKey:cacheKey];
  if (hit) return hit;

  UIImage *img = [self imageWithSVG:svg size:size tint:tint];
  if (img) [[self cache] setObject:img forKey:cacheKey];
  return img;
}

+ (nullable UIImage *)imageWithSVG:(NSString *)svg size:(CGFloat)size tint:(nullable UIColor *)tint {
  if (svg.length == 0 || size <= 0) return nil;
  UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
  fmt.opaque = NO;
  UIGraphicsImageRenderer *renderer =
      [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:fmt];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
    DSDrawSVG(svg, size, tint, ctx.CGContext);
  }];
}

+ (nullable CGPathRef)newPathFromData:(NSString *)d CF_RETURNS_RETAINED {
  if (d.length == 0) return NULL;
  return DSCreatePathFromData(d);
}

@end
