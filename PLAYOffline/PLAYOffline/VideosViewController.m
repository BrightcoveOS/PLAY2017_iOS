//
//  VideosViewController.m
//  BCOVOfflineDRM
//
//  Created by Steve Bushell on 1/27/17.
//  Copyright (c) 2017 Brightcove. All rights reserved.
//

#import "VideosViewController.h"
#import "DownloadsViewController.h"
#import "SettingsViewController.h"

// This project demonstrates how you can implement an app that
// supports offline playback with FairPlay.
//
// To run this app, you need a Brightcove Dynamic Delivery account,
// plus a playlist of FairPlay-encoded videos.
// You can enter your account information in the section
// immediatly below.
//
// Before downloading any content, you must set the "offline_enabled" property
// in Video Cloud for every video that you want to be eligible for offline playback.
// You can do this through the CMS API; see the CMS API reference documentation
// on brightcove.com for details.


// Enter your Brightcove Dynamic Delivery account information here:
NSString * const kDynamicDeliveryAccountID = @""; // your account ID
NSString * const kDynamicDeliveryPolicyKey = @""; // policy key for your account";
NSString * const kDynamicDeliveryPlaylistRefID = @""; // playlist ref ID for your FairPlay-protected videos";


// For quick access to this controller from other tabs
VideosViewController *gVideosViewController;

@interface VideosViewController () <BCOVPlaybackControllerDelegate, BCOVPUIPlayerViewDelegate, UITableViewDataSource, UITableViewDelegate>

// Brightcove-related objects
@property (nonatomic, strong) BCOVPlaybackService *playbackService;
@property (nonatomic, strong) BCOVPUIPlayerView *playerView;
@property (nonatomic, strong) BCOVFPSBrightcoveAuthProxy *authProxy;

// View that holds the video's player view
@property (nonatomic, weak) IBOutlet UIView *videoContainer;

// Keep track of info from the playlist
// for easy display in the table
@property NSMutableArray<BCOVVideo *> *currentVideos;
@property (nonatomic, strong) NSString *currentPlaylistTitle;
@property (nonatomic, strong) NSString *currentPlaylistDescription;
@property (nonatomic, strong) NSMutableDictionary *imageCacheDictionary;

@property (nonatomic, weak) IBOutlet UITableView *videosTableView;

@end


@implementation VideosViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Become delegate so we can control orientation
    gVideosViewController.tabBarController.delegate = self;

    [self updateStatus];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self showWarnings];
}

- (void)setup
{
    [self retrievePlaylist];
    [self createNewPlaybackController];
    [self updateStatus];
}

// Removes the downloaded video
- (void)didRemoveVideoFromTable:(nonnull BCOVOfflineVideoToken)brightcoveOfflineToken
{
    [self updateStatus];
}

