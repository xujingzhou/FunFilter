//
//  ExportEffects
//  TailorableFilter
//
//  Created by Johnny Xu(徐景周) on 5/30/15.
//  Copyright (c) 2015 Future Studio. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "ExportEffects.h"
#import "AVAsset+help.h"

#define DefaultOutputVideoName @"outputMovie.mp4"
#define DefaultOutputAudioName @"outputAudio.caf"

@interface ExportEffects ()
{
}

@property (strong, nonatomic) NSTimer *timerEffect;
@property (strong, nonatomic) AVAssetExportSession *exportSession;

@property (strong, nonatomic) GPUImageMovie *movieFile;
@property (strong, nonatomic) GPUImageOutput<GPUImageInput> *filter;
@property (strong, nonatomic) GPUImageMovieWriter *movieWriter;

@property (strong, nonatomic) NSTimer *timerFilter;
@property (retain, nonatomic) NSMutableDictionary *themesDic;

@end

@implementation ExportEffects
{

}

+ (ExportEffects *)sharedInstance
{
    static ExportEffects *sharedInstance = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedInstance = [[ExportEffects alloc] init];
    });
    
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    
    if (self)
    {
        _timerEffect = nil;
        _exportSession = nil;
        
        _filenameBlock = nil;
        
        _timerFilter = nil;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_exportSession)
    {
        _exportSession = nil;
    }
    
    if (_timerEffect)
    {
        [_timerEffect invalidate];
        _timerEffect = nil;
    }
    
    if (_movieFile)
    {
        _movieFile = nil;
    }
    
    if (_movieWriter)
    {
        _movieWriter = nil;
    }
    
    if (_exportSession)
    {
        _exportSession = nil;
    }
    
    if (_timerFilter)
    {
        [_timerFilter invalidate];
        _timerFilter = nil;
    }
}

#pragma mark Utility methods
- (NSString*)getOutputFilePath
{
    NSString* mp4OutputFile = [NSTemporaryDirectory() stringByAppendingPathComponent:DefaultOutputVideoName];
    return mp4OutputFile;
}

- (NSString*)getTempOutputFilePath
{
    NSString *path = NSTemporaryDirectory();
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    formatter.dateFormat = @"yyyyMMddHHmmssSSS";
    NSString *nowTimeStr = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:0]];
    
    NSString *fileName = [[path stringByAppendingPathComponent:nowTimeStr] stringByAppendingString:@".mov"];
    return fileName;
}

#pragma mark - writeExportedVideoToAssetsLibrary
- (void)writeExportedVideoToAssetsLibrary:(NSString *)outputPath
{
    __unsafe_unretained typeof(self) weakSelf = self;
    NSURL *exportURL = [NSURL fileURLWithPath:outputPath];
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:exportURL])
    {
        [library writeVideoAtPathToSavedPhotosAlbum:exportURL completionBlock:^(NSURL *assetURL, NSError *error)
         {
             NSString *message;
             if (!error)
             {
                 message = GBLocalizedString(@"MsgSuccess");
             }
             else
             {
                 message = [error description];
             }
             
             NSLog(@"%@", message);
             
             // Output path
             self.filenameBlock = ^(void) {
                 return outputPath;
             };
             
             if (weakSelf.finishVideoBlock)
             {
                 weakSelf.finishVideoBlock(YES, message);
             }
         }];
    }
    else
    {
        NSString *message = GBLocalizedString(@"MsgFailed");;
        NSLog(@"%@", message);
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (_finishVideoBlock)
        {
            _finishVideoBlock(NO, message);
        }
    }
    
    library = nil;
}

#pragma mark - GPUImage
- (void) pause
{
    if (_movieFile.progress < 1.0)
    {
        [_movieWriter cancelRecording];
    }
    else if (_exportSession.progress < 1.0)
    {
        [_exportSession cancelExport];
    }
}

