//
//  MCSAssetExporterDefines.h
//  Pods
//
//  Created by BD on 2021/3/20.
//

#ifndef MCSAssetExporterDefines_h
#define MCSAssetExporterDefines_h

#import <Foundation/Foundation.h>
@protocol MCSAssetExporter, MCSAssetExportObserver;

typedef NS_ENUM(NSUInteger, MCSAssetExportStatus) {
    MCSAssetExportStatusUnknown,
    MCSAssetExportStatusWaiting,
    MCSAssetExportStatusExporting,
    MCSAssetExportStatusFinished,
    MCSAssetExportStatusFailed,
    MCSAssetExportStatusSuspended,
    MCSAssetExportStatusCancelled,
};

NS_ASSUME_NONNULL_BEGIN
@protocol MCSAssetExporter <NSObject>
@property (nonatomic, strong, readonly) NSURL *URL;
@property (nonatomic, readonly) MCSAssetExportStatus status;
@property (nonatomic, readonly) float progress;
- (void)synchronize; // 同步进度(由于存在边播边缓存, 导出进度可能会发生变动)
- (void)resume;      // 恢复
- (void)suspend;     // 暂停, 缓存文件不会被删除
- (void)cancel;      // 取消, 缓存可能会被资源管理器删除
@end

@protocol MCSAssetExportObserver <NSObject>
@optional
- (void)exporter:(id<MCSAssetExporter>)exporter statusDidChange:(MCSAssetExportStatus)status;
- (void)exporter:(id<MCSAssetExporter>)exporter progressDidChange:(float)progress;
- (void)exporterManagerDidRemoveAssetWithURL:(NSURL *)URL;
- (void)exporterManagerDidRemoveAllAssets;
@end


@protocol MCSAssetExporterManager <NSObject>
- (void)registerObserver:(id<MCSAssetExportObserver>)observer;
- (void)removeObserver:(id<MCSAssetExportObserver>)observer;

@property (nonatomic) NSInteger maxConcurrentExportCount;

@property (nonatomic, strong, readonly, nullable) NSArray<id<MCSAssetExporter>> *allExporters;
 
- (id<MCSAssetExporter>)exportAssetWithURL:(NSURL *)URL;
- (void)removeAssetWithURL:(NSURL *)URL;
- (void)removeAllAssets;
 
- (MCSAssetExportStatus)statusWithURL:(NSURL *)URL;
- (float)progressWithURL:(NSURL *)URL;
- (nullable NSURL *)playbackURLForExportedAssetWithURL:(NSURL *)URL;
 
- (void)synchronizeForAssetWithURL:(NSURL *)URL;
- (void)synchronize;
@end
NS_ASSUME_NONNULL_END
#endif /* MCSAssetExporterDefines_h */