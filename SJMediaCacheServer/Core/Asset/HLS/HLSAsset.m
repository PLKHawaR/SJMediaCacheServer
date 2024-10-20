//
//  HLSAsset.m
//  SJMediaCacheServer_Example
//
//  Created by 畅三江 on 2020/6/9.
//  Copyright © 2020 changsanjiang@gmail.com. All rights reserved.
//

#import "HLSAsset.h"
#import "MCSConfiguration.h"
#import "MCSURL.h"
#import "MCSUtils.h"
#import "MCSConsts.h"
#import "HLSAssetContentProvider.h"
#import "HLSAssetReader.h"
#import "MCSRootDirectory.h"
#import "MCSRequest.h"
#import "MCSAssetContent.h"
#import "NSFileManager+MCS.h"
#import "MCSMimeType.h"
#import "HLSAssetSegmentNode.h"
#import "MCSAssetManager.h"

static NSString *HLS_AES_KEY_MIME_TYPE = @"application/octet-stream";

@interface HLSAsset () {
    NSHashTable<id<MCSAssetObserver>> *mObservers;
    BOOL mStored;
    BOOL mPrepared;
    HLSAssetParser *_Nullable mParser;
    MCSConfiguration *mConfiguration;
    HLSAssetContentProvider *mProvider;
    id<MCSAssetContent> _Nullable mPlaylistContent;
    NSMutableDictionary<NSString *, id<MCSAssetContent>> * _Nullable mAESKeyContents; // { identifier: content }
    NSMutableDictionary<NSString *, id<HLSItem>> *_Nullable mSegmentURIItems; // { nodeIdentifier: item }
    HLSAssetSegmentNodeMap *mSegmentNodeMap; // ts
    
    HLSAsset *_Nullable mVariantStreamAsset;
    HLSAsset *_Nullable mAudioRenditionAsset;
    HLSAsset *_Nullable mVideoRenditionAsset;
    id<MCSAssetContent> _Nullable mSubtitlesContent;
    
    __weak HLSAsset *_Nullable mMasterAsset;
}

@property (nonatomic) NSInteger id; // saveable
@property (nonatomic, copy) NSString *name; // saveable
@property (nonatomic, weak, nullable) HLSAsset *root;
@end

@implementation HLSAsset
@synthesize id = _id;

+ (NSString *)sql_primaryKey {
    return @"id";
}

+ (NSArray<NSString *> *)sql_autoincrementlist {
    return @[@"id"];
}

+ (NSArray<NSString *> *)sql_blacklist {
    return @[@"readwriteCount", @"isStored", @"configuration", @"contents", @"parser", @"root"];
}

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    _name = name.copy;
    return self;
}

- (void)dealloc {
    [mObservers removeAllObjects];
}

- (void)prepare {
    @synchronized (self) {
        NSParameterAssert(self.name != nil);
        if ( mPrepared )
            return;
        mPrepared = YES;
        mConfiguration = MCSConfiguration.alloc.init;
        NSString *directory = [MCSRootDirectory assetPathForFilename:self.name];
        mProvider = [HLSAssetContentProvider.alloc initWithDirectory:directory];
        mSegmentNodeMap = [HLSAssetSegmentNodeMap.alloc init];

        // find proxy playlist file
        NSString *proxyPlaylistFilePath = [mProvider loadPlaylistFilePath];
        if ( proxyPlaylistFilePath != nil ) {
            NSError *error = nil;
            mParser = [HLSAssetParser.alloc initWithProxyPlaylist:[NSString stringWithContentsOfFile:proxyPlaylistFilePath encoding:NSUTF8StringEncoding error:&error]];
            if ( mParser != nil ) [self _onPlaylist:proxyPlaylistFilePath];
        }
    }
}

- (id<MCSConfiguration>)configuration {
    return mConfiguration;
}

- (NSString *)path {
    return [MCSRootDirectory assetPathForFilename:_name];
}