- (void)initializeVideoFilter:(NSURL*)inputMovieURL fromSystemCamera:(BOOL)fromSystemCamera
{
    // 1.
    _movieFile = [[GPUImageMovie alloc] initWithURL:inputMovieURL];
    _movieFile.runBenchmark = NO;
    _movieFile.playAtActualSpeed = NO;
    
    // 2. Add filter effect
    _filter = nil;
    NSUInteger themesCount = [[[VideoThemesData sharedInstance] getThemeData] count];
    if (self.themeCurrentType != kThemeNone && themesCount >= self.themeCurrentType)
    {
        GPUImageOutput<GPUImageInput> *filterCurrent = [[[VideoThemesData sharedInstance] getThemeFilter:fromSystemCamera] objectForKey:[NSNumber numberWithInt:self.themeCurrentType]];
        _filter = filterCurrent;
    }
    
    // 3.
    if ((NSNull*)_filter != [NSNull null] && _filter != nil)
    {
        [_movieFile addTarget:_filter];
    }
}

- (void)buildVideoFilter:(NSString*)videoFilePath fromSystemCamera:(BOOL)fromSystemCamera finishBlock:(GenericCallback)finishBlock
{
    if (self.themeCurrentType == kThemeNone)
    {
        NSLog(@"Theme is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (finishBlock)
        {
            finishBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        return;
    }
    
//    if (isStringEmpty(videoFilePath))
//    {
//        NSLog(@"videoFilePath is empty!");
//        
//        // Output path
//        self.filenameBlock = ^(void) {
//            return @"";
//        };
//        
//        if (finishBlock)
//        {
//            finishBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
//        }
//        return;
//    }
    
    self.themesDic = [[VideoThemesData sharedInstance] getThemeData];
    
    // 2.
    NSURL *inputVideoURL = getFileURL(videoFilePath);
    [self initializeVideoFilter:inputVideoURL fromSystemCamera:fromSystemCamera];
    
    // 3. Movie output temp file
    NSString *pathToTempMov = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tempMovie.mov"];
    unlink([pathToTempMov UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    NSURL *outputTempMovieURL = [NSURL fileURLWithPath:pathToTempMov];
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputVideoURL options:nil];
    NSArray *assetVideoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (assetVideoTracks.count <= 0)
    {
        NSLog(@"Video track is empty!");
        return;
    }
    AVAssetTrack *videoAssetTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    
    // If this if from system camera, it will rotate 90c, and swap width and height
    CGSize sizeVideo = CGSizeMake(videoAssetTrack.naturalSize.width, videoAssetTrack.naturalSize.height);
    if (fromSystemCamera)
    {
        sizeVideo = CGSizeMake(videoAssetTrack.naturalSize.height, videoAssetTrack.naturalSize.width);
    }
    _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:outputTempMovieURL size:sizeVideo];
    
    if ((NSNull*)_filter != [NSNull null] && _filter != nil)
    {
        [_filter addTarget:_movieWriter];
    }
    else
    {
        [_movieFile addTarget:_movieWriter];
    }
    
    // 4. Configure this for video from the movie file, where we want to preserve all video frames and audio samples
    _movieWriter.shouldPassthroughAudio = YES;
    _movieFile.audioEncodingTarget = _movieWriter;
    [_movieFile enableSynchronizedEncodingUsingMovieWriter:_movieWriter];
    
    // 5.
    [_movieWriter startRecording];
    [_movieFile startProcessing];
    
    // 6. Progress monitor
    _timerFilter = [NSTimer scheduledTimerWithTimeInterval:0.3f
                                                    target:self
                                                  selector:@selector(retrievingFilterProgress)
                                                  userInfo:nil
                                                   repeats:YES];
    
    __weak typeof(self) weakSelf = self;
    // 7. Filter finished
    [weakSelf.movieWriter setCompletionBlock:^{
        
        if ((NSNull*)_filter != [NSNull null] && _filter != nil)
        {
            [_filter removeTarget:weakSelf.movieWriter];
        }
        else
        {
            [_movieFile removeTarget:weakSelf.movieWriter];
        }
        
        [_movieWriter finishRecordingWithCompletionHandler:^{
            
            // Closer timer
            [_timerFilter invalidate];
            _timerFilter = nil;
            
            if (finishBlock)
            {
                finishBlock(YES, pathToTempMov);
            }
        }];
        
    }];
    
    // 8. Filter failed
    [weakSelf.movieWriter  setFailureBlock: ^(NSError* error){
        
        if ((NSNull*)_filter != [NSNull null] && _filter != nil)
        {
            [_filter removeTarget:weakSelf.movieWriter];
        }
        else
        {
            [_movieFile removeTarget:weakSelf.movieWriter];
        }
        
//        [_movieWriter finishRecordingWithCompletionHandler:^{
            
            // Closer timer
            [_timerFilter invalidate];
            _timerFilter = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                self.filenameBlock = ^(void) {
                    return @"";
                };
                
                if (finishBlock)
                {
                    finishBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
                }
            });
            
            NSLog(@"Add filter effect failed! - %@", error.description);
            return;
//        }];
        
    }];
}

