//
//  ViewController.m
//  PLAY360
//
//  Created by Steve Bushell on 5/17/17.
//  Copyright © 2017 Brightcove. All rights reserved.
//

// This project demonstrates how to play a 360 video in your app.
// In most circumstances you don't need to make any changes at all to your
// regular video workflow to play 360 video, but there are a few details
// that can make the experience better.

// 1 - VR Goggles support
// The BCOVPUIPlayerViewDelegate protocol has a delegate method:
// - (void)didSetVideo360NavigationMethod:(BCOVPUIVideo360NavigationMethod)navigationMethod projectionStyle:(BCOVVideo360ProjectionStyle)projectionStyle
// You can implement this method to find out when the user has tapped the "VR Goggles"
// button, and then force the screen orientation to landscape.
// See below for a sample implementation.
//
// 2 - Setting the "projection" property
// If you are creating your own 360 video object, you should be sure to set the
// "projection" property to "equirectangular".
// Setting this flag will active the 360 video view for that video.
// See -playNextVideo below to see this in action.


#import "ViewController.h"

@import BrightcovePlayerSDK;

@interface ViewController () <BCOVPlaybackControllerDelegate, BCOVPUIPlayerViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic) IBOutlet UIView *videoView;
@property (nonatomic) id<BCOVPlaybackController> playbackController;
@property (nonatomic) BCOVPUIPlayerView *playerView;
@property (nonatomic) BCOVPlaybackService *playbackService;
@property (nonatomic) BCOVVideo *retrievedVideo;

@property (nonatomic) IBOutlet UIButton *videoButton;

// Helps manage device orientation
@property (nonatomic) BOOL landscapeOnly;

@end

// Demo video account credentials
static NSString * const kSampleVideoCloudPlaybackServicePolicyKey = @"BCpkADawqM1W-vUOMe6RSA3pA6Vw-VWUNn5rL0lzQabvrI63-VjS93gVUugDlmBpHIxP16X8TSe5LSKM415UHeMBmxl7pqcwVY_AZ4yKFwIpZPvXE34TpXEYYcmulxJQAOvHbv2dpfq-S_cm";
static NSString * const kSampleVideoCloudAccountID = @"3636334163001";
static NSString * const kSampleVideo360VideoID = @"5240309173001";


@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)requestContentFromPlaybackService
{
    [self.playbackService findVideoWithVideoID:kSampleVideo360VideoID
                                    parameters:nil
                                    completion:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
                                        
                                        if (video != nil)
                                        {
                                            self.retrievedVideo = video;
                                            [self.playbackController setVideos:@[ video ]];
                                        }
                                        else
                                        {
                                            // No online video? Try the built-in video
                                            [self playNextVideo];
                                        }
                                        
                                    }];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (self.landscapeOnly)
    {
        return UIInterfaceOrientationMaskLandscape;
    }
    
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (self.landscapeOnly)
    {
        switch (interfaceOrientation)
        {
            case UIInterfaceOrientationLandscapeLeft:
            case UIInterfaceOrientationLandscapeRight:
                // all good
                break;
            default:
            {
                return NO;
                break;
            }
        }
    }
    
    return YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self createPlayerView];
    
    // Create Playback Controller
    BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
    
    self.playbackController = [sdkManager createPlaybackController];
    self.playerView.playbackController = self.playbackController;
    
    self.playbackController.delegate = self;
    self.playbackController.autoPlay = YES;
    self.playbackController.autoAdvance = YES;
    
    // Instantiate Playback Service
    self.playbackService = [[BCOVPlaybackService alloc] initWithAccountId:kSampleVideoCloudAccountID
                                                                policyKey:kSampleVideoCloudPlaybackServicePolicyKey];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self requestContentFromPlaybackService];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (void)playNextVideo
{
    static int sVideoNumber = 1;
    
    if (sVideoNumber > 1)
        sVideoNumber = 0;
    
    switch (sVideoNumber ++)
    {
        case 0:
        {
            // Play our pre-fetched video
            if (self.retrievedVideo)
            {
                [self.playbackController setVideos:@[ self.retrievedVideo ]];
            }
            break;
        }
            
        case 1:
        {
            // Play local video
            NSURL *videoURL = [[NSBundle mainBundle] URLForResource:@"videos_s_3"
                                                      withExtension:@"mp4"];
            BCOVSource *source = [[BCOVSource alloc] initWithURL:videoURL
                                                  deliveryMethod:kBCOVSourceDeliveryHLS
                                                      properties:nil];
            
            // Set "projection" property to indicate that it's a 360 video
            BCOVVideo *video360 = [[BCOVVideo alloc] initWithSource:source
                                                          cuePoints:nil
                                                         properties:@{ @"projection": @"equirectangular" }];
            
            [self.playbackController setVideos:@[ video360 ]];
            break;
        }
    }
}

- (IBAction)handleVideoButton:(UIButton *)button
{
    [self playNextVideo];
}

- (void)createPlayerView
{
    if (self.playerView == nil)
    {
        BCOVPUIPlayerViewOptions *options = [[BCOVPUIPlayerViewOptions alloc] init];
        options.presentingViewController = self;
        
        BCOVPUIBasicControlView *controlView = [BCOVPUIBasicControlView basicControlViewWithVODLayout];
        self.playerView = [[BCOVPUIPlayerView alloc] initWithPlaybackController:nil
                                                                        options:options
                                                                   controlsView:controlView];
        self.playerView.frame = self.videoView.bounds;
        self.playerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [self.videoView addSubview:self.playerView];
        
        // Set delegate so we know when the VR Goggles button has been tapped
        self.playerView.delegate = self;
    }
}

#pragma mark - PlayerView Delegate Methods

// Respond to navigation method and projection style changes
// from tap on VR Goggles button
- (void)didSetVideo360NavigationMethod:(BCOVPUIVideo360NavigationMethod)navigationMethod
                       projectionStyle:(BCOVVideo360ProjectionStyle)projectionStyle
{
    switch (projectionStyle)
    {
        case BCOVVideo360ProjectionStyleNormal:
        {
            NSLog(@"projectionStyle == BCOVVideo360ProjectionStyleNormal");
            
            // No landscape restriction
            self.landscapeOnly = NO;
            break;
        }
            
        case BCOVVideo360ProjectionStyleVRGoggles:
        {
            NSLog(@"projectionStyle == BCOVVideo360ProjectionStyleVRGoggles");
            
            // Allow landscape only if wearing goggles
            self.landscapeOnly = YES;
            
            // If the goggles are on, change the device orientation
            UIDeviceOrientation currentDeviceOrientation = [UIDevice currentDevice].orientation;
            switch (currentDeviceOrientation)
            {
                case UIDeviceOrientationLandscapeLeft:
                case UIDeviceOrientationLandscapeRight:
                    // all good
                    break;
                default:
                {
                    // switch orientation
                    NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft];
                    [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
                    break;
                }
            }
            
            break;
        }
    }
    
    [UIViewController attemptRotationToDeviceOrientation];
}

#pragma mark - Playback Controller Delegate Methods

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
{
    // If there's an error, play the built-in video
    if ([lifecycleEvent.eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFail]
        || [lifecycleEvent.eventType isEqualToString:kBCOVPlaybackSessionLifecycleEventFailedToPlayToEndTime])
    {
        [self playNextVideo];
    }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller didCompletePlaylist:(id<NSFastEnumeration>)playlist
{
    // play again
    [self.playbackController setVideos:playlist];
}

@end