#pragma mark - VariantStream

- (nullable HLSAsset *)selectedVariantStreamAsset {
    return mVariantStreamAsset;
}

- (nullable HLSAsset *)selectedAudioRenditionAsset {
    return mAudioRenditionAsset;
}

- (nullable HLSAsset *)selectedVideoRenditionAsset {
    return mVideoRenditionAsset;
}

- (nullable HLSAsset *)masterAsset {
    return mMasterAsset;
}

//@interface HLSAsset (VariantStream)
//@property (nonatomic, strong, readonly, nullable) HLSAsset *selectedVariantStreamAsset;
//@property (nonatomic, strong, readonly, nullable) HLSAsset *selectedAudioRenditionAsset;
//@property (nonatomic, strong, readonly, nullable) HLSAsset *selectedVideoRenditionAsset;
///// variantStreamAsset.masterAsset;
///// selectedAudioRenditionAsset.masterAsset;
///// selectedVideoRenditionAsset.masterAsset;
//@property (nonatomic, weak, readonly, nullable) HLSAsset *masterAsset;
//
//@property (nonatomic, readonly) BOOL isVariantStreamAsset;
//@property (nonatomic, readonly) BOOL isAudioRenditionAsset;
//@property (nonatomic, readonly) BOOL isVideoRenditionAsset;
//@property (nonatomic, readonly) BOOL isMasterAsset;

#pragma mark - mark

#warning next ... identifier 与 extension 的添加问题

- (NSString *)generateAESKeyIdentifierWithOriginalURL:(NSURL *)originalURL {
    return [MCSURL.shared generateProxyIdentifierFromHLSOriginalURL:originalURL extension:HLS_EXTENSION_KEY];
}

- (NSString *)generateSubtitlesIdentifierWithOriginalURL:(NSURL *)originalURL {
    return [MCSURL.shared generateProxyIdentifierFromHLSOriginalURL:originalURL extension:HLS_EXTENSION_SUBTITLES];
}

- (NSString *)generateSegmentIdentifierWithOriginalURL:(NSURL *)originalURL {
    return [MCSURL.shared generateProxyIdentifierFromHLSOriginalURL:originalURL extension:HLS_EXTENSION_SEGMENT];
}

/// @param byteRange #EXT-X-BYTERANGE or { NSNotFound, NSNotFound }
- (NSString *)generateSegmentNodeIdentifierWithSegmentIdentifier:(NSString *)segmentIdentifier requestHeaderByteRange:(NSRange)byteRange {
    return byteRange.location == NSNotFound ? segmentIdentifier : [NSString stringWithFormat:@"%@_%lu_%lu", segmentIdentifier, byteRange.location, byteRange.length];
}

#pragma mark - mark

- (nullable HLSAssetParser *)parser {
    @synchronized (self) {
        return mParser;
    }
}

- (MCSAssetType)type {
    return MCSAssetTypeHLS;
}

- (nullable NSArray<id<HLSAssetSegment>> *)TsContents {
    return nil;
}

- (BOOL)isStored {
    @synchronized (self) {
        return mStored;
    }
}

- (NSUInteger)tsCount {
    @synchronized (self) {
        return mParser.segmentsCount;
    }
}

@synthesize root = _root;
- (void)setRoot:(nullable HLSAsset *)root {
    @synchronized (self) {
        _root = root;
    }
}

- (nullable HLSAsset *)root {
    @synchronized (self) {
        return _root;
    }
}


- (nullable id<MCSAssetReader>)readerWithRequest:(id<MCSRequest>)request networkTaskPriority:(float)networkTaskPriority readDataDecoder:(NSData *(^_Nullable)(NSURLRequest *request, NSUInteger offset, NSData *data))readDataDecoder delegate:(nullable id<MCSAssetReaderDelegate>)delegate {
    return [HLSAssetReader.alloc initWithAsset:self request:request networkTaskPriority:networkTaskPriority readDataDecoder:readDataDecoder delegate:delegate];
}