#pragma mark - Export Video
- (void)addEffectToVideo:(NSString *)videoFilePath withAudioFilePath:(NSString *)audioFilePath
{
    if (isStringEmpty(videoFilePath))
    {
        NSLog(@"videoFilePath is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }
    
    NSURL *videoURL = getFileURL(videoFilePath);
    AVAsset *videoAsset = [AVAsset assetWithURL:videoURL];
    if (videoAsset)
    {
        UIInterfaceOrientation videoOrientation = orientationForTrack(videoAsset);
        NSLog(@"videoOrientation: %ld", (long)videoOrientation);
        if (videoOrientation == UIInterfaceOrientationPortrait)
        {
            // Right rotation 90 degree
            [self setShouldRightRotate90:YES withTrackID:TrackIDCustom];
        }
        else
        {
            [self setShouldRightRotate90:NO withTrackID:TrackIDCustom];
        }
    }
    else
    {
        NSLog(@"videoAsset is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }

    // Filter
    [self buildVideoFilter:videoFilePath fromSystemCamera:[self shouldRightRotate90ByTrackID:TrackIDCustom] finishBlock:^(BOOL success, id result) {
        
        if (success)
        {
            NSLog(@"buildVideoFilter success.");
            
            // Combine 2 video to export
            NSString *filterVideoFile = result;
            NSMutableArray *videoFileArray = [NSMutableArray arrayWithCapacity:2];
            [videoFileArray addObject:videoFilePath];
            [videoFileArray addObject:filterVideoFile];
            
            [self exportVideo:videoFileArray withAudioFilePath:nil];
        }
        else
        {
            self.filenameBlock = ^(void) {
                return @"";
            };
            
            if (self.finishVideoBlock)
            {
                self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
            }
        }
    }];
}

#pragma mark - addAudioMixToComposition
- (void)addAudioMixToComposition:(AVMutableComposition *)composition withAudioMix:(AVMutableAudioMix *)audioMix withAsset:(AVURLAsset*)commentary
{
    NSInteger i;
    NSArray *tracksToDuck = [composition tracksWithMediaType:AVMediaTypeAudio];
    
    // 1. Clip commentary duration to composition duration.
    CMTimeRange commentaryTimeRange = CMTimeRangeMake(kCMTimeZero, commentary.duration);
    if (CMTIME_COMPARE_INLINE(CMTimeRangeGetEnd(commentaryTimeRange), >, [composition duration]))
        commentaryTimeRange.duration = CMTimeSubtract([composition duration], commentaryTimeRange.start);
    
    // 2. Add the commentary track.
    AVMutableCompositionTrack *compositionCommentaryTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:TrackIDCustom];
    AVAssetTrack * commentaryTrack = [[commentary tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    [compositionCommentaryTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, commentaryTimeRange.duration) ofTrack:commentaryTrack atTime:commentaryTimeRange.start error:nil];
    
    // 3. Fade in for bgMusic
    CMTime fadeTime = CMTimeMake(1, 1);
    CMTimeRange startRange = CMTimeRangeMake(kCMTimeZero, fadeTime);
    NSMutableArray *trackMixArray = [NSMutableArray array];
    AVMutableAudioMixInputParameters *trackMixComentray = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:commentaryTrack];
    [trackMixComentray setVolumeRampFromStartVolume:0.0f toEndVolume:0.5f timeRange:startRange];
    [trackMixArray addObject:trackMixComentray];
    
    // 4. Fade in & Fade out for original voices
    for (i = 0; i < [tracksToDuck count]; i++)
    {
        CMTimeRange timeRange = [[tracksToDuck objectAtIndex:i] timeRange];
        if (CMTIME_COMPARE_INLINE(CMTimeRangeGetEnd(timeRange), ==, kCMTimeInvalid))
        {
            break;
        }
        
        CMTime halfSecond = CMTimeMake(1, 2);
        CMTime startTime = CMTimeSubtract(timeRange.start, halfSecond);
        CMTime endRangeStartTime = CMTimeAdd(timeRange.start, timeRange.duration);
        CMTimeRange endRange = CMTimeRangeMake(endRangeStartTime, halfSecond);
        if (startTime.value < 0)
        {
            startTime.value = 0;
        }
        
        [trackMixComentray setVolumeRampFromStartVolume:0.5f toEndVolume:0.2f timeRange:CMTimeRangeMake(startTime, halfSecond)];
        [trackMixComentray setVolumeRampFromStartVolume:0.2f toEndVolume:0.5f timeRange:endRange];
        [trackMixArray addObject:trackMixComentray];
    }
    
    audioMix.inputParameters = trackMixArray;
}

- (void)addAsset:(AVAsset *)asset toComposition:(AVMutableComposition *)composition withTrackID:(CMPersistentTrackID)trackID withRecordAudio:(BOOL)recordAudio withTimeRange:(CMTimeRange)timeRange
{
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:trackID];
    AVAssetTrack *assetVideoTrack = asset.firstVideoTrack;
    [videoTrack insertTimeRange:timeRange ofTrack:assetVideoTrack atTime:kCMTimeZero error:nil];
    [videoTrack setPreferredTransform:assetVideoTrack.preferredTransform];
    
    if (recordAudio)
    {
        AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:trackID];
        if ([[asset tracksWithMediaType:AVMediaTypeAudio] count] > 0)
        {
            AVAssetTrack *assetAudioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
            [audioTrack insertTimeRange:timeRange ofTrack:assetAudioTrack atTime:kCMTimeZero error:nil];
        }
        else
        {
            NSLog(@"Reminder: video hasn't audio!");
        }
    }
}

- (void)exportVideo:(NSArray *)videoFilePathArray withAudioFilePath:(NSString *)audioFilePath
{
    if (!videoFilePathArray || [videoFilePathArray count] < 1)
    {
        NSLog(@"videoFilePath is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }
    
    CGFloat duration = 0;
    CMTimeRange bgVideoTimeRange = kCMTimeRangeZero;
    NSMutableArray *assetArray = [[NSMutableArray alloc] initWithCapacity:2];
    AVMutableComposition *composition = [AVMutableComposition composition];
    for (int i = 0; i < [videoFilePathArray count]; ++i)
    {
        NSString *videoPath = [videoFilePathArray objectAtIndex:i];
        NSURL *videoURL = getFileURL(videoPath);
        AVAsset *videoAsset = [AVAsset assetWithURL:videoURL];
        
        if (i == 0)
        {
            // BG video duration
            bgVideoTimeRange = [[videoAsset firstVideoTrack] timeRange];
        }
        
        if (videoAsset)
        {
            [self addAsset:videoAsset toComposition:composition withTrackID:i+1 withRecordAudio:NO withTimeRange:bgVideoTimeRange];
            [assetArray addObject:videoAsset];
            
            // Max duration
            duration = MAX(duration, CMTimeGetSeconds(videoAsset.duration));
        }
    }
    
    if ([assetArray count] < 1)
    {
        NSLog(@"assetArray is empty!");
        
        // Output path
        self.filenameBlock = ^(void) {
            return @"";
        };
        
        if (self.finishVideoBlock)
        {
            self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
        }
        
        return;
    }
    
    // Embedded Music
    if (!isStringEmpty(audioFilePath))
    {
        AVURLAsset *audioAsset = [[AVURLAsset alloc] initWithURL:getFileURL(audioFilePath) options:nil];
        AVAssetTrack *assetAudioTrack = nil;
        if ([[audioAsset tracksWithMediaType:AVMediaTypeAudio] count] > 0)
        {
            assetAudioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
            if (assetAudioTrack)
            {
                AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
                [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake(duration*30, 30)) ofTrack:assetAudioTrack atTime:kCMTimeZero error:nil];
            }
        }
        else
        {
            NSLog(@"Reminder: embedded audio file is empty!");
        }
    }
    else
    {
        // BG video music
        AVAssetTrack *assetAudioTrack = nil;
        AVAsset *audioAsset = [assetArray objectAtIndex:0];
        if ([[audioAsset tracksWithMediaType:AVMediaTypeAudio] count] > 0)
        {
            assetAudioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
            if (assetAudioTrack)
            {
                AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
                [compositionAudioTrack insertTimeRange:bgVideoTimeRange ofTrack:assetAudioTrack atTime:kCMTimeZero error:nil];
            }
        }
        else
        {
            NSLog(@"Reminder: embeded BG video hasn't audio!");
        }
    }
    
    // BG video
    AVAssetTrack *firstVideoTrack = [assetArray[0] firstVideoTrack];
    CGSize videoSize = CGSizeMake(firstVideoTrack.naturalSize.width, firstVideoTrack.naturalSize.height);
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    
    BOOL shouldRotate = [self shouldRightRotate90ByTrackID:TrackIDCustom];
    if (shouldRotate)
    {
        videoComposition.renderSize = CGSizeMake(videoSize.height, videoSize.width);
    }
    else
    {
        videoComposition.renderSize = CGSizeMake(videoSize.width, videoSize.height);
    }
    
    videoComposition.frameDuration = CMTimeMakeWithSeconds(1.0 / firstVideoTrack.nominalFrameRate, firstVideoTrack.naturalTimeScale);
    instruction.timeRange = [composition.tracks.firstObject timeRange];
    
    NSMutableArray *layerInstructionArray = [[NSMutableArray alloc] initWithCapacity:1];
    for (int i = 0; i < [assetArray count]; ++i)
    {
        AVMutableVideoCompositionLayerInstruction *videoLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstruction];
        videoLayerInstruction.trackID = i + 1;
        
        [layerInstructionArray addObject:videoLayerInstruction];
    }
    
    instruction.layerInstructions = layerInstructionArray;
    videoComposition.instructions = @[ instruction ];
    videoComposition.customVideoCompositorClass = [CustomVideoCompositor class];
    
    // Export
    NSString *exportPath = [self getOutputFilePath];
    NSURL *exportURL = [NSURL fileURLWithPath:[self returnFormatString:exportPath]];
    // Delete old file
    unlink([exportPath UTF8String]);
    
    _exportSession = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetMediumQuality];
    _exportSession.outputURL = exportURL;
    _exportSession.outputFileType = AVFileTypeMPEG4;
    _exportSession.shouldOptimizeForNetworkUse = YES;
    
    if (videoComposition)
    {
        _exportSession.videoComposition = videoComposition;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Progress monitor
        _timerEffect = [NSTimer scheduledTimerWithTimeInterval:0.3f
                                                        target:self
                                                      selector:@selector(retrievingExportProgress)
                                                      userInfo:nil
                                                       repeats:YES];
    });
    
    __block typeof(self) blockSelf = self;
    [_exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
        switch ([_exportSession status])
        {
            case AVAssetExportSessionStatusCompleted:
            {
                // Close timer
                [blockSelf.timerEffect invalidate];
                blockSelf.timerEffect = nil;
                
                // Save video to Album
                [self writeExportedVideoToAssetsLibrary:exportPath];
                
                NSLog(@"Export Successful: %@", exportPath);
                break;
            }
                
            case AVAssetExportSessionStatusFailed:
            {
                // Close timer
                [blockSelf.timerEffect invalidate];
                blockSelf.timerEffect = nil;
                
                // Output path
                self.filenameBlock = ^(void) {
                    return @"";
                };
                
                if (self.finishVideoBlock)
                {
                    self.finishVideoBlock(NO, GBLocalizedString(@"MsgConvertFailed"));
                }
                
                NSLog(@"Export failed: %@, %@", [[blockSelf.exportSession error] localizedDescription], [blockSelf.exportSession error]);
                break;
            }
                
            case AVAssetExportSessionStatusCancelled:
            {
                NSLog(@"Canceled: %@", blockSelf.exportSession.error);
                break;
            }
            default:
                break;
        }
    }];
}

