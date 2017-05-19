//
//  SettingsViewController.m
//  BCOVOfflineDRM
//
//  Created by Steve Bushell on 1/27/17.
//  Copyright (c) 2017 Brightcove. All rights reserved.
//

@import AVFoundation;

#import "SettingsViewController.h"


// For quick access to this controller from other tabs
SettingsViewController *gSettingsViewController;

@interface SettingsViewController ()

// IBOutlets for our UI elements
@property (nonatomic) IBOutlet UITextField *rentalDurationTextField;
@property (nonatomic) IBOutlet UIView *rentalSettingsView;
@property (nonatomic) IBOutlet UISegmentedControl *licenseTypeSegmentedControl;

@end


@implementation SettingsViewController


#pragma mark Initialization method

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder;
{
    self = [super initWithCoder:aDecoder];
    
    if (self)
    {
        gSettingsViewController = self;
    }
    
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Become delegate so we can control orientation
    gVideosViewController.tabBarController.delegate = self;
}

- (UIInterfaceOrientationMask)tabBarControllerSupportedInterfaceOrientations:(UITabBarController *)tabBarController
{
    return UIInterfaceOrientationMaskPortrait;
}

- (void)setup
{
    [self.licenseTypeSegmentedControl addTarget:self
                                         action:@selector(doLicenseTypeChange:)
                               forControlEvents:UIControlEventValueChanged];

    // Add a "Done" button to the numeric keyboard
    UIToolbar *keyboardDoneButtonView = [[UIToolbar alloc] init];
    [keyboardDoneButtonView sizeToFit];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                   style:UIBarButtonItemStyleDone target:self
                                                                  action:@selector(doneClicked:)];
    [keyboardDoneButtonView setItems:[NSArray arrayWithObjects:doneButton, nil]];
    self.rentalDurationTextField.inputAccessoryView = keyboardDoneButtonView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tabBarController = (UITabBarController*)self.parentViewController;

    [self setup];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.view endEditing:YES];
}

- (IBAction)doneClicked:(id)sender
{
    [self.view endEditing:YES];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
}

- (BOOL)purchaseLicenseType
{
    if (self.licenseTypeSegmentedControl == nil)
    {
        return NO;
    }

    BOOL isPurchaseLicenseType = (self.licenseTypeSegmentedControl.selectedSegmentIndex == 1);
    
    return isPurchaseLicenseType;
}

- (IBAction)doLicenseTypeChange:(id)sender
{
    BOOL isPurchaseLicenseType = [self purchaseLicenseType];

    self.rentalSettingsView.alpha = (isPurchaseLicenseType ? 0.0 : 1.0);
}

- (unsigned long long)rentalDuration
{
    if (self.rentalDurationTextField == nil)
    {
        return 3e9;
    }

    unsigned long long durationSeconds = self.rentalDurationTextField.text.longLongValue;
    
    return durationSeconds;
}

- (IBAction)doCrash:(id)sender
{
    // Give the user an option to crash the app.
    // This is used to show that we can recover downloads in progress
    // when the app is launched after a crash.
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Crash!"
                                                                   message:@"Click OK to crash the app"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction * action) {
                                                              
                                                              NSLog(@"Crashing...");
                                                              void (^crashBlock)(void) = nil;
                                                              
                                                              crashBlock();
                                                              
                                                          }];
    
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * action) { }];
    
    [alert addAction:defaultAction];
    [alert addAction:cancelAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
