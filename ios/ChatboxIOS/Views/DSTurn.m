//
//  DSTurn.m
//  ChatboxIOS
//

#import "DSTurn.h"

@implementation DSTurn

- (instancetype)init {
  if ((self = [super init])) {
    _rounds = [NSMutableArray array];
    _toolResults = [NSMutableDictionary dictionary];
    _serverCalls = [NSMutableArray array];
    _citations = [NSMutableArray array];
    _branchIndex = 0;
    _branchTotal = 1;
  }
  return self;
}

+ (NSArray<DSTurn *> *)turnsFromMessages:(NSArray<NSDictionary *> *)messages {
  NSMutableArray<DSTurn *> *turns = [NSMutableArray array];
  // 上一个 user 消息的分支信息，挂到紧随其后的助手 turn 上
  NSArray<NSDictionary *> *pendingBranches = nil;
  NSInteger pendingIndex = 0;

  NSUInteger i = 0;
  while (i < messages.count) {
    NSDictionary *m = messages[i];
    NSString *role = m[@"role"] ?: @"";

    if ([role isEqualToString:@"user"]) {
      DSTurn *t = [[DSTurn alloc] init];
      t.role = DSTurnRoleUser;
      t.anchor = m;
      NSArray *br = [m[@"branches"] isKindOfClass:NSArray.class] ? m[@"branches"] : nil;
      t.branches = br;
      t.branchTotal = MAX(1, (NSInteger)br.count);
      t.branchIndex = [m[@"branchIndex"] isKindOfClass:NSNumber.class] ? [m[@"branchIndex"] integerValue] : 0;
      if (t.branchIndex >= t.branchTotal) t.branchIndex = t.branchTotal - 1;
      [turns addObject:t];
      pendingBranches = br;
      pendingIndex = t.branchIndex;
      i++;
      continue;
    }

    if ([role isEqualToString:@"assistant"]) {
      DSTurn *t = [[DSTurn alloc] init];
      t.role = DSTurnRoleAssistant;
      t.anchor = m;
      t.branches = pendingBranches;
      t.branchTotal = MAX(1, (NSInteger)pendingBranches.count);
      t.branchIndex = pendingIndex;
      pendingBranches = nil;

      while (i < messages.count) {
        NSDictionary *p = messages[i];
        NSString *r = p[@"role"] ?: @"";
        if ([r isEqualToString:@"user"]) break;
        if ([r isEqualToString:@"assistant"]) {
          [t.rounds addObject:p];
          if ([p[@"streaming"] boolValue]) t.streaming = YES;
          NSArray *srv = [p[@"server_tool_calls"] isKindOfClass:NSArray.class] ? p[@"server_tool_calls"] : nil;
          if (srv.count) {
            // 同一轮可能多次下发，按 type+query 合并：后到的覆盖前面的同名调用
            for (NSDictionary *c in srv) {
              if (![c isKindOfClass:NSDictionary.class]) continue;
              NSString *key = [NSString stringWithFormat:@"%@|%@", c[@"id"] ?: @"", c[@"type"] ?: @""];
              NSInteger exist = -1;
              for (NSInteger k = 0; k < (NSInteger)t.serverCalls.count; k++) {
                NSDictionary *old = t.serverCalls[(NSUInteger)k];
                NSString *oldKey = [NSString stringWithFormat:@"%@|%@", old[@"id"] ?: @"", old[@"type"] ?: @""];
                if ([oldKey isEqualToString:key]) { exist = k; break; }
              }
              if (exist >= 0) t.serverCalls[(NSUInteger)exist] = c;
              else [t.serverCalls addObject:c];
            }
          }
          NSArray *ann = [p[@"annotations"] isKindOfClass:NSArray.class] ? p[@"annotations"] : nil;
          if (ann.count) {
            for (NSDictionary *a in ann)
              if ([a isKindOfClass:NSDictionary.class]) [t.citations addObject:a];
          }
        } else if ([r isEqualToString:@"tool"]) {
          NSString *cid = p[@"tool_call_id"];
          if ([cid isKindOfClass:NSString.class] && cid.length) t.toolResults[cid] = p;
        }
        i++;
      }
      [turns addObject:t];
      continue;
    }

    i++;  // 孤立的 tool / system 消息不单独成行
  }
  return turns;
}

- (NSDictionary *)tailRound {
  for (NSDictionary *r in self.rounds.reverseObjectEnumerator) {
    NSString *c = [r[@"content"] isKindOfClass:NSString.class] ? r[@"content"] : @"";
    if (c.length) return r;
  }
  return self.rounds.lastObject;
}

@end
