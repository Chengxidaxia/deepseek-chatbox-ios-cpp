#import "AppDelegate.h"
#import "DSBoxService.h"
#import "DSConversationListController.h"
#import <UserNotifications/UserNotifications.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// ---------------------------------------------------------------------------
// 崩溃兜底：ad-hoc 包拿不到系统 .ips 日志，出问题只能靠这个。
//
// 分两条路：
//   ObjC 未捕获异常 —— 运行时还在，可以放心用 Foundation，写完整描述 + 调用栈
//   致命信号（SIGSEGV 等）—— 上下文里调 Foundation 可能死锁，把「崩」变成「卡死」，
//                            所以只做 async-signal-safe 的 open/write，写一行标记
//
// 日志落在 Caches/last-crash.log，下次启动弹一次，可复制，看完删除。
// ---------------------------------------------------------------------------

static char g_crashPath[512];   // 信号处理里只能用 C 字符串，启动时填好

static void DSCrashPathInit(void) {
  NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
  NSString *p = [dir stringByAppendingPathComponent:@"last-crash.log"];
  const char *c = p.UTF8String;
  if (!c) return;
  snprintf(g_crashPath, sizeof(g_crashPath), "%s", c);
}

/// 信号名。不用 strsignal：它在不同 SDK 里的可用性和线程安全性都不稳，
/// 而且信号处理里只该调 async-signal-safe 的东西，一张静态表最稳。
static const char *DSSignalName(int sig) {
  switch (sig) {
    case SIGABRT: return "SIGABRT（abort/异常）";
    case SIGSEGV: return "SIGSEGV（野指针/越界）";
    case SIGBUS:  return "SIGBUS（总线错误）";
    case SIGFPE:  return "SIGFPE（算术异常）";
    case SIGILL:  return "SIGILL（非法指令）";
    case SIGTRAP: return "SIGTRAP（断点/运行时检查）";
    default:      return "未知信号";
  }
}

static NSString *DSCrashPath(void) {
  return g_crashPath[0] ? [NSString stringWithUTF8String:g_crashPath] : nil;
}

static void DSWriteCrashText(NSString *text) {
  NSString *p = DSCrashPath();
  if (!p) return;
  [text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void DSExceptionHandler(NSException *e) {
  NSString *text = [NSString stringWithFormat:
      @"时间: %@\n版本: %@ (%@)\n类型: ObjC 未捕获异常\n\n%@: %@\n\n调用栈:\n%@\n",
      [NSDate date],
      [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"],
      [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"],
      e.name, e.reason ?: @"(无描述)",
      [e.callStackSymbols componentsJoinedByString:@"\n"]];
  DSWriteCrashText(text);
  NSLog(@"[crash] %@", text);
}

static void DSSignalHandler(int sig) {
  // 这里不能碰 Foundation：只用 open/write，保证不会死锁
  if (g_crashPath[0]) {
    int fd = open(g_crashPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
      char buf[128];
      int n = snprintf(buf, sizeof(buf), "类型: 致命信号 %d %s\n（无调用栈：信号上下文里不能调 Foundation）\n",
                       sig, DSSignalName(sig));
      if (n > 0) { ssize_t w = write(fd, buf, (size_t)n); (void)w; }
      close(fd);
    }
  }
  signal(sig, SIG_DFL);
  raise(sig);
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  DSCrashPathInit();
  NSSetUncaughtExceptionHandler(&DSExceptionHandler);
  static int kSigs[] = {SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP};
  for (size_t i = 0; i < sizeof(kSigs) / sizeof(kSigs[0]); i++) signal(kSigs[i], DSSignalHandler);

  // 打开本地 SQLite
  NSError *err = nil;
  if (![[DSBoxService shared] openStoreWithError:&err]) {
    NSLog(@"存储打开失败: %@", err.localizedDescription);
  }

  DSConversationListController *list = [[DSConversationListController alloc] init];
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
  if (@available(iOS 15.0, *)) {
    UINavigationBarAppearance *app = [UINavigationBarAppearance new];
    app.backgroundColor = [UIColor systemBackgroundColor];
    nav.navigationBar.standardAppearance = app;
    nav.navigationBar.scrollEdgeAppearance = app;
  }

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];

  [self showLastCrashIfAny];
  return YES;
}

/// 上次崩过就把日志弹出来（可复制），看完删除，不反复打扰
- (void)showLastCrashIfAny {
  NSString *path = DSCrashPath();
  if (!path) return;
  NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  if (!log.length) return;

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    NSString *shown = log.length > 1200 ? [log substringToIndex:1200] : log;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"上次运行崩溃了"
        message:shown preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"复制日志" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
      UIPasteboard.generalPasteboard.string = log;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel
                                        handler:^(UIAlertAction *x) {
      [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
  });
}

@end
