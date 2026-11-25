//
//  DSIcon.h
//  ChatboxIOS
//
//  图标一律用官方包里的原始矢量。源码来自官方 `Assets.car` 的 `ISTC` rendition
//  （LZVN 解压后是 SVG），由 DSSVGIcon 直接渲染成 UIImage —— 所以形状、线宽、
//  圆角、端点都和官方逐字节一致，不再靠「按几何特征重绘」去猜。
//
//  尺寸口径也跟官方一致：官方图标只有 16 / 20 / 24 三种画布，
//  16 用于输入条里的开关，20 用于列表与操作，24 用于顶栏。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 官方画布尺寸（pt）
extern const CGFloat DSIconPointSizeInline;  // 16
extern const CGFloat DSIconPointSizeAction;  // 20
extern const CGFloat DSIconPointSizeNav;     // 24

typedef NS_ENUM(NSInteger, DSIconName) {
  // —— 顶栏 ——
  DSIconMenu = 0,        // ic_menu_outline_24      打开会话列表
  DSIconNewChat,         // ic_new_chat_outline_24  新对话
  DSIconChevronDown,     // ic_chevron_down_outline_20
  DSIconChevronUp,       // chevron_up_fill
  DSIconChevronLeft,     // ic_chevron_left_outline_20
  DSIconChevronRight,    // ic_chevron_right_outline_20
  DSIconArrowRight,      // ic_arrow_right_outline_16
  DSIconClose,           // ic_close_outline_24
  // 官方 Assets.car 里那个 ic_ellipsis_outline_20 其实是**竖**三点（kebab）。
  // 「更多操作」这个语义在 iOS 上应该是横三点（meatball），所以这里指向
  // 由它旋转 90° 得到的 ic_ellipsis_horizontal_outline_20 —— 圆点半径与间距不变。
  DSIconMore,            // ic_ellipsis_horizontal_outline_20
  DSIconMoreVertical,    // ic_ellipsis_outline_20（官方原素材，竖版，留作它用）

  // —— 输入条 ——
  DSIconThink,           // ic_think_outline_16     深度思考
  DSIconSearch,          // ic_search_outline_16    搜索
  DSIconGlobe,           // ic_globe_language_outline_16  联网 / 智能搜索
  DSIconPlus,            // ic_plus_outline_20
  DSIconAttach,          // paperclip_regular
  DSIconCamera,          // camera_regular
  DSIconPhoto,           // ic_photo_outline_20
  DSIconMic,             // voice                   语音输入
  DSIconSend,            // ic_send_fill_20
  DSIconStop,            // ic_stop_fill_20

  // —— 模型 ——
  DSIconLightning,       // ic_flash_filled_16      快速
  DSIconExpert,          // ic_expert_filled_16     专家
  DSIconVision,          // ic_vision_filled_16     识图

  // —— 消息操作 ——
  DSIconCopy,            // ic_copy_outline_20
  DSIconRefresh,         // ic_refresh_outline_20
  DSIconLike,            // ic_like_outline_20
  DSIconLikeFill,        // ic_like_fill_20
  DSIconDislike,         // ic_dislike_outline_20
  DSIconDislikeFill,     // ic_dislike_fill_20
  DSIconShare,           // ic_share_outline_20
  DSIconDownload,        // ic_download_outline_20
  DSIconSpeaker,         // ic_playing_fill_24      朗读
  DSIconPlay,            // ic_play_media_outline_24

  // —— 会话列表 ——
  DSIconPin,             // ic_pin_outline_20
  DSIconUnpin,           // ic_unpin_outline_20
  DSIconTrash,           // ic_trash_outline_20
  DSIconEdit,            // ic_edit_outline_20

  // —— 状态 ——
  DSIconCheck,           // ic_check_outline_20
  DSIconChecked,         // ic_checked_filled_16
  DSIconInfo,            // ic_info_outline_16
  DSIconWarning,         // ic_warning_outline_16
  DSIconBrowse,          // ic_browse_outline_16    网页浏览中
  DSIconSearchWarning,   // ic_search_warning_outline_16
  DSIconLoading,         // loading                 转圈
  DSIconContinue,        // chat_continue           继续生成
  DSIconPhone,           // ic_phone_outline_20
  DSIconEye,             // eye_regular
  DSIconUserCircle,      // user_circle_filled

  // —— 旧名兼容（语义不变，只是换成官方资源）——
  DSIconBrain = DSIconExpert,
  DSIconDoc = DSIconBrowse,
  DSIconFile = DSIconAttach,
};

@interface DSIcon : NSObject

/// 模板图：形状取官方矢量，颜色跟随 tintColor（最常用）。
+ (nullable UIImage *)image:(DSIconName)name size:(CGFloat)size;

/// 指定颜色的实色图（不跟随 tintColor）。
+ (nullable UIImage *)image:(DSIconName)name size:(CGFloat)size color:(UIColor *)color;

/// 保留官方自带配色的原图（多色图标用，例如发送箭头）。
+ (nullable UIImage *)officialImage:(DSIconName)name size:(CGFloat)size;

/// 直接按官方资源名取图（保留官方配色）。
+ (nullable UIImage *)imageWithAssetKey:(NSString *)key size:(CGFloat)size;

/// 枚举 → 官方资源名，便于排查。
+ (nullable NSString *)assetKeyForName:(DSIconName)name;

@end

NS_ASSUME_NONNULL_END
