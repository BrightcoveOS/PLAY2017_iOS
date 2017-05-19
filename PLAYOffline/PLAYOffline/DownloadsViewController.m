//
//  DownloadsViewController.m
//  BCOVOfflineDRM
//
//  Created by Steve Bushell on 1/27/17.
//  Copyright (c) 2017 Brightcove. All rights reserved.
//

#import "DownloadsViewController.h"


// For quick access to this controller from other tabs
DownloadsViewController *gDownloadsViewController;

@interface DownloadsViewController () <BCOVPlaybackControllerDelegate, BCOVPUIPlayerViewDelegate, UITableViewDataSource, UITableViewDelegate>

// Views and controls at the top of the Downloads tab
@property (nonatomic) IBOutlet UIView *downloadProgressView;
@property (nonatomic) IBOutlet UIImageView *posterImageView;
@property (nonatomic) BCOVPUIPlayerView *playerView;
@property (nonatomic) IBOutlet UIView *videoContainer;
@property (nonatomic) IBOutlet UILabel *infoLabel;
@property (nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic) IBOutlet UIButton *hideButton;
@property (nonatomic) IBOutlet UIButton *pauseButton;
@property (nonatomic) IBOutlet UIButton *cancelButton;

// Main table of downloaded videos
@property (nonatomic, weak) IBOutlet UITableView *downloadsTableView;


// Free storage space label inside table footer
@property (nonatomic) UILabel *freeSpaceLabel;
@property (nonatomic) NSTimer *freeSpaceTimer;

// Which video was last selected in the table
@property (nonatomic) BCOVOfflineVideoToken selectedOfflineVideoToken;

// Object to control playback in video container
@property (nonatomic, strong) id<BCOVPlaybackController> playbackController;
@property (nonatomic, strong) BCOVFPSBrightcoveAuthProxy *authProxy;

@end


// utility for finding the size of a directory in our application folder
unsigned long long int directorySize(NSString *folderPath)
{
    if (folderPath == nil)
        return 0;
    
    unsigned long long int fileSize = 0;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:folderPath error:nil];
    
    for (NSString *fileName in filesArray)
    {
        NSDictionary *fileDictionary =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[folderPath stringByAppendingPathComponent:fileName] error:nil];
        fileSize += [fileDictionary fileSize];
    }
    
    return fileSize;
}


@implementation DownloadsViewController

#pragma mark Initialization method

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Become delegate so we can control orientation
    gVideosViewController.tabBarController.delegate = self;

    // Refresh the table
    [self.downloadsTableView reloadData];
}

- (void)setup
{
    // Add actions to button controls
    [self.playButton addTarget:self
                        action:@selector(doPlayHideButton:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.pauseButton addTarget:self
                        action:@selector(doPauseButton:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.cancelButton addTarget:self
                        action:@selector(doCancelButton:)
              forControlEvents:UIControlEventTouchUpInside];
}

// Create the PlayerUI controls
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
        self.playerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        self.playerView.delegate = self;
        [self.videoContainer addSubview:self.playerView];
        self.videoContainer.alpha = 0.0;
    }
}

// Create the playback controller
- (void)createNewPlaybackController
{
    if (!self.playbackController)
    {
        NSLog(@"Creating a new playbackController");
        
        BCOVPlayerSDKManager *sdkManager = [BCOVPlayerSDKManager sharedManager];
        
        self.authProxy = [[BCOVFPSBrightcoveAuthProxy alloc] initWithPublisherId:nil applicationId:nil];
        
        BCOVBasicSessionProviderOptions *options = [[BCOVBasicSessionProviderOptions alloc] init];
        options.sourceSelectionPolicy = [BCOVBasicSourceSelectionPolicy sourceSelectionHLSWithScheme:kBCOVSourceURLSchemeHTTPS];
        id<BCOVPlaybackSessionProvider> psp = [sdkManager createBasicSessionProviderWithOptions:options];
        id<BCOVPlaybackSessionProvider> fps = [sdkManager createFairPlaySessionProviderWithAuthorizationProxy:self.authProxy
                                                                                      upstreamSessionProvider:psp];
        
        id<BCOVPlaybackController> playbackController = [sdkManager createPlaybackControllerWithSessionProvider:fps viewStrategy:nil];
        playbackController.autoAdvance = YES;
        playbackController.autoPlay = YES;
        playbackController.delegate = self;
        self.playbackController = playbackController;
        self.playerView.playbackController = playbackController;
    }
}

