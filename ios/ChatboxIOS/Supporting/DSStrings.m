//
//  DSStrings.m
//  ChatboxIOS
//

#import "DSStrings.h"

#pragma mark - 会话列表

NSString *const DSStrNewChatTitle = @"新对话";
NSString *const DSStrSessionListEmptyTitle = @"暂无对话";
NSString *const DSStrSessionListEmptyDesc = @"你与 DeepSeek 的对话\n将展示在这里";
NSString *const DSStrStartNewChat = @"开启新对话";
NSString *const DSStrGroupPinned = @"置顶";
NSString *const DSStrGroupToday = @"今天";
NSString *const DSStrGroupYesterday = @"昨天";
NSString *const DSStrGroup7Days = @"7 天内";
NSString *const DSStrGroup30Days = @"30 天内";
NSString *const DSStrGroupEarlier = @"更早";
NSString *const DSStrSearchHint = @"搜索对话内容...";
NSString *const DSStrSearchNoResult = @"暂无相关结果";
NSString *const DSStrDeleteSession = @"删除";
NSString *const DSStrDeleteSessionModal = @"删除后，该对话将不可恢复";
NSString *const DSStrDeleteSessionDesc = @"由该对话生成的分享链接也将失效";
NSString *const DSStrRenameSession = @"重命名";
NSString *const DSStrRenameSessionTitle = @"重命名对话";
NSString *const DSStrPinSession = @"置顶";
NSString *const DSStrUnpinSession = @"取消置顶";
NSString *const DSStrDeleteAllChats = @"删除所有历史对话";
NSString *const DSStrDeleteAllConfirm = @"删除所有对话";

#pragma mark - 聊天页

NSString *const DSStrInputPlaceholder = @"发消息";
NSString *const DSStrSend = @"发送";
NSString *const DSStrSending = @"发送中";
NSString *const DSStrStop = @"停止";
NSString *const DSStrNewLine = @"换行";
NSString *const DSStrThinking = @"正在思考";
NSString *const DSStrThinkingDone = @"已思考";
NSString *const DSStrThinkAutoFold = @"思考内容自动折叠";
NSString *const DSStrThinkAutoFoldDesc = @"开启后，思考结束后将自动折叠思考内容";
NSString *const DSStrRegenerate = @"再试一次";
NSString *const DSStrRegenerateSearchOn = @"搜索网页";
NSString *const DSStrRegenerateSearchOff = @"关闭搜索";
NSString *const DSStrRegenerateVerbose = @"更加详细";
NSString *const DSStrRegenerateBrief = @"更加简洁";
NSString *const DSStrAIAlert = @"回答由 AI 生成，仅供参考";
NSString *const DSStrContextLimitTitle = @"对话长度已达上限";
NSString *const DSStrContextLimitDesc =
    @"为保证回复质量，对话有长度限制。当前对话已达上限，无法继续回复，请开启新对话。";
NSString *const DSStrContextLimitConfirm = @"我知道了";
NSString *const DSStrBranchSwitcher = @"第 %1$ld 条消息（共 %2$ld 条）";

#pragma mark - 消息操作

NSString *const DSStrCopy = @"复制";
NSString *const DSStrCopied = @"已复制";
NSString *const DSStrShare = @"分享";
NSString *const DSStrReadAloud = @"朗读音色";

#pragma mark - 工具卡片

NSString *const DSStrToolSearchWip = @"搜索中...";
NSString *const DSStrToolSearchQuery = @"搜索 %@";
NSString *const DSStrToolSearchDone = @"已搜索 %@";
NSString *const DSStrToolSearchResult = @"搜索结果";
NSString *const DSStrToolSearchEmpty = @"未搜索到合适内容";
NSString *const DSStrToolSearchFailed = @"联网搜索暂不可用";
NSString *const DSStrToolOpen = @"浏览";
NSString *const DSStrToolOpenSearchResult = @"浏览搜索结果";
NSString *const DSStrToolOpenFailed = @"浏览失败";
NSString *const DSStrToolFindWip = @"正在查找“%@”";
NSString *const DSStrToolFindDone = @"已查找到“%@”";
NSString *const DSStrToolFindEmpty = @"未查找到“%@”";
NSString *const DSStrToolFindFailed = @"查找失败";
NSString *const DSStrMergeSearchCount = @"已搜索到 %ld 个网页";
NSString *const DSStrMergeOpenCount = @"已浏览 %ld 个页面";

#pragma mark - 模型

NSString *const DSStrModelDefault = @"快速模式";
NSString *const DSStrModelDefaultDesc = @"适合日常对话，即时响应";
NSString *const DSStrModelExpert = @"专家模式";
NSString *const DSStrModelExpertDesc = @"擅长复杂问题，高峰需等待";
NSString *const DSStrModelVision = @"识图模式";
NSString *const DSStrModelVisionDesc = @"擅长理解图片内容";

#pragma mark - 附件

NSString *const DSStrAttachFiles = @"上传文件";
NSString *const DSStrUploading = @"正在上传";
NSString *const DSStrFileParserWip = @"解析中...";
NSString *const DSStrFileUploadWip = @"上传中...";
NSString *const DSStrFileFailed = @"解析失败";
NSString *const DSStrFileNoText = @"未提取到文字";
NSString *const DSStrUploadAlbum = @"相册";
NSString *const DSStrUploadCamera = @"拍照";
NSString *const DSStrUploadFile = @"文件";
NSString *const DSStrVoiceHoldToTalk = @"按住说话";

