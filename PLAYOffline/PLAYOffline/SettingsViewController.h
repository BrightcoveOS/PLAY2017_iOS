//
//  SettingsViewController.h
//  BCOVOfflineDRM
//
//  Created by Steve Bushell on 1/27/17.
//  Copyright (c) 2017 Brightcove. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "VideosViewController.h"

@interface SettingsViewController : UIViewController <UITabBarControllerDelegate>

@property (nonatomic, nonnull) UITabBarController *tabBarController;

// Accessors for license type and info
- (BOOL)purchaseLicenseType;
- (unsigned long long)rentalDuration;


@end

// For quick access to this controller from other tabs
extern SettingsViewController * _Nonnull gSettingsViewController;