// Play: show video container and start up the playback controller
// Hide: destroy the playback controller and hide the video container
- (IBAction)doPlayHideButton:(id)sender
{
    if (self.playbackController == nil)
    {
        // Convert offline video token to a BCOVVideo object so we can play it
        BCOVVideo *video = [BCOVOfflineVideoManager.sharedManager videoObjectFromOfflineVideoToken:self.selectedOfflineVideoToken];
        
        if (video == nil)
        {
            NSLog(@"Could not find video for token %@", self.selectedOfflineVideoToken);
            return;
        }
        
        self.videoContainer.alpha = 1.0;
        
        [self createNewPlaybackController];
        [self.playbackController setVideos:@[ video ]];
        
        [self.playButton setTitle:@"Hide" forState:UIControlStateNormal];
    }
    else
    {
        // Hiding
        self.playbackController = nil;
        self.videoContainer.alpha = 0.0;

        [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
    }
}

// Pause a download in progress
- (IBAction)doPauseButton:(id)sender
{
    BCOVOfflineVideoManager *sharedManager = BCOVOfflineVideoManager.sharedManager;

    BCOVOfflineVideoStatus *offlineVideoStatus = [sharedManager offlineVideoStatusForToken:self.selectedOfflineVideoToken];
    
    switch (offlineVideoStatus.downloadState)
    {
        case BCOVOfflineVideoDownloadStateRequested:
            break;

        case BCOVOfflineVideoDownloadStateDownloading:
            [sharedManager pauseVideoDownload:self.selectedOfflineVideoToken];
            break;

        case BCOVOfflineVideoDownloadStateSuspended:
            [sharedManager resumeVideoDownload:self.selectedOfflineVideoToken];
            break;

        case BCOVOfflineVideoDownloadStateCancelled:
        case BCOVOfflineVideoDownloadStateCompleted:
        case BCOVOfflineVideoDownloadStateError:
            break;
    }
}

// Cancel a download in progress
- (IBAction)doCancelButton:(id)sender
{
    BCOVOfflineVideoManager *sharedManager = BCOVOfflineVideoManager.sharedManager;
    
    BCOVOfflineVideoStatus *offlineVideoStatus = [sharedManager offlineVideoStatusForToken:self.selectedOfflineVideoToken];
    
    switch (offlineVideoStatus.downloadState)
    {
        case BCOVOfflineVideoDownloadStateRequested:
        case BCOVOfflineVideoDownloadStateDownloading:
        case BCOVOfflineVideoDownloadStateSuspended:
            [sharedManager cancelVideoDownload:self.selectedOfflineVideoToken];
            break;

        case BCOVOfflineVideoDownloadStateCancelled:
        case BCOVOfflineVideoDownloadStateCompleted:
        case BCOVOfflineVideoDownloadStateError:
            break;
    }
}

// Initial setup
- (void)viewDidLoad
{
    [super viewDidLoad];

    gDownloadsViewController = self;

    self.tabBarController = (UITabBarController*)self.parentViewController;

    self.downloadsTableView.dataSource = self;
    self.downloadsTableView.delegate = self;
    [self.downloadsTableView setContentInset:UIEdgeInsetsMake(0, 0, 0, 0)];
    [self createTableFooter];
    [self updateInfoForSelectedDownload];
    
    [self createPlayerView];

    [self setup];
}

// Refresh the list of downloaded videos
- (void)refresh
{
    [self.downloadsTableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    // Create the free space timer
    [self freeSpaceUpdate:nil];
    self.freeSpaceTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                           target:self
                                                         selector:@selector(freeSpaceUpdate:)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // Clean up
    [self.freeSpaceTimer invalidate];
    self.freeSpaceTimer = nil;
}

- (void)freeSpaceUpdate:(NSTimer *)timer
{
    // Show how much free space is on the device
    const double cMB = (1024.0 * 1024.0);
    const double cGB = (cMB * 1024.0);
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfFileSystemForPath:@"/var" error:nil];
    
    NSNumber *freeSizeNumber = attributes[NSFileSystemFreeSize];
    NSNumber *fileSystemSizeNumber = attributes[NSFileSystemSize];
    
    NSString *freeSpaceString = [NSString stringWithFormat:@"Free: %.1f MB of %.1f GB",
                                 freeSizeNumber.doubleValue / cMB,
                                 fileSystemSizeNumber.doubleValue / cGB];
    
    self.freeSpaceLabel.textColor = [UIColor blackColor];
    if (freeSizeNumber.doubleValue / cMB < 500)
    {
        self.freeSpaceLabel.textColor = [UIColor orangeColor];
    }
    if (freeSizeNumber.doubleValue / cMB < 100)
    {
        self.freeSpaceLabel.textColor = [UIColor redColor];
    }
    
    self.freeSpaceLabel.text = freeSpaceString;
    self.freeSpaceLabel.frame = CGRectMake(0, 0, self.downloadsTableView.frame.size.width, 28);
}

// Create footer to display free space
- (void)createTableFooter
{
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 28)];
    footerView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.freeSpaceLabel = [[UILabel alloc] init];
    self.freeSpaceLabel.frame = CGRectMake(0, 0, 320, 28);
    self.freeSpaceLabel.numberOfLines = 1;
    [self.freeSpaceLabel setText:@"Free:"];
    self.freeSpaceLabel.textAlignment = NSTextAlignmentCenter;
    self.freeSpaceLabel.font = [UIFont boldSystemFontOfSize:14];
    self.freeSpaceLabel.textColor = [UIColor blackColor];
    self.freeSpaceLabel.backgroundColor = [UIColor clearColor];
    
    [footerView addSubview:self.freeSpaceLabel];

    self.downloadsTableView.tableFooterView = footerView;
}