- (nullable id<MCSAssetContent>)getPlaylistContent {
    @synchronized (self) {
        return mPlaylistContent != nil ? [mPlaylistContent readwriteRetain] : nil;
    }
}

- (nullable id<MCSAssetContent>)createPlaylistContentWithOriginalURL:(NSURL *)originalURL currentURL:(NSURL *)currentURL playlist:(NSData *)rawData error:(out NSError **)errorPtr {
    @synchronized (self) {
        if ( mPlaylistContent == nil ) {
            NSError *error = nil;
            NSString *proxyPlaylist = [HLSAssetParser proxyPlaylistWithAsset:self.name originalURL:originalURL currentURL:currentURL playlist:rawData variantStreamSelectionHandler:_variantStreamSelectionHandler renditionSelectionHandler:_renditionSelectionHandler error:&error];
            if ( proxyPlaylist != nil ) {
                NSString *filePath = [mProvider writeContentsToPlaylist:proxyPlaylist error:&error];
                if ( filePath != nil ) {
                    mParser = [HLSAssetParser.alloc initWithProxyPlaylist:proxyPlaylist];
                    if ( mParser != nil ) [self _onPlaylist:filePath];
                }
            }
            if ( error != nil && errorPtr != NULL ) *errorPtr = error;
        }
        return mPlaylistContent != nil ? [mPlaylistContent readwriteRetain] : nil;
    }
}

- (nullable id<MCSAssetContent>)getAESKeyContentWithOriginalURL:(NSURL *)originalURL {
    @synchronized (self) {
        NSString *identifier = [self generateAESKeyIdentifierWithOriginalURL:originalURL];
        id<MCSAssetContent> _Nullable content = mAESKeyContents != nil ? mAESKeyContents[identifier] : nil;
        return content != nil ? [content readwriteRetain] : nil;
    }
}

- (nullable id<MCSAssetContent>)createAESKeyContentWithOriginalURL:(NSURL *)originalURL data:(NSData *)data error:(out NSError **)errorPtr {
    @synchronized (self) {
        NSString *identifier = [self generateAESKeyIdentifierWithOriginalURL:originalURL];
        id<MCSAssetContent> _Nullable content = mAESKeyContents != nil ? mAESKeyContents[identifier] : nil;
        NSError *error = nil;
        if ( content == nil ) {
            NSString *filePath = [mProvider getAESKeyFilePath:identifier];
            if ( [data writeToFile:filePath options:NSDataWritingAtomic error:&error] ) {
                content = [MCSAssetContent.alloc initWithMimeType:HLS_AES_KEY_MIME_TYPE filePath:filePath startPositionInAsset:0 length:data.length];
                if ( mAESKeyContents == nil ) mAESKeyContents = NSMutableDictionary.dictionary;
                mAESKeyContents[identifier] = content;
            }
            if ( error != nil && errorPtr != NULL ) *errorPtr = error;
        }
        return content != nil ? [content readwriteRetain] : nil;
    }
}

- (nullable id<MCSAssetContent>)getSubtitlesContentWithOriginalURL:(NSURL *)originalURL {
    @synchronized (self) {
// subtitles only one can be selected;
//        NSString *identifier = [self generateSubtitlesIdentifierWithOriginalURL:originalURL];
//        id<MCSAssetContent> _Nullable content = mSubtitlesContents != nil ? mSubtitlesContents[identifier] : nil;
//        return content != nil ? [content readwriteRetain] : nil;
        return mSubtitlesContent != nil ? [mSubtitlesContent readwriteRetain] : nil;
    }
}

