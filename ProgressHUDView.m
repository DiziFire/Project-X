#import "ProgressHUDView.h"

@implementation ProgressHUDView

+ (ProgressHUDView *)showHUDAddedTo:(UIView *)view title:(NSString *)title {
    ProgressHUDView *hud = [[ProgressHUDView alloc] initWithFrame:view.bounds];
    hud.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 120)];
    container.center = hud.center;
    container.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    container.layer.cornerRadius = 14;
    container.clipsToBounds = YES;
    container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    hud.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 240, 22)];
    hud.titleLabel.text = title;
    hud.titleLabel.textAlignment = NSTextAlignmentCenter;
    hud.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    hud.titleLabel.textColor = [UIColor whiteColor];
    [container addSubview:hud.titleLabel];

    hud.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    hud.progressView.frame = CGRectMake(20, 56, 200, 12);
    hud.progressView.progress = 0.0f;
    [container addSubview:hud.progressView];

    hud.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, 240, 20)];
    hud.detailLabel.textAlignment = NSTextAlignmentCenter;
    hud.detailLabel.font = [UIFont systemFontOfSize:13];
    hud.detailLabel.textColor = [UIColor lightGrayColor];
    [container addSubview:hud.detailLabel];

    [hud addSubview:container];
    [view addSubview:hud];
    return hud;
}

+ (void)hideHUDForView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[ProgressHUDView class]]) {
            [sub removeFromSuperview];
        }
    }
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    [self.progressView setProgress:progress animated:animated];
}

- (void)setDetailText:(NSString *)text {
    self.detailLabel.text = text;
}

@end