// Display all info related to video in the info view
// at the top of the downloads tab
- (void)updateInfoForSelectedDownload
{
    self.infoLabel.text = @"No video selected";
    
    if (self.selectedOfflineVideoToken == nil)
        return;
    
    BCOVOfflineVideoStatus *offlineVideoStatus = [gVideosViewController.offlineVideoManager offlineVideoStatusForToken:self.selectedOfflineVideoToken];
    
    if (offlineVideoStatus == nil)
        return;
    
    // Convert offline video token to a BCOVVideo object
    // so that we can get at all the metadata
    BCOVVideo *video = [gVideosViewController.offlineVideoManager videoObjectFromOfflineVideoToken:self.selectedOfflineVideoToken];
    
    
    NSString *videoID = video.properties[@"id"];
    NSNumber *sizeNumber = gVideosViewController.estimatedDownloadSizeDictionary[videoID];
    double megabytes = sizeNumber.doubleValue;
    
    NSNumber *startTimeNumber = video.properties[kBCOVOfflineVideoDownloadStartTimePropertyKey];
    NSTimeInterval startTime = startTimeNumber.doubleValue;
    NSNumber *endTimeNumber = video.properties[kBCOVOfflineVideoDownloadEndTimePropertyKey];
    NSTimeInterval endTime = endTimeNumber.doubleValue;
    NSTimeInterval totalDownloadTime = (endTime - startTime);
    NSTimeInterval currentTime = NSDate.date.timeIntervalSinceReferenceDate;

    // Get license information
    NSString *licenseText =
    ({
        NSString *text;
        NSNumber *purchaseNumber = video.properties[kBCOVFairPlayLicensePurchaseKey];
        NSNumber *rentalDurationNumber = video.properties[kBCOVFairPlayLicenseRentalDurationKey];
        
        
        do
        {
            if ((purchaseNumber != nil) && (purchaseNumber.boolValue == YES))
            {
                text = @"purchase";
                break;
            }
            
            if (rentalDurationNumber != nil)
            {
                double rentalDuration = rentalDurationNumber.doubleValue;
                NSDate *startDate = [NSDate dateWithTimeIntervalSinceReferenceDate:startTime];
                NSDate *expirationDate = [startDate dateByAddingTimeInterval:rentalDuration];
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                dateFormatter.dateStyle = kCFDateFormatterMediumStyle;
                dateFormatter.timeStyle = NSDateFormatterShortStyle;
                text = [NSString stringWithFormat:@"Rental (expires %@)",
                        [dateFormatter stringFromDate:expirationDate]];
                
                break;
            }
            
        } while (false);
        
        text;
    });
    
    // Get download info based on the download status
    double mbps;
    NSString *downloadState;
    
    switch (offlineVideoStatus.downloadState)
    {
        case BCOVOfflineVideoDownloadStateRequested:
            downloadState = @"download requested";
            break;
        case BCOVOfflineVideoDownloadStateDownloading:
        {
            mbps = ((megabytes * offlineVideoStatus.downloadPercent / 100.0) / (currentTime - startTime));
            downloadState = [NSString stringWithFormat:@"downloading (%0.1f%% @ %0.1f MB/s)", offlineVideoStatus.downloadPercent, mbps];
            break;
        }
        case BCOVOfflineVideoDownloadStateSuspended:
        {
            downloadState = [NSString stringWithFormat:@"paused (%0.1f%%)", offlineVideoStatus.downloadPercent];
            break;
        }
        case BCOVOfflineVideoDownloadStateCancelled:
            downloadState = @"cancelled";
            break;
        case BCOVOfflineVideoDownloadStateCompleted:
        {
            mbps = ((megabytes * offlineVideoStatus.downloadPercent / 100.0) / totalDownloadTime);
            downloadState = [NSString stringWithFormat:@"complete (%0.1f MB/s @ %d mins)", mbps, (int)(totalDownloadTime / 60.0)];
            break;
        }
        case BCOVOfflineVideoDownloadStateError:
            downloadState = [NSString stringWithFormat:@"error %ld (%@)", (long)offlineVideoStatus.error.code, offlineVideoStatus.error.localizedDescription];
            break;
    }
    
    NSString *infoText = [NSString stringWithFormat:@"%@\n"
                          @"Status: %@\n"
                          @"License: %@\n",
                          video.properties[@"name"],
                          downloadState,
                          licenseText];
    
    self.infoLabel.text = infoText;
    [self.infoLabel sizeToFit];
}

