//
//  DSStrings.h
//  ChatboxIOS
//
//  界面文案。来源：官方 iOS App（DeepSeek-2.7.1.ipa）zh-Hans.lproj/Localizable.strings
//  抽取的 806 条中的相关子集，key 原样保留在注释里，便于回溯核对。
//  标注「自创」的是官方没有、本 App 独有的条目（本地 API Key / 思考强度等）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 会话列表  （SessionList* / session*）

extern NSString *const DSStrNewChatTitle;            // sessionInitTitle = 新对话
extern NSString *const DSStrSessionListEmptyTitle;   // sessionListEmptyTitle = 暂无对话
extern NSString *const DSStrSessionListEmptyDesc;    // sessionListEmptyDescription
extern NSString *const DSStrStartNewChat;            // sessionListNewChatButton = 开启新对话
extern NSString *const DSStrGroupPinned;             // sessionGroupPinned = 置顶
extern NSString *const DSStrGroupToday;              // sessionHistoryTimelineLabelToday = 今天
extern NSString *const DSStrGroupYesterday;          // sessionHistoryTimelineLabelYesterday = 昨天
extern NSString *const DSStrGroup7Days;              // sessionHistoryTimelineLabel7Days = 7 天内
extern NSString *const DSStrGroup30Days;             // sessionHistoryTimelineLabel30days = 30 天内
extern NSString *const DSStrGroupEarlier;            // 自创：更早
extern NSString *const DSStrSearchHint;              // searchHint = 搜索对话内容...
extern NSString *const DSStrSearchNoResult;          // searchEmptyResult = 暂无相关结果
extern NSString *const DSStrDeleteSession;           // deleteSessionAction = 删除
extern NSString *const DSStrDeleteSessionModal;      // sessionDeleteModal = 删除后，该对话将不可恢复
extern NSString *const DSStrDeleteSessionDesc;       // sessionDeleteDescription = 由该对话生成的分享链接也将失效
extern NSString *const DSStrRenameSession;           // renameSessionAction = 重命名
extern NSString *const DSStrRenameSessionTitle;      // renameSessionModalTitle = 重命名对话
extern NSString *const DSStrPinSession;              // sessionPinAction = 置顶
extern NSString *const DSStrUnpinSession;            // sessionUnpinAction = 取消置顶
extern NSString *const DSStrDeleteAllChats;          // profileDeleteAllChatButton = 删除所有历史对话
extern NSString *const DSStrDeleteAllConfirm;        // allSessionsDeleteConfirm = 删除所有对话

#pragma mark - 聊天页  （chatInput* / send / thinking / regenerate*）

extern NSString *const DSStrInputPlaceholder;        // chatInputPlaceholderChat = 发消息
extern NSString *const DSStrSend;                    // send = 发送
extern NSString *const DSStrSending;                 // sending = 发送中
extern NSString *const DSStrStop;                    // 自创：停止（官方靠按钮态，无独立文案）
extern NSString *const DSStrNewLine;                 // new_line_menu = 换行
extern NSString *const DSStrThinking;                // thinking = 正在思考
extern NSString *const DSStrThinkAutoFold;           // thinkingAutoFold = 思考内容自动折叠
extern NSString *const DSStrThinkAutoFoldDesc;       // thinkingAutoFoldDesc
extern NSString *const DSStrRegenerate;              // regenerateNormal = 再试一次
extern NSString *const DSStrRegenerateSearchOn;      // regenerateEnableSearch = 搜索网页
extern NSString *const DSStrRegenerateSearchOff;     // regenerateDisableSearch = 关闭搜索
extern NSString *const DSStrRegenerateVerbose;       // regenerateVerbosityHigh = 更加详细
extern NSString *const DSStrRegenerateBrief;         // regenerateVerbosityLow = 更加简洁
extern NSString *const DSStrAIAlert;                 // inputAIAlert = 回答由 AI 生成，仅供参考
extern NSString *const DSStrContextLimitTitle;       // hintClickContextExceedDialogTitle = 对话长度已达上限
extern NSString *const DSStrContextLimitDesc;        // hintClickContextExceedDialogDescription
extern NSString *const DSStrContextLimitConfirm;     // hintClickContextExceedDialogConfirm = 我知道了
extern NSString *const DSStrBranchSwitcher;          // branch_switcher_description = 第 %d 条消息（共 %d 条）

#pragma mark - 消息操作

