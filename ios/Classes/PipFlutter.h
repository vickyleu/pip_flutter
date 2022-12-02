// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>


#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import "PipFlutterTimeUtils.h"
#import "PipFlutterView.h"
#import "PipFlutterEzDrmAssetsLoaderDelegate.h"


NS_ASSUME_NONNULL_BEGIN

@class PipCacheManager;

@interface PipFlutter : NSObject <FlutterPlatformView, FlutterStreamHandler, AVPictureInPictureControllerDelegate>
@property(readonly, nonatomic) AVPlayer* player;
@property(readonly, nonatomic) PipFlutterEzDrmAssetsLoaderDelegate* loaderDelegate;
@property(nonatomic) FlutterEventChannel* eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(nonatomic) CGAffineTransform preferredTransform;
@property(nonatomic, readonly) bool disposed;
@property(nonatomic, readonly) bool isPlaying;
@property(nonatomic, readonly) bool isPiping;
@property(nonatomic) bool isLooping;
@property(nonatomic, readonly) bool isInitialized;
@property(nonatomic, readonly) NSString* key;
@property(nonatomic, readonly) int failedCount;
@property(nonatomic) AVPlayerLayer* _playerLayer;
@property(nonatomic) bool _pictureInPicture;
@property(nonatomic) bool _observersAdded;
@property(nonatomic) int stalledCount;
@property(nonatomic) bool isStalledCheckStarted;
@property(nonatomic) float playerRate;
@property(nonatomic) int overriddenDuration;
@property(nonatomic) AVPlayerTimeControlStatus lastAvPlayerTimeControlStatus;
- (void)play;
- (void)pause;
- (void)setIsLooping:(bool)isLooping;
- (void)updatePlayingState;
- (int64_t) duration;
- (int64_t) position;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setMixWithOthers:(bool)mixWithOthers;
- (void)seekTo:(int)location;
- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(nullable NSString*  )certificateUrl withLicenseUrl:(nullable NSString*  )licenseUrl cacheKey:(nullable NSString*  )cacheKey cacheManager:(PipCacheManager*)cacheManager overriddenDuration:(int) overriddenDuration;
- (void)setDataSourceURL:(NSURL*)url withKey:(NSString*)key withCertificateUrl:(nullable NSString* )certificateUrl withLicenseUrl:(nullable NSString* )licenseUrl withHeaders:(nullable NSDictionary* )headers withCache:(BOOL)useCache cacheKey:(nullable NSString* )cacheKey cacheManager:(PipCacheManager*)cacheManager overriddenDuration:(int) overriddenDuration videoExtension: (nullable NSString*) videoExtension;
- (void)setVolume:(double)volume;
- (void)setSpeed:(double)speed result:(FlutterResult)result;
- (void) setAudioTrack:(NSString*) name index:(int) index;
- (void)setTrackParameters:(int) width: (int) height: (int)bitrate;
- (void) enablePictureInPicture: (CGRect) frame;
- (void) playerLayerSetup: (CGRect) frame;

- (void)setPictureInPicture:(BOOL)pictureInPicture;
- (void)disablePictureInPicture;
- (int64_t)absolutePosition;
- (int64_t) FLTCMTimeToMillis:(CMTime) time;

- (void)clear;
- (void)disposeSansEventChannel;
- (void)dispose;

- (void)setOnBackgroundCountingListener:(nullable void (^)(void) )pFunction;
@end

NS_ASSUME_NONNULL_END