- (void)usePlaylist:(NSArray *)playlist
{
    // Re-initialize all the containers that store information
    // related to the videos in the current playlist
    self.imageCacheDictionary = [NSMutableDictionary dictionary];
    self.videosTableViewData = [NSMutableArray array];
    self.estimatedDownloadSizeDictionary = [NSMutableDictionary dictionary];
    
    for (BCOVVideo *video in playlist)
    {
        // Async task to get and store thumbnails
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            // videoID is the key in the image cache dictionary
            NSString *videoID = video.properties[@"id"];
            
            // Find the https URL to our thumbnail
            NSArray *thumbnailSourcesArray = video.properties[@"thumbnail_sources"];
            
            if (thumbnailSourcesArray)
            {
                for (NSDictionary *thumbnailDictionary in thumbnailSourcesArray)
                {
                    NSString *thumbnailURLString = thumbnailDictionary[@"src"];
                    if (thumbnailURLString == nil)
                        return;
                    
                    NSURL *thumbnailURL = [NSURL URLWithString:thumbnailURLString];
                    if ([thumbnailURL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)
                    {
                        NSData *thumbnailImageData = [NSData dataWithContentsOfURL:thumbnailURL];
                        UIImage *thumbnailImage = [UIImage imageWithData:thumbnailImageData];
                        
                        if (thumbnailImage != nil)
                        {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                self.imageCacheDictionary[videoID] = thumbnailImage;
                                [self.videosTableView reloadData];
                                
                            });
                        }
                    }
                }
            }
        });
        
        // Estimate download size for each video
        [self.offlineVideoManager estimateDownloadSize:video
                                               options:nil
                                            completion:^(double megabytes, NSError *error) {
                                                
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    
                                                    // Store the returned size in our dictionary
                                                    NSString *videoID = video.properties[@"id"];
                                                    
                                                    if (videoID != nil)
                                                    {
                                                        self.estimatedDownloadSizeDictionary[videoID] = @(megabytes);
                                                    }
                                                    
                                                    [self.videosTableView reloadData];
                                                    
                                                });
                                                
                                            }];
        
        NSDictionary *videoDictionary =
        @{
          @"video": video,
          @"state": ( video.canBeDownloaded ? @(eVideoStateDownloadable) : @(eVideoStateOnlineOnly) )
          };
        
        [self.videosTableViewData addObject:videoDictionary.mutableCopy];
    }
    
    [self.videosTableView reloadData];
}

- (void)retrievePlaylist
{
    // Dynamic Delivery/DRM account credentials
    NSString *accountID = kDynamicDeliveryAccountID;
    NSString *policyKey = kDynamicDeliveryPolicyKey;
    NSString *playlistRefID = kDynamicDeliveryPlaylistRefID;

    // Retrieve a playlist through the BCOVPlaybackService
    BCOVPlaybackServiceRequestFactory *playbackServiceRequestFactory = [[BCOVPlaybackServiceRequestFactory alloc] initWithAccountId:accountID
                                                                                                                          policyKey:policyKey];
    BCOVPlaybackService *playbackService = [[BCOVPlaybackService alloc] initWithRequestFactory:playbackServiceRequestFactory];
    
    [playbackService findPlaylistWithReferenceID:playlistRefID
                                      parameters:nil
                                      completion:^(BCOVPlaylist *playlist, NSDictionary *jsonResponse, NSError *error)
     {
         
         if (playlist)
         {
             self.currentVideos = playlist.videos.mutableCopy;
             self.currentPlaylistTitle = playlist.properties[@"name"];
             self.currentPlaylistDescription = playlist.properties[@"description"];

             NSLog(@"Retrieved playlist containing %d videos", (int)self.currentVideos.count);
             
             [self usePlaylist:self.currentVideos];
         }
         else
         {
             NSLog(@"No playlist for ID %@ was found.", playlistRefID);
         }
         
     }];
}

#pragma mark - UITabBarController Delegate Methods

- (UIInterfaceOrientationMask)tabBarControllerSupportedInterfaceOrientations:(UITabBarController *)tabBarController
{
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - BCOVPlaybackController Delegate Methods

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
{
    if ([kBCOVPlaybackSessionLifecycleEventFail isEqualToString:lifecycleEvent.eventType])
    {
        NSError *error = lifecycleEvent.properties[kBCOVPlaybackSessionEventKeyError];
        NSLog(@"Error: `%@`", error.userInfo[NSUnderlyingErrorKey]);
    }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller didAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
    if (session)
    {
        NSLog(@"Session source details: %@", session.source);
    }
}

#pragma mark - BCOVPUIPlayerViewDelegate Methods

- (void)playerView:(BCOVPUIPlayerView *)playerView willTransitionToScreenMode:(BCOVPUIScreenMode)screenMode
{
    self.tabBarController.tabBar.hidden = (screenMode == BCOVPUIScreenModeFull);
}

#pragma mark - BCOVOfflineVideoManagerDelegate Methods

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
             downloadTask:(AVAssetDownloadTask *)downloadtask
            didProgressTo:(NSTimeInterval)percent
{
    NSLog(@"didProgressTo: %0.2f%% for token: %@", (float)percent, offlineVideoToken);
    
    dispatch_async(dispatch_get_main_queue(), ^{

        [self updateStatus];
        [gDownloadsViewController refresh];
        [gDownloadsViewController updateInfoForSelectedDownload];

    });
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
didFinishDownloadWithError:(NSError *)error
{
    NSLog(@"Download finished with error: %@", error);

    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self updateStatus];
        [gDownloadsViewController refresh];
        [gDownloadsViewController updateInfoForSelectedDownload];
        
    });
}

- (void)didDownloadStaticImagesWithOfflineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
{
    // Called when the thumbnail and poster frame downloads
    // for the specified video token are complete
}

#pragma mark - Support

- (void)createPlayerView
{
    if (self.playerView == nil)
    {
        BCOVPUIPlayerViewOptions *options = [[BCOVPUIPlayerViewOptions alloc] init];
        options.presentingViewController = self;
        
        BCOVPUIBasicControlView *controlView = [BCOVPUIBasicControlView basicControlViewWithVODLayout];
        self.playerView = [[BCOVPUIPlayerView alloc] initWithPlaybackController:nil
                                                                        options:options
                                                                   controlsView:controlView ];

        self.playerView.frame = self.videoContainer.bounds;
        self.playerView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
        self.playerView.delegate = self;
        [self.videoContainer addSubview:self.playerView];
    }
}

- (void)createNewPlaybackController
{
    if (!self.playbackController)
    {
        NSLog(@"Creating a new playbackController");

        BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];

        // Publisher/application IDs not required for Dynamic Delivery
        self.authProxy = [[BCOVFPSBrightcoveAuthProxy alloc] initWithPublisherId:nil
                                                                   applicationId:nil];
        
        // You can use the same auth proxy for the offline video manager
        // and the call to create the FairPlay session provider.
        BCOVOfflineVideoManager.sharedManager.authProxy = self.authProxy;
        
        // Create the session provider chain
        BCOVBasicSessionProviderOptions *options = [[BCOVBasicSessionProviderOptions alloc] init];
        options.sourceSelectionPolicy = [BCOVBasicSourceSelectionPolicy sourceSelectionHLSWithScheme:kBCOVSourceURLSchemeHTTPS];
        id<BCOVPlaybackSessionProvider> basicSessionProvider = [sdkManager createBasicSessionProviderWithOptions:options];
        id<BCOVPlaybackSessionProvider> fairPlaySessionProvider = [sdkManager createFairPlaySessionProviderWithApplicationCertificate:nil
                                                                                                                   authorizationProxy:self.authProxy
                                                                                                              upstreamSessionProvider:basicSessionProvider];
        
        // Create the playback controller
        id<BCOVPlaybackController> playbackController = [sdkManager createPlaybackControllerWithSessionProvider:fairPlaySessionProvider
                                                                                                   viewStrategy:nil];

        // Start playing right away (the default value for autoAdvance is NO)
        playbackController.autoAdvance = YES;
        playbackController.autoPlay = YES;

        // Register for delegate method callbacks
        playbackController.delegate = self;

        // Retain the playback controller
        self.playbackController = playbackController;

        // Associate the playback controller with the player view
        self.playerView.playbackController = playbackController;
    }
}

- (void)showWarnings
{
    // Account credentials warning
    if (kDynamicDeliveryAccountID.length == 0)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Invalid account information"
                                                                       message:@"Don't forget to enter your account information at the top of VideosViewController.m"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * action) {}];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Simulator warning
#if (TARGET_OS_SIMULATOR)
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reminder..."
                                                                   message:@"FairPlay videos won't display in a simulator."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {}];
    
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
    return;
