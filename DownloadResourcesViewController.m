#import <UIKit/UIKit.h>

// DownloadResourcesViewController.m
#import "DownloadResourcesViewController.h"

@implementation DownloadResourcesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Download resources";

    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    descLabel.text = @"Download AppStore++ for downgrade and upgrade app";
    descLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    descLabel.numberOfLines = 0;
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:descLabel];

    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [downloadButton setTitle:@"Download AppStore++" forState:UIControlStateNormal];
    downloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    downloadButton.layer.cornerRadius = 10;
    downloadButton.backgroundColor = [UIColor systemBlueColor];
    [downloadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [downloadButton addTarget:self action:@selector(downloadAppStorePlus) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:downloadButton];

    [NSLayoutConstraint activateConstraints:@[
        [descLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        [descLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [descLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [downloadButton.topAnchor constraintEqualToAnchor:descLabel.bottomAnchor constant:40],
        [downloadButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [downloadButton.widthAnchor constraintEqualToConstant:260],
        [downloadButton.heightAnchor constraintEqualToConstant:54],
    ]];
}

- (void)downloadAppStorePlus {
    NSURL *url = [NSURL URLWithString:@"https://github.com/CokePokes/AppStorePlus-TrollStore/releases/download/v1.2-1/AppStore++_TrollStore_v1.0.3-2.ipa"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end
