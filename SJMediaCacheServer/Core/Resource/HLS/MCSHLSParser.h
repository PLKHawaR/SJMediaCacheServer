//
//  MCSHLSParser.h
//  SJMediaCacheServer_Example
//
//  Created by 畅三江 on 2020/6/9.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>
@protocol MCSHLSParserDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface MCSHLSParser : NSObject
- (instancetype)initWithURL:(NSURL *)URL inResource:(NSString *)resourceName delegate:(id<MCSHLSParserDelegate>)delegate delegateQueue:(dispatch_queue_t)queue;

- (void)prepare;

- (void)close;

@property (nonatomic, copy, readonly) NSString *resourceName;
@property (nonatomic, copy, readonly) NSString *indexFilePath;
@property (nonatomic, readonly) NSUInteger tsCount;
@property (nonatomic, readonly) BOOL isClosed;
@property (nonatomic, readonly) BOOL isDone;

- (NSURL *)tsURLWithTsName:(NSString *)tsName __deprecated;
- (nullable NSString *)tsNameAtIndex:(NSUInteger)index __deprecated;
@end


@protocol MCSHLSParserDelegate <NSObject>
- (void)parserParseDidFinish:(MCSHLSParser *)parser;
- (void)parser:(MCSHLSParser *)parser anErrorOccurred:(NSError *)error;
@end

NS_ASSUME_NONNULL_END
