//
//  DSIcon.m
//  ChatboxIOS
//

#import "DSIcon.h"
#import "DSSVGIcon.h"

const CGFloat DSIconPointSizeInline = 16.0;
const CGFloat DSIconPointSizeAction = 20.0;
const CGFloat DSIconPointSizeNav = 24.0;

/// 枚举 → 官方资源名。名字就是官方 `Assets.car` 里的资源名（去掉 .svg、小写），
/// 想核对某个图标长什么样，直接去 Resources/OfficialIcons 下同名文件看源码。
static NSString *DSIconAssetKey(DSIconName name) {
  switch (name) {
    case DSIconMenu: return @"ic_menu_outline_24";
    case DSIconNewChat: return @"ic_new_chat_outline_24";
    case DSIconChevronDown: return @"ic_chevron_down_outline_20";
    case DSIconChevronUp: return @"chevron_up_fill";
    case DSIconChevronLeft: return @"ic_chevron_left_outline_20";
    case DSIconChevronRight: return @"ic_chevron_right_outline_20";
    case DSIconArrowRight: return @"ic_arrow_right_outline_16";
    case DSIconClose: return @"ic_close_outline_24";
    case DSIconMore: return @"ic_ellipsis_outline_20";

    case DSIconThink: return @"ic_think_outline_16";
    case DSIconSearch: return @"ic_search_outline_16";
    case DSIconGlobe: return @"ic_globe_language_outline_16";
    case DSIconPlus: return @"ic_plus_outline_20";
    case DSIconAttach: return @"paperclip_regular";
    case DSIconCamera: return @"camera_regular";
    case DSIconPhoto: return @"ic_photo_outline_20";
    case DSIconMic: return @"call_microphone";
    case DSIconSend: return @"ic_send_fill_20";
    case DSIconStop: return @"ic_stop_fill_20";

    case DSIconLightning: return @"ic_flash_filled_16";
    case DSIconExpert: return @"ic_expert_filled_16";
    case DSIconVision: return @"ic_vision_filled_16";

    case DSIconCopy: return @"ic_copy_outline_20";
    case DSIconRefresh: return @"ic_refresh_outline_20";
    case DSIconLike: return @"ic_like_outline_20";
    case DSIconLikeFill: return @"ic_like_fill_20";
    case DSIconDislike: return @"ic_dislike_outline_20";
    case DSIconDislikeFill: return @"ic_dislike_fill_20";
    case DSIconShare: return @"ic_share_outline_20";
    case DSIconDownload: return @"ic_download_outline_20";
    case DSIconSpeaker: return @"voice";
    case DSIconPlay: return @"ic_play_media_outline_24";

    case DSIconPin: return @"ic_pin_outline_20";
    case DSIconUnpin: return @"ic_unpin_outline_20";
    case DSIconTrash: return @"ic_trash_outline_20";
    case DSIconEdit: return @"ic_edit_outline_20";

    case DSIconCheck: return @"ic_check_outline_20";
    case DSIconChecked: return @"ic_checked_filled_16";
    case DSIconInfo: return @"ic_info_outline_16";
    case DSIconWarning: return @"ic_warning_outline_16";
    case DSIconBrowse: return @"ic_browse_outline_16";
    case DSIconSearchWarning: return @"ic_search_warning_outline_16";
    case DSIconLoading: return @"loading";
    case DSIconContinue: return @"chat_continue";
    case DSIconPhone: return @"ic_phone_outline_20";
    case DSIconEye: return @"eye_regular";
    case DSIconUserCircle: return @"user_circle_filled";
  }
  return nil;
}

@implementation DSIcon

+ (NSString *)assetKeyForName:(DSIconName)name {
  return DSIconAssetKey(name);
}

+ (UIImage *)image:(DSIconName)name size:(CGFloat)size {
  UIImage *img = [DSSVGIcon imageNamed:DSIconAssetKey(name) size:size];
  // 模板化：形状来自官方矢量，颜色交给调用点的 tintColor。
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (UIImage *)image:(DSIconName)name size:(CGFloat)size color:(UIColor *)color {
  UIImage *img = [DSSVGIcon imageNamed:DSIconAssetKey(name) size:size tint:color];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)officialImage:(DSIconName)name size:(CGFloat)size {
  UIImage *img = [DSSVGIcon imageNamed:DSIconAssetKey(name) size:size];
  return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)imageWithAssetKey:(NSString *)key size:(CGFloat)size {
  return [DSSVGIcon imageNamed:key size:size];
}

@end