- (CGRect)getCroppedRect
{
    NSArray *pointsPath = [self getPathPoints];
    return getCroppedBounds(pointsPath);
}

// Convert 'space' char
- (NSString *)returnFormatString:(NSString *)str
{
    return [str stringByReplacingOccurrencesOfString:@" " withString:@""];
}

#pragma mark - Export Progress Callback
- (void)retrievingFilterProgress
{
    if (_movieFile && _exportProgressBlock)
    {
        NSString *title = GBLocalizedString(@"Processing");
        self.exportProgressBlock([NSNumber numberWithFloat:_movieFile.progress], title);
    }    
}

- (void)retrievingExportProgress
{
    if (_exportSession && _exportProgressBlock)
    {
        self.exportProgressBlock([NSNumber numberWithFloat:_exportSession.progress], nil);
    }
}

#pragma mark - NSUserDefaults
#pragma mark - setShouldRightRotate90
- (void)setShouldRightRotate90:(BOOL)shouldRotate withTrackID:(NSInteger)trackID
{
    NSString *identifier = [NSString stringWithFormat:@"TrackID_%ld", (long)trackID];
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    if (shouldRotate)
    {
        [userDefaultes setBool:YES forKey:identifier];
    }
    else
    {
        [userDefaultes setBool:NO forKey:identifier];
    }
    
    [userDefaultes synchronize];
}