- (nullable id<MCSAssetContent>)createSubtitlesContentWithOriginalURL:(NSURL *)originalURL data:(NSData *)data error:(out NSError **)errorPtr {
    @synchronized (self) {
        if ( mSubtitlesContent == nil ) {
            NSString *identifier = [self generateSubtitlesIdentifierWithOriginalURL:originalURL];
            NSError *error = nil;
            NSString *filePath = [mProvider getSubtitlesFilePath:identifier];
            if ( [data writeToFile:filePath options:NSDataWritingAtomic error:&error] ) {
                mSubtitlesContent = [MCSAssetContent.alloc initWithMimeType:MCSMimeType(originalURL.path.pathExtension) filePath:filePath startPositionInAsset:0 length:data.length];
            }
            if ( error != nil && errorPtr != NULL ) *errorPtr = error;
        }
        return mSubtitlesContent != nil ? [mSubtitlesContent readwriteRetain] : nil;
    }
}


/// 将返回如下两种content, 如果未满足条件, 则返回nil
///
///     - 如果ts已缓存完毕, 则返回完整的content
///
///     - 如果ts被缓存了一部分(可能存在多个), 则将返回长度最长的并且readwrite为0的content
///
/// 该操作将会对 content 进行一次 readwriteRetain, 请在不需要时, 调用一次 readwriteRelease.
- (id<HLSAssetSegment>)getSegmentContentWithOriginalURL:(NSURL *)originalURL byteRange:(NSRange)byteRange {
    @synchronized (self) {
        NSString *segmentIdentifier = [self generateSegmentIdentifierWithOriginalURL:originalURL];
        NSString *nodeIdentifier = [self generateSegmentNodeIdentifierWithSegmentIdentifier:segmentIdentifier requestHeaderByteRange:byteRange];
        HLSAssetSegmentNode *node = [mSegmentNodeMap nodeForIdentifier:nodeIdentifier];
        if ( node != nil ) {
            id<HLSAssetSegment> segment = node.fullOrIdleContent;
            return segment != nil ? [segment readwriteRetain] : nil;
        }
        return nil;
    }
}

- (nullable id<MCSAssetContent>)createContentReadwriteWithDataType:(MCSDataType)dataType response:(id<MCSDownloadResponse>)response error:(NSError *__autoreleasing  _Nullable * _Nullable)errorPtr {
    switch ( dataType ) {
        case MCSDataTypeHLSMask:
        case MCSDataTypeHLSPlaylist:
        case MCSDataTypeHLSAESKey:
        case MCSDataTypeHLSSubtitles:
        case MCSDataTypeHLS:
        case MCSDataTypeFILEMask:
        case MCSDataTypeFILE: return nil; /* return nil; */
        case MCSDataTypeHLSSegment: { // only segment
            @synchronized (self) {
                id<HLSAssetSegment>content = nil;
                NSString *segmentIdentifier = [self generateSegmentIdentifierWithOriginalURL:response.originalRequest.URL];
                NSRange byteRange = MCSRequestRange(MCSRequestGetContentRange(response.originalRequest.allHTTPHeaderFields));
                NSString *nodeIdentifier = [self generateSegmentNodeIdentifierWithSegmentIdentifier:segmentIdentifier requestHeaderByteRange:byteRange];
                id<HLSItem> item = mSegmentURIItems[nodeIdentifier];
                NSURL *originalURL = [MCSURL.shared restoreURLFromHLSProxyURI:item.URI];
                NSString *mimeType = MCSMimeType(originalURL.path.pathExtension);
                BOOL isSubrange = byteRange.length != NSNotFound;
                content = !isSubrange ? [mProvider createSegmentWithIdentifier:segmentIdentifier mimeType:mimeType totalLength:response.totalLength error:errorPtr] :
                                        [mProvider createSegmentWithIdentifier:segmentIdentifier mimeType:mimeType totalLength:response.totalLength byteRange:byteRange error:errorPtr];
                if ( content != nil ) {
                    [mSegmentNodeMap attachContentToNode:content identifier:nodeIdentifier];
                    return [content readwriteRetain];
                }
                return nil;
            }
        }
    }
}