#endif
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.downloadSizeDictionary = [NSMutableDictionary dictionary];

    // Initialize the Offline Video Manager once before using it
    [BCOVOfflineVideoManager initializeOfflineVideoManagerWithDelegate:self
                                                               options:@{}];
    self.offlineVideoManager = BCOVOfflineVideoManager.sharedManager;
    gVideosViewController = self;

    self.tabBarController = (UITabBarController*)self.parentViewController;
    
    self.videosTableView.dataSource = self;
    self.videosTableView.delegate = self;
    [self.videosTableView setContentInset:UIEdgeInsetsMake(0, 0, 8, 0)];
    
    [NSURLCache.sharedURLCache removeAllCachedResponses];
    
    [self createPlayerView];
    [self setup];
    
    [self updateBadge];
}

- (void)updateStatus
{
    // Refresh the list of downloaded videos from the offline video manager
    self.offlineVideoTokenArray = [self.offlineVideoManager offlineVideoTokens];

    // Update UI with current information
    [self updateBadge];
    [self.videosTableView reloadData];
    
    [self updateStatusForPlaylist];
}

// Update the video dictionary array with the current status
// as reported by the offline video manager
- (void)updateStatusForPlaylist
{
    // Get any array of the status of every downloaded or downloading video
    NSArray<BCOVOfflineVideoStatus *> *statusArray = [self.offlineVideoManager offlineVideoStatus];
    
    // Get a status object from the status array
    for (BCOVOfflineVideoStatus * offlineVideoStatus in statusArray)
    {
        // Find the matching local video dictionary
        // (Match them using the offline video token)
        for (NSMutableDictionary *videoDictionary in self.videosTableViewData)
        {
            BCOVOfflineVideoToken testToken = videoDictionary[@"token"];
            
            if ([testToken isEqualToString:offlineVideoStatus.offlineVideoToken])
            {
                // Match! Update status for this dictionary.
                
                switch (offlineVideoStatus.downloadState)
                {
                    case BCOVOfflineVideoDownloadStateRequested:
                    case BCOVOfflineVideoDownloadStateDownloading:
                        videoDictionary[@"state"] = @(eVideoStateDownloading);
                        break;
                    case BCOVOfflineVideoDownloadStateSuspended:
                        videoDictionary[@"state"] = @(eVideoStatePaused);
                        break;
                    case BCOVOfflineVideoDownloadStateCancelled:
                        videoDictionary[@"state"] = @(eVideoStateCancelled);
                        break;
                    case BCOVOfflineVideoDownloadStateCompleted:
                        videoDictionary[@"state"] = @(eVideoStateDownloaded);
                        break;
                    case BCOVOfflineVideoDownloadStateError:
                        videoDictionary[@"state"] = @(eVideoStateDownloadable);
                        break;
                }
            }
        }
    }
}

// Set a number on the "Downloads" tab icon
- (void)updateBadge
{
    // Get any array of the status of every downloaded or downloading video
    NSArray<BCOVOfflineVideoStatus *> *statusArray = [self.offlineVideoManager offlineVideoStatus];
    
    //int downloadedCount = (int)statusArray.count;
    
    int downloadingCount = 0;
    
    for (BCOVOfflineVideoStatus * offlineVideoStatus in statusArray)
    {
        if (offlineVideoStatus.downloadState == BCOVOfflineVideoDownloadStateDownloading
            || offlineVideoStatus.downloadState == BCOVOfflineVideoDownloadStateRequested)
        {
            downloadingCount ++;
        }
    }
    
    NSString *badgeString;
    if (downloadingCount > 0)
    {
        badgeString = [NSString stringWithFormat:@"%d", downloadingCount];
    }
    
    self.tabBarController.tabBar.items[1].badgeValue = badgeString;
}