- (BOOL)shouldRightRotate90ByTrackID:(NSInteger)trackID
{
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [NSString stringWithFormat:@"TrackID_%ld", (long)trackID];
    BOOL result = [[userDefaultes objectForKey:identifier] boolValue];
    NSLog(@"shouldRightRotate90ByTrackID %@ : %@", identifier, result?@"Yes":@"No");
    
    if (result)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark - ShouldRightRotate90ByCustom
- (BOOL)shouldRightRotate90ByCustom:(NSString *)identifier
{
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    BOOL result = [[userDefaultes objectForKey:identifier] boolValue];
    NSLog(@"shouldRightRotate90ByCustom %@ : %@", identifier, result?@"Yes":@"No");
    
    if (result)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark - PathPoints
- (NSArray *)getPathPoints
{
    NSArray *arrayResult = nil;
    NSString *flag = @"ArrayPathPoints";
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    NSData *dataPathPoints = [userDefaultes objectForKey:flag];
    if (dataPathPoints)
    {
        arrayResult = [NSKeyedUnarchiver unarchiveObjectWithData:dataPathPoints];
//        if (arrayResult && [arrayResult count] > 0)
//        {
//            NSLog(@"points has content.");
//        }
    }
    else
    {
        NSLog(@"getPathPoints is empty.");
    }
    
    return arrayResult;
}

@end