- (void)clear {
    @synchronized (self) {
        for ( id<MCSAssetObserver> observer in MCSAllHashTableObjects(mObservers) ) {
            if ( [observer respondsToSelector:@selector(assetWillClear:)] ) {
                [observer assetWillClear:self];
            }
        }
        mStored = NO;
        mParser = nil;
        mPlaylistContent = nil;
        mAESKeyContents = nil;
        mSegmentURIItems = nil;
        [mSegmentNodeMap removeAllNodes];
        if ( mVariantStreamAsset != nil ) {
            [mVariantStreamAsset clear];
            mVariantStreamAsset = nil;
        }
        if ( mAudioRenditionAsset != nil ) {
            [mAudioRenditionAsset clear];
            mAudioRenditionAsset = nil;
        }
        if ( mVideoRenditionAsset != nil ) {
            [mVideoRenditionAsset clear];
            mVideoRenditionAsset = nil;
        }
        mSubtitlesContent = nil;
        [mProvider clear];
        
        for ( id<MCSAssetObserver> observer in MCSAllHashTableObjects(mObservers) ) {
            if ( [observer respondsToSelector:@selector(assetDidClear:)] ) {
                [observer assetDidClear:self];
            }
        }
    }
}

- (void)registerObserver:(id<MCSAssetObserver>)observer {
    if ( observer != nil ) {
        @synchronized (self) {
            if ( mObservers == nil ) {
                mObservers = NSHashTable.weakObjectsHashTable;
            }
            [mObservers addObject:observer];
        }
    }
}

- (void)removeObserver:(id<MCSAssetObserver>)observer {
    @synchronized (self) {
        [mObservers removeObject:observer];
    }
}

#pragma mark - readwrite

- (instancetype)readwriteRetain {
    [super readwriteRetain];
    if ( mMasterAsset != nil ) [mMasterAsset readwriteRetain];
    return self;
}

- (void)readwriteRelease {
    [super readwriteRelease];
    if ( mMasterAsset != nil ) [mMasterAsset readwriteRelease];
}

- (void)readwriteCountDidChange:(NSInteger)count {
    if ( count == 0 ) {
        @synchronized (self) {
            [self _trimExcessSegmentContents];
        }
    }
}

#pragma mark - unlocked