extern NSString *const DSStrCopy;                    // copy = 复制
extern NSString *const DSStrCopied;                  // copyOk = 已复制
extern NSString *const DSStrShare;                   // share = 分享
extern NSString *const DSStrReadAloud;               // voiceSwitchBottomSheetTitle = 朗读音色

#pragma mark - 工具卡片  （tool* / mergeTool*）

extern NSString *const DSStrToolSearchWip;           // toolSearchWip = 搜索中...
extern NSString *const DSStrToolSearchQuery;         // toolSearchingWithQuery = 搜索 %@
extern NSString *const DSStrToolSearchDone;          // toolSearchFinished = 已搜索 %@
extern NSString *const DSStrToolSearchResult;        // toolSearchResult = 搜索结果
extern NSString *const DSStrToolSearchEmpty;         // toolSearchNoResult = 未搜索到合适内容
extern NSString *const DSStrToolSearchFailed;        // toolSearchFailed = 联网搜索暂不可用
extern NSString *const DSStrToolOpen;                // toolOpen = 浏览
extern NSString *const DSStrToolOpenSearchResult;    // toolOpenSearchResult = 浏览搜索结果
extern NSString *const DSStrToolOpenFailed;          // toolOpenFailed = 浏览失败
extern NSString *const DSStrToolFindWip;             // toolFindWip = 正在查找“%@”
extern NSString *const DSStrToolFindDone;            // toolFindFinished = 已查找到“%@”
extern NSString *const DSStrToolFindEmpty;           // toolFindNoResult = 未查找到“%@”
extern NSString *const DSStrToolFindFailed;          // toolFindFailed = 查找失败
extern NSString *const DSStrMergeSearchCount;        // mergeToolSearchResults = 已搜索到 %d 个网页
extern NSString *const DSStrMergeOpenCount;          // mergeToolOpenResults = 已浏览 %d 个页面

#pragma mark - 模型  （*ModelName / *ModelDescription）

extern NSString *const DSStrModelDefault;            // defaultModelName = 快速模式
extern NSString *const DSStrModelDefaultDesc;        // defaultModelDescription = 适合日常对话，即时响应
extern NSString *const DSStrModelExpert;             // expertModelName = 专家模式
extern NSString *const DSStrModelExpertDesc;         // expertModelDescription = 擅长复杂问题，高峰需等待
extern NSString *const DSStrModelVision;             // visionModelName = 识图模式
extern NSString *const DSStrModelVisionDesc;         // visionModelDescription = 擅长理解图片内容

#pragma mark - 附件  （upload* / attach_files / file*）

extern NSString *const DSStrAttachFiles;             // attach_files = 上传文件
extern NSString *const DSStrUploading;               // uploading = 正在上传
extern NSString *const DSStrFileParserWip;           // uploadFileStatusParsing = 解析中...
extern NSString *const DSStrFileUploadWip;           // uploadFileStatusUploading = 上传中...
extern NSString *const DSStrFileFailed;              // uploadFileStatusFailed = 解析失败
extern NSString *const DSStrFileNoText;              // uploadFileStatusContentEmpty = 未提取到文字
extern NSString *const DSStrUploadAlbum;             // uploadPanelAlbum = 相册
extern NSString *const DSStrUploadCamera;            // uploadPanelCamera = 拍照
extern NSString *const DSStrUploadFile;              // uploadPanelFile = 文件
extern NSString *const DSStrVoiceHoldToTalk;         // voiceInputButton = 按住说话

#pragma mark - 通用

extern NSString *const DSStrSettings;                // profileTitle = 设置
extern NSString *const DSStrPersonalization;         // personalization = 个性化
extern NSString *const DSStrFontSize;                // fontSize = 字体大小
extern NSString *const DSStrResponseSettings;        // responseSettings = 回答设置
extern NSString *const DSStrDataControls;            // dataControls = 数据管理
extern NSString *const DSStrAbout;                   // profileAboutSectionHeader = 关于
extern NSString *const DSStrCancel;                  // 自创：取消
extern NSString *const DSStrOK;                      // 自创：好
extern NSString *const DSStrConfirm;                 // 自创：确认
extern NSString *const DSStrSave;                    // 自创：保存
extern NSString *const DSStrDeleteWord;              // delete = 删除

// 以下为官方没有、本 App 独有的概念（自创）
extern NSString *const DSStrAPIKey;                  // API Key
extern NSString *const DSStrThinkStrength;           // 思考强度
extern NSString *const DSStrContextLimit;            // 上下文限制
extern NSString *const DSStrTemperature;             // 温度
extern NSString *const DSStrSystemPrompt;            // 系统提示词

NS_ASSUME_NONNULL_END