#pragma mark - BCOVPlaybackController Delegate Methods

- (void)playbackController:(id<BCOVPlaybackController>)controller playbackSession:(id<BCOVPlaybackSession>)session didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
{
    // Report any playback errors
    if ([kBCOVPlaybackSessionLifecycleEventFail isEqualToString:lifecycleEvent.eventType])
    {
        NSError *error = lifecycleEvent.properties[kBCOVPlaybackSessionEventKeyError];
        NSLog(@"Error: `%@`", error.userInfo[NSUnderlyingErrorKey]);
    }
}

- (void)playbackController:(id<BCOVPlaybackController>)controller didAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
}

#pragma mark - UITabBarController Delegate Methods

- (UIInterfaceOrientationMask)tabBarControllerSupportedInterfaceOrientations:(UITabBarController *)tabBarController
{
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - BCOVPUIPlayerViewDelegate Methods

- (void)playerView:(BCOVPUIPlayerView *)playerView willTransitionToScreenMode:(BCOVPUIScreenMode)screenMode
{
    // Use the PlayerUI's delegate method to hide the tab bar controller
    // when we go full screen.
    self.tabBarController.tabBar.hidden = (screenMode == BCOVPUIScreenModeFull);
}

#pragma mark - UITableView delegate methods

- (IBAction)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    // Respond to selection of a video download
    self.selectedOfflineVideoToken = gVideosViewController.offlineVideoTokenArray[indexPath.row];

    // Load poster image into the detail view

    // Convert offline video token to a BCOVVideo object
    // so that we can get the metadata property
    // containing the poster image path
    BCOVVideo *video = [gVideosViewController.offlineVideoManager videoObjectFromOfflineVideoToken:self.selectedOfflineVideoToken];

    // Make sure we have a backup image if the poster is not there
    UIImage *defaultImage = [UIImage imageNamed:@"bcov"];

    NSString *posterPathString = video.properties[kBCOVOfflineVideoPosterFilePathPropertyKey];
    UIImage *posterImage = [UIImage imageWithContentsOfFile:posterPathString];
    
    self.posterImageView.image = posterImage ?: defaultImage;
    self.posterImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.posterImageView.clipsToBounds = YES;

    [self updateInfoForSelectedDownload];

    // Update the Pause/Resume button title
    BCOVOfflineVideoStatus *offlineVideoStatus = [gVideosViewController.offlineVideoManager offlineVideoStatusForToken:self.selectedOfflineVideoToken];
    
    switch (offlineVideoStatus.downloadState)
    {
        case BCOVOfflineVideoDownloadStateDownloading:
            [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
            [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
            break;

        case BCOVOfflineVideoDownloadStateSuspended:
            [self.pauseButton setTitle:@"Resume" forState:UIControlStateNormal];
            [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
            break;
            
        default:
            [self.pauseButton setTitle:@"--" forState:UIControlStateNormal];
            [self.cancelButton setTitle:@"--" forState:UIControlStateNormal];
            break;
    }
}

- (BOOL)tableView:(UITableView *)tableView
canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Allow swipe-to-delete
    return YES;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Handle swipe-to-delete for a downloaded video
    BCOVOfflineVideoToken brightcoveOfflineToken = gVideosViewController.offlineVideoTokenArray[indexPath.row];
    
    // Delete from storage through the offline video mananger
    [gVideosViewController.offlineVideoManager deleteOfflineVideo:brightcoveOfflineToken];

    // Report deletion so that the video page can update download status
    [gVideosViewController didRemoveVideoFromTable:(BCOVOfflineVideoToken)brightcoveOfflineToken];
    
    // Remove from our local list of video tokens
    NSMutableArray *updatedOfflineVideoTokenArray = gVideosViewController.offlineVideoTokenArray.mutableCopy;
    [updatedOfflineVideoTokenArray removeObject:brightcoveOfflineToken];
    gVideosViewController.offlineVideoTokenArray = updatedOfflineVideoTokenArray;
    
    [self.downloadsTableView deleteRowsAtIndexPaths:@[indexPath]
                                   withRowAnimation:UITableViewRowAnimationFade];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [NSString stringWithFormat:@"%d Offline Videos", (int)gVideosViewController.offlineVideoTokenArray.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSArray<BCOVOfflineVideoStatus *> *statusArray = [gVideosViewController.offlineVideoManager offlineVideoStatus];
    
    int inProgressCount = 0;
    for (BCOVOfflineVideoStatus *offlineVideoStatus in statusArray)
    {
        if (offlineVideoStatus.downloadState == BCOVOfflineVideoDownloadStateDownloading)
        {
            inProgressCount ++;
        }
    }

    NSString *footerString;
    
    switch (inProgressCount)
    {
        case 0:
            footerString = [NSString stringWithFormat:@"All Videos Are Fully Downloaded"];
            break;
        case 1:
            footerString = [NSString stringWithFormat:@"1 Video Is Still Downloading"];
            break;
        default:
            footerString = [NSString stringWithFormat:@"%d Videos Are Still Downloading",
                            inProgressCount];
            break;
    }
    
    return footerString;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return a new table view cell for this row
    int index = (int)indexPath.row;
    BCOVOfflineVideoToken offlineVideoToken = gVideosViewController.offlineVideoTokenArray[index];
    BCOVOfflineVideoStatus *offlineVideoStatus = [gVideosViewController.offlineVideoManager offlineVideoStatusForToken:offlineVideoToken];

    // Convert offline video token to a BCOVVideo object
    // so that we can get at all the metadata
    BCOVVideo *video = [BCOVOfflineVideoManager.sharedManager videoObjectFromOfflineVideoToken:offlineVideoToken];

    // Get a new table view cell
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"download_cell"
                                                            forIndexPath:indexPath];
    
    // Extract info from video properties
    cell.textLabel.text = video.properties[@"name"];
    NSString *detailString = video.properties[@"description"];
    if ((detailString == nil) || (detailString.length == 0))
    {
        detailString = video.properties[@"reference_id"];
    }
    
    // Detail text is two lines consisting of:
    // "duration in seconds / actual download size)"
    // "reference_id"
    cell.detailTextLabel.numberOfLines = 2;
    NSNumber *durationNumber = video.properties[@"duration"];
    int duration = durationNumber.intValue / 1000;
    NSString *twoLineDetailString;

    if (offlineVideoStatus.downloadState == BCOVOfflineVideoDownloadStateCompleted)
    {
        // download complete: show the downloaded video size
        NSNumber *megabytesValue = gVideosViewController.downloadSizeDictionary[offlineVideoToken];
        double megabytes = 0.0;

        // Compute size if it hasn't been done yet
        if (megabytesValue == nil)
        {
            NSString *videoFilePath = video.properties[kBCOVOfflineVideoFilePathPropertyKey];
            unsigned long long int videoSize = directorySize(videoFilePath);
            megabytes = (double)videoSize / (1024.0 * 1024.0);

            // Store the computed value
            gVideosViewController.downloadSizeDictionary[offlineVideoToken] = @(megabytes);
        }
        else
        {
            // use precomputed value
            megabytes = megabytesValue.doubleValue;
        }

        twoLineDetailString = [NSString stringWithFormat:@"%d sec / %0.2f MB\n%@",
                               duration, megabytes,
                               detailString ?: @""];
    }
    else
    {
        // download not complete: skip the download size
        twoLineDetailString = [NSString stringWithFormat:@"%d sec / %@ MB\n%@",
                               duration, @"--",
                               detailString ?: @""];
    }

    cell.detailTextLabel.text = twoLineDetailString;
    
    // Set the thumbnail image
    {
        NSString *thumbnailPathString = video.properties[kBCOVOfflineVideoThumbnailFilePathPropertyKey];
        UIImage *thumbnailImage = [UIImage imageWithContentsOfFile:thumbnailPathString];
        
        // Set up the image view
        // Use a default image if the cached image is not available
        cell.imageView.image = thumbnailImage ?: [UIImage imageNamed:@"bcov"];
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    }

    DownloadCell *downloadCell = (DownloadCell *)cell;
    
    
    if (offlineVideoStatus == nil)
    {
        [downloadCell setStateImage:eVideoStateOnlineOnly];
    }
    else
    {
        switch (offlineVideoStatus.downloadState)
        {
            case BCOVOfflineVideoDownloadStateRequested:
            case BCOVOfflineVideoDownloadStateDownloading:
                [downloadCell setStateImage:eVideoStateDownloading];
                break;
            case BCOVOfflineVideoDownloadStateSuspended:
                [downloadCell setStateImage:eVideoStatePaused];
                break;
            case BCOVOfflineVideoDownloadStateCancelled:
                [downloadCell setStateImage:eVideoStateCancelled];
                break;
            case BCOVOfflineVideoDownloadStateCompleted:
                [downloadCell setStateImage:eVideoStateDownloaded];
                break;
            case BCOVOfflineVideoDownloadStateError:
                [downloadCell setStateImage:eVideoStateError];
                break;
        }
    }
    
    downloadCell.progress = offlineVideoStatus.downloadPercent;
    [downloadCell setNeedsLayout];

    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return gVideosViewController.offlineVideoTokenArray.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 72;
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
@implementation DownloadCell : UITableViewCell

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
    
    _progressBarView = [[UIView alloc] initWithFrame:CGRectZero];
    _progressBarView.backgroundColor = UIColor.greenColor;
    [self.contentView addSubview:_progressBarView];
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
    
    const int cProgressBarHeight = 2;
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

    // Align progress bar along bottom edge.
    CGRect progressBarFrame = CGRectMake(0, self.contentView.bounds.size.height - cProgressBarHeight - 2,
                                         cellWidth * self.progress / 100, cProgressBarHeight);
    self.progressBarView.frame = progressBarFrame;
}

@end