- (void)_onPlaylist:(NSString *)proxyPlaylistFilePath {
    NSParameterAssert(mParser != nil);
    // playlist content
    mPlaylistContent = [MCSAssetContent.alloc initWithFilePath:proxyPlaylistFilePath startPositionInAsset:0 length:[NSFileManager.defaultManager mcs_fileSizeAtPath:proxyPlaylistFilePath]];
    // find existing aes contents
    [mParser.keys enumerateObjectsUsingBlock:^(id<HLSKey>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSURL *originalURL = [MCSURL.shared restoreURLFromHLSProxyURI:obj.URI];
        NSString *identifier = [self generateAESKeyIdentifierWithOriginalURL:originalURL];
        NSString *filePath = [mProvider getAESKeyFilePath:identifier];
        // playlist 与 aes key 都属于小文件, 目录中只要存在对应文件就说明已下载完毕;
        if ( [NSFileManager.defaultManager fileExistsAtPath:filePath] ) {
            if ( mAESKeyContents == nil ) mAESKeyContents = NSMutableDictionary.dictionary;
            mAESKeyContents[identifier] = [MCSAssetContent.alloc initWithMimeType:HLS_AES_KEY_MIME_TYPE filePath:filePath startPositionInAsset:0 length:[NSFileManager.defaultManager mcs_fileSizeAtPath:filePath]];
        }
    }];
    
    if ( mParser.segmentsCount != 0 ) {
        mSegmentURIItems = NSMutableDictionary.dictionary;
        [mParser.segments enumerateObjectsUsingBlock:^(id<HLSSegment>  _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
            NSURL *originalURL = [MCSURL.shared restoreURLFromHLSProxyURI:item.URI];
            NSString *segmentIdentifier = [self generateSegmentIdentifierWithOriginalURL:originalURL];
            NSRange byteRange = item.byteRange;
            NSString *nodeIdentifier = [self generateSegmentNodeIdentifierWithSegmentIdentifier:segmentIdentifier requestHeaderByteRange:byteRange];
            mSegmentURIItems[nodeIdentifier] = item;
        }];
        
        // find existing segment contents
        NSArray<NSString *> *existingFilenames = [mProvider loadSegmentFilenames];
        if ( existingFilenames.count != 0 ) {
            [existingFilenames enumerateObjectsUsingBlock:^(NSString * _Nonnull filename, NSUInteger idx, BOOL * _Nonnull stop) {
                NSRange byteRange = { NSNotFound, NSNotFound };
                NSString *segmentIdentifier = [mProvider getSegmentIdentifierByFilename:filename byteRange:&byteRange];
                NSString *nodeIdentifier = [self generateSegmentNodeIdentifierWithSegmentIdentifier:segmentIdentifier requestHeaderByteRange:byteRange];
                id<HLSItem> item = mSegmentURIItems[nodeIdentifier];
                NSURL *originalURL = [MCSURL.shared restoreURLFromHLSProxyURI:item.URI];
                NSString *mimeType = MCSMimeType(originalURL.path.pathExtension);
                id<HLSAssetSegment> content = [mProvider getSegmentByFilename:filename mimeType:mimeType];
                [mSegmentNodeMap attachContentToNode:content identifier:nodeIdentifier];
            }];
        }
    }
    else if ( mParser.variantStream != nil ) {
        //    __weak HLSAsset *_Nullable mVariantStreamAsset;
        //    __weak HLSAsset *_Nullable mAudioRenditionAsset;
        //    __weak HLSAsset *_Nullable mVideoRenditionAsset;
        //    id<MCSAssetContent> _Nullable mSubtitlesContent;
        
        id<HLSVariantStream> selectedVariantStream = mParser.variantStream;
        id<HLSRendition> _Nullable selectedAudioRendition = mParser.audioRendition;
        id<HLSRendition> _Nullable selectedVideoRendition = mParser.videoRendition;
        id<HLSRendition> _Nullable selectedSubtitlesRendition = mParser.subtitlesRendition;
        mVariantStreamAsset = [MCSAssetManager.shared assetWithURL:[MCSURL.shared restoreURLFromHLSProxyURI:selectedVariantStream.URI]];
        mVariantStreamAsset->mMasterAsset = self;
        [mVariantStreamAsset prepare];
        
        if ( selectedAudioRendition != nil ) {
            mAudioRenditionAsset = [MCSAssetManager.shared assetWithURL:[MCSURL.shared restoreURLFromHLSProxyURI:selectedAudioRendition.URI]];
            mAudioRenditionAsset->mMasterAsset = self;
            [mAudioRenditionAsset prepare];
        }
        
        if ( selectedVideoRendition != nil ) {
            mVideoRenditionAsset = [MCSAssetManager.shared assetWithURL:[MCSURL.shared restoreURLFromHLSProxyURI:selectedVideoRendition.URI]];
            mVideoRenditionAsset->mMasterAsset = self;
            [mVideoRenditionAsset prepare];
        }
        
        if ( selectedSubtitlesRendition != nil ) {
            NSURL *originalURL = [MCSURL.shared restoreURLFromHLSProxyURI:selectedSubtitlesRendition.URI];
            NSString *identifier = [self generateSubtitlesIdentifierWithOriginalURL:originalURL];
            NSString *filePath = [mProvider getSubtitlesFilePath:identifier];
            // 同样都是小文件, 目录中只要存在对应文件就说明已下载完毕;
            if ( [NSFileManager.defaultManager fileExistsAtPath:filePath] ) {
                mSubtitlesContent = [MCSAssetContent.alloc initWithMimeType:MCSMimeType(originalURL.path.pathExtension) filePath:filePath startPositionInAsset:0 length:[NSFileManager.defaultManager mcs_fileSizeAtPath:filePath]];
            }
        }
    }
        
    // trim
    [self _trimExcessSegmentContents];
}

