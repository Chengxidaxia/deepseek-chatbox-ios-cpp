#import "AppDelegate.h"
#import "DSBoxService.h"
#import "DSConversationListController.h"
#import <UserNotifications/UserNotifications.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
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
  return YES;
}

@end