#pragma mark - 通用

NSString *const DSStrSettings = @"设置";
NSString *const DSStrPersonalization = @"个性化";
NSString *const DSStrFontSize = @"字体大小";
NSString *const DSStrResponseSettings = @"回答设置";
NSString *const DSStrDataControls = @"数据管理";
NSString *const DSStrAbout = @"关于";
NSString *const DSStrCancel = @"取消";
NSString *const DSStrOK = @"好";
NSString *const DSStrConfirm = @"确认";
NSString *const DSStrSave = @"保存";
NSString *const DSStrDeleteWord = @"删除";

NSString *const DSStrAPIKey = @"API Key";
NSString *const DSStrThinkStrength = @"思考强度";
NSString *const DSStrContextLimit = @"上下文限制";
NSString *const DSStrTemperature = @"温度";
NSString *const DSStrSystemPrompt = @"系统提示词";

#pragma mark - 补充文案

NSString *const DSStrSearching = @"搜索中...";
NSString *const DSStrDeepThink = @"深度思考";
NSString *const DSStrSearched = @"已搜索";
NSString *const DSStrBrowsing = @"浏览";
NSString *const DSStrBrowseFailed = @"浏览失败";
NSString *const DSStrFindFailed = @"查找失败";
NSString *const DSStrSearchFailed = @"联网搜索暂不可用";
NSString *const DSStrSources = @"引用来源";
NSString *const DSStrToolCalls = @"工具调用";
NSString *const DSStrExpand = @"展开";
NSString *const DSStrCollapse = @"收起";
NSString *const DSStrToolResult = @"执行结果";
NSString *const DSStrGenerating = @"生成中";
NSString *const DSStrStopped = @"已停止生成";
NSString *const DSStrHoldToTalk = @"按住说话";
NSString *const DSStrReleaseToSend = @"松开 发送";
NSString *const DSStrSlideUpToCancel = @"上滑 取消";
NSString *const DSStrRecognizing = @"识别中...";
NSString *const DSStrAttachments = @"附件";
NSString *const DSStrRemoveAttachment = @"移除";
NSString *const DSStrModelSwitch = @"切换模型";
NSString *const DSStrRetry = @"重试";

// 工具名 → 中文名。与 tool_defs.json 的 40 个工具一一对应；改工具清单时同步这里。
// 官方的联网类工具（web_search/fetch_url）用官方文案「联网搜索」「读取网页」，
// 其余是本机内置工具，官方没有，命名属自创（保持动词/名词短语风格统一）。
static NSDictionary<NSString *, NSString *> *DSToolLabels(void) {
  static NSDictionary *map = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    map = @{
      @"get_balance": @"账户余额", @"list_models": @"模型列表", @"current_time": @"当前时间",
      @"search_history": @"搜索历史", @"usage_stats": @"用量统计", @"web_search": @"联网搜索",
      @"fetch_url": @"读取网页", @"calculator": @"计算器", @"hash_text": @"哈希计算",
      @"base64_codec": @"Base64 编解码", @"url_codec": @"URL 编解码", @"json_format": @"JSON 格式化",
      @"text_stats": @"文本统计", @"uuid_gen": @"生成 UUID", @"random_pick": @"随机选择",
      @"dns_lookup": @"DNS 查询", @"port_check": @"端口检测", @"http_request": @"HTTP 请求",
      @"local_ip": @"本机 IP", @"base_convert": @"进制转换", @"percentage": @"百分比计算",
      @"date_diff": @"日期差计算", @"unit_convert": @"单位换算", @"regex_test": @"正则测试",
      @"diff_text": @"文本对比", @"csv_json": @"CSV/JSON 转换", @"slugify": @"生成 Slug",
      @"password_gen": @"生成密码", @"id_validator": @"证件校验", @"timestamp_convert": @"时间戳转换",
      @"json_minify": @"JSON 压缩", @"token_count": @"Token 计数", @"qr_text": @"生成二维码",
      @"stat_calc": @"统计计算", @"hex_view": @"十六进制查看", @"color_convert": @"颜色转换",
      @"text_kit": @"文本工具", @"aes_crypto": @"AES 加密", @"find_tool": @"查找工具",
      @"cmd_run": @"执行命令",
    };
  });
  return map;
}

NSString *DSStrToolLabel(NSString *toolName) {
  if (toolName.length == 0) return DSStrToolCalls;
  NSString *label = DSToolLabels()[toolName];
  return label.length ? label : toolName;
}

NSString *DSStrToolKind(NSString *toolName) {
  // 官方三类 Fragment：ToolSearchFragmentView / ToolOpenFragmentView / ToolFindFragmentView
  if ([toolName isEqualToString:@"web_search"]) return @"search";
  if ([toolName isEqualToString:@"fetch_url"] || [toolName isEqualToString:@"http_request"]) return @"open";
  if ([toolName isEqualToString:@"find_tool"] || [toolName isEqualToString:@"search_history"]) return @"find";
  return @"local";
}