/// unlocked
- (void)_trimExcessSegmentContents {
    if ( mStored || mParser == nil || self.readwriteCount != 0 ) return;
    
    if      ( mParser.segmentsCount != 0 ) {
        __block BOOL isAllSegmentsCached = mParser.segmentsCount == mSegmentNodeMap.count;
        [mSegmentNodeMap enumerateNodesUsingBlock:^(HLSAssetSegmentNode * _Nonnull node, BOOL * _Nonnull stop) {
            [self _trimExcessContentsForNode:node];
            if ( isAllSegmentsCached && node.fullContent == nil ) isAllSegmentsCached = NO;
        }];
        if ( isAllSegmentsCached ) {
            mStored = YES;
        }
    }
    else if ( mParser.variantStream != nil ) {
//        /// Represents the selected variant stream. If there are variant streams in the m3u8, only one can be selected.
//        /// The selection is made through HLSVariantStreamSelectionHandler.
//        @property (nonatomic, strong, readonly, nullable) id<HLSVariantStream> variantStream;
//        /// Represents the selected audio rendition. If there are audio renditions in the m3u8, only one can be selected.
//        /// The selection is made through HLSRenditionSelectionHandler.
//        @property (nonatomic, strong, readonly, nullable) id<HLSRendition> audioRendition;
//        /// Represents the selected video rendition. If there are video renditions in the m3u8, only one can be selected.
//        /// The selection is made through HLSRenditionSelectionHandler.
//        @property (nonatomic, strong, readonly, nullable) id<HLSRendition> videoRendition;
//        /// Represents the selected subtitles rendition. If there are subtitles renditions in the m3u8, only one can be selected.
//        /// The selection is made through HLSRenditionSelectionHandler.
//        @property (nonatomic, strong, readonly, nullable) id<HLSRendition> subtitlesRendition;
        BOOL isVariantStreamStored = mVariantStreamAsset.isStored;
        BOOL isAudioRenditionStored = mAudioRenditionAsset == nil || mAudioRenditionAsset.isStored;
        BOOL isVideoRenditionStored = mVideoRenditionAsset == nil || mVideoRenditionAsset.isStored;
        BOOL isSubtitlesRenditionStored = mParser.subtitlesRendition == nil || mSubtitlesContent != nil;
        mStored = isVariantStreamStored && isAudioRenditionStored && isVideoRenditionStored && isSubtitlesRenditionStored;
    }
    else {
        mStored = YES;
    }
    
    if ( mStored ) [self _notifyDidStore];
}

/// unlocked
- (void)_trimExcessContentsForNode:(HLSAssetSegmentNode *)node {
    if ( node.numberOfContents > 1 ) {
        // 同一段segment可能存在多个文件
        // 删除多余的无用的content
        id<HLSAssetSegment> fullSegment = node.fullContent;
        if ( fullSegment != nil ) {        
            [node trimExcessContentsWithTest:^BOOL(id<HLSAssetSegment>  _Nonnull content, BOOL * _Nonnull stop) {
                if ( content != fullSegment && content.readwriteCount == 0 ) {
                    [mProvider removeSegment:content];
                    return YES;
                }
                return NO;
            }];
        }
    }
}

- (void)_notifyDidStore {
    for ( id<MCSAssetObserver> observer in MCSAllHashTableObjects(mObservers) ) {
        if ( [observer respondsToSelector:@selector(assetDidStore:)] ) {
            [observer assetDidStore:self];
        }
    }
}
@end