// Handle taps on the download button
- (void)doDownloadButton:(UIButton *)button
{
    // Get index of video that was selected for download
    int index = (int)button.tag;
    NSDictionary *videoDictionary = self.videosTableViewData[index];
    BCOVVideo *video = videoDictionary[@"video"];
    
    // Generate the license parameters based on the Settings tab
    NSDictionary *licenseParameters;
    BOOL isPurchaseLicense = [gSettingsViewController purchaseLicenseType];

    // Set the kBCOVFairPlayLicensePurchaseKey key for purchases,
    // or the kBCOVFairPlayLicenseRentalDurationKey for rental
    if (isPurchaseLicense)
    {
        licenseParameters = @{
                              kBCOVFairPlayLicensePurchaseKey: @YES
                              };
    }
    else
    {
        unsigned long long rentalDuration = [gSettingsViewController rentalDuration];
        
        NSLog(@"Requesting Rental License:\n"
              @"rentalDuration: %llu",
              rentalDuration);
        
        licenseParameters = @{
                              kBCOVFairPlayLicenseRentalDurationKey: @(rentalDuration),
                              };
    }
    
    // Request the vidoe download
    [self.offlineVideoManager requestVideoDownload:video
                                        parameters:licenseParameters
                                        completion:^(BCOVOfflineVideoToken offlineVideoToken, NSError *error) {
                                            
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                
                                                if (error == nil)
                                                {
                                                    // Success! Update our table with the new download status
                                                    NSMutableDictionary *updatedVideoDictionary = videoDictionary.mutableCopy;
                                                    updatedVideoDictionary[@"state"] = @(eVideoStateDownloading);
                                                    updatedVideoDictionary[@"token"] = offlineVideoToken;
                                                    [self.videosTableViewData replaceObjectAtIndex:index
                                                                                        withObject:updatedVideoDictionary];
                                                    
                                                    [self updateStatus];
                                                }
                                                else
                                                {
                                                    // Report any errors
                                                    NSString *alertMessage = error.localizedDescription;
                                                    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Video Download Error"
                                                                                                                   message:alertMessage
                                                                                                            preferredStyle:UIAlertControllerStyleAlert];
                                                    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                                                                          handler:^(UIAlertAction * action) {}];
                                                    
                                                    [alert addAction:defaultAction];
                                                    [self presentViewController:alert animated:YES completion:nil];
                                                }
                                                
                                            });
                                            
                                        }];
}

#pragma mark - UITableView methods

// Play the video in this row when selected
- (IBAction)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSDictionary *videoDictionary = self.videosTableViewData[ (int)indexPath.row ];
    BCOVVideo *video = videoDictionary[@"video"];
    
    if (video != nil)
    {
        [self.playbackController setVideos:@[ video ]];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.currentPlaylistTitle;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return self.currentPlaylistDescription;
}

// Populate table with data from videosTableViewData
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    int row = (int)indexPath.row;
    NSDictionary *videoDictionary = self.videosTableViewData[row];
    BCOVVideo *video = videoDictionary[@"video"];
    NSString *videoID = video.properties[@"id"];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"video_cell"
                                                            forIndexPath:indexPath];
    cell.textLabel.text = video.properties[@"name"];
    NSString *detailString = video.properties[@"description"];
    if ((detailString == nil) || (detailString.length == 0))
    {
        detailString = video.properties[@"reference_id"];
    }

    // Detail text is two lines consisting of:
    // "duration in seconds / estimated download size)"
    // "reference_id"
    cell.detailTextLabel.numberOfLines = 2;
    NSNumber *durationNumber = video.properties[@"duration"];
    int duration = durationNumber.intValue / 1000;
    NSNumber *sizeNumber = self.estimatedDownloadSizeDictionary[videoID];
    double megabytes = sizeNumber.doubleValue;
    NSString *twoLineDetailString = [NSString stringWithFormat:@"%d sec / %0.2f MB\n%@",
                                     duration, megabytes,
                                     detailString ?: @""];
    cell.detailTextLabel.text = twoLineDetailString;

    // Set up the image view
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.clipsToBounds = YES;

    // Use cached thumbnail image for display
    {
        UIImage *thumbnailImage = (UIImage *)self.imageCacheDictionary[videoID];
        
        // Use a default image if the cached image is not available
        cell.imageView.image = thumbnailImage ?: [UIImage imageNamed:@"bcov"];
    }

    // Set the state information for the cell.
    VideoCell *videoCell = (VideoCell *)cell;
    
    NSNumber *stateNumber = videoDictionary[@"state"];

    [videoCell setStateImage:(VideoState)stateNumber.intValue];

    // Add action to status button.
    [videoCell.statusButton addTarget:self
                               action:@selector(doDownloadButton:)
                     forControlEvents:UIControlEventTouchUpInside];
    videoCell.statusButton.tag = row;
    
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.videosTableViewData.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 64;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 32;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 28;
}

