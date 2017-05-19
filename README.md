# PLAY2017_iOS
iOS Demo apps presented at the Brightcove PLAY 2017 conference

## Requirements

- macOS 10.12
- Xcode 8.3
- iOS 10.0

Offline Playback with DRM requires:
- Brightcove Dynamic Delivery account
- FairPlay-protected videos


## Contents

This repository contains two projects presented at the Brightcove PLAY 2017 conference in Boston, Massachusetts on May 23, 2017. For details about the play conference, visit [PLAY 2017](https://play.brightcove.com).

Both projects contain a copy of the Brightcove Native Player SDK, version 6.0.0 (beta), so you can download and run them without installing any other software. You shoud not use this beta release of the SDK in any app that is being submitted to the App Store.

### PLAY360
An iOS app that shows how to play a 360 video in the Brightcove Native Player SDK.

### PLAYOffline
An iOS app that shows how to implement HLS video downloading and offline playback with the Brightcove Native Player SDK.

## PLAY360

This project will load a 360 video from a demo Brightcove account, and play it in an interactive OpenGL environment. This project can be run in the simulator, but works best on a device because it takes advantage of the device orientation sensing for navigation.

If you tap the "PLAY" logo at the bottom of the screen, you can switch from an online HLS video, to a built-in MP4 video that has its "projection" flag set manually.

The code also shows how you can optionally listen for changes to the navigation method and projection style that occur when the "360" button is tapped in the PlayerUI. When the user enters "VR Goggles" mode, you can see how to switch the app's orientation to landscape.


## PLAYOffline

This project shows how to download, play, and manage offline videos protected with FairPlay encryption.

Since we cannot share FairPlay credentials, you need to enter your own account credentials at the top of VideosViewController.m.

The "kDynamicDeliveryPlaylistRefID" should refer to a playlist reference ID, not a playlist ID. The playlist should contain your FairPlay-protected HLS videos, and these videos should have their `offline_enabled` flags set so that they can be downloaded. Please see the [CMS API Reference](http://docs.brightcove.com/en/video-cloud/cms-api/references/cms-api/versions/v1/index.html) for details about how to set the `offline_enabled` flag.

The "Videos" tab shows you the videos that are available in your playlist. Tap the "download from cloud" button on each cell to begin a download. If you do not see a download button, the "offline_enabled" flag is probably not set.

The "Downloads" tab shows you the videos that are currently downloading, or have already been downloaded. Tap on a video to see information about each download. The size under the video in the table is the actual size in storage.

The "Settings" page is where you can change the license parameters. There is also a "crash" button. This button executes a nil block to terminate the app immediately. You can use this to test the persistence of background downloads. First, start downloading a video, then "crash" the app, and then relaunch. You should see that your downloads have continued in the background, and may have even completed without the app running.

Note that these tests should be performed outside of the Xcode environment. Xcode can interfere with the behavior of background sessions, and can also interfere with video downloads (because running in Xcode can install the app in a new sandbox).

For full details about using Offline Playback with DRM, please see the `OfflinePlayback.md` document in this repository.