@end

// Custom cell implementation to arrange
// text and images more carefully.
// Also adds a download status image.
@implementation VideoCell : UITableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self)
    {
        [self privateInit];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder;
{
    self = [super initWithCoder:aDecoder];
    
    if (self)
    {
        [self privateInit];
    }

    return self;
}

- (void)privateInit
{
    _statusButton = [[UIButton alloc] initWithFrame:CGRectZero];
    [self.contentView addSubview:_statusButton];
}

- (void)setStateImage:(VideoState)state
{
    UIImage *newImage = nil;
    switch (state)
    {
        case eVideoStateOnlineOnly: // nothing
        {
            break;
        }
        case eVideoStateDownloadable:
        {
            newImage = [UIImage imageNamed:@"download"];
            break;
        }
        case eVideoStateDownloading:
        {
            newImage = [UIImage imageNamed:@"inprogress"];
            break;
        }
        case eVideoStatePaused:
        {
            newImage = [UIImage imageNamed:@"paused"];
            break;
        }
        case eVideoStateDownloaded:
        {
            newImage = [UIImage imageNamed:@"downloaded"];
            break;
        }
        case eVideoStateCancelled:
        {
            newImage = [UIImage imageNamed:@"cancelled"];
            break;
        }
        case eVideoStateError:
        {
            newImage = [UIImage imageNamed:@"error"];
            break;
        }
    }

    [self.statusButton setImage:newImage forState:UIControlStateNormal];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    const int cIndicatorImageDimension = 32;
    const int cMargin = 8;
    const int cHalfMargin = cMargin / 2;
    int cellWidth = self.frame.size.width;
    int cellHeight = self.frame.size.height;
    
    // Center image on left side of cell
    int rowHeight = cellHeight;
    int thumbnailHeight = rowHeight - cMargin;
    int thumbnailWidth = thumbnailHeight * 16 / 9;
    self.imageView.frame = CGRectMake(cMargin, cHalfMargin, thumbnailWidth, thumbnailHeight);

    CGRect indicatorImageFrame = self.frame;
    
    // Center indicator image on right
    indicatorImageFrame = CGRectMake(cellWidth - cIndicatorImageDimension - cMargin,
                                     (cellHeight - cIndicatorImageDimension) / 2,
                                     cIndicatorImageDimension,
                                     cIndicatorImageDimension);
    self.statusButton.frame = indicatorImageFrame;
    
    // Stack the label/detail text
    CGRect labelFrame = self.textLabel.frame;
    labelFrame.origin.x = cMargin + thumbnailWidth + cMargin;
    labelFrame.size.width = cellWidth - thumbnailWidth - cIndicatorImageDimension - cMargin * 3;
    self.textLabel.frame = labelFrame;
    
    labelFrame = self.detailTextLabel.frame;
    labelFrame.origin.x = cMargin + thumbnailWidth + cMargin;
    labelFrame.size.width = cellWidth - thumbnailWidth - cIndicatorImageDimension - cMargin * 3;
    self.detailTextLabel.frame = labelFrame;
}

@end
