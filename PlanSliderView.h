#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PlanSliderView;

// Protocol for handling plan selection and purchase events
@protocol PlanSliderViewDelegate <NSObject>
@optional
- (void)planSliderView:(PlanSliderView *)sliderView didSelectPlan:(NSDictionary *)plan;
- (void)planSliderView:(PlanSliderView *)sliderView didPurchasePlan:(NSDictionary *)plan;
@end

@interface PlanSliderView : UIView <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

// Initialize with auth token for API requests
- (instancetype)initWithFrame:(CGRect)frame authToken:(NSString *)authToken;

// Method to load plans from API
- (void)loadPlans;

// Method to calculate the height needed for the content
- (CGFloat)getContentHeight;

// Method to handle plan purchase from cells
- (void)handlePlanPurchase:(NSDictionary *)plan;

// Properties
@property (nonatomic, weak) id<PlanSliderViewDelegate> delegate;
@property (nonatomic, strong) NSArray *plans;
@property (nonatomic, strong) NSString *authToken;
@property (nonatomic, assign, getter=isLoading) BOOL loading;

@end

NS_ASSUME_NONNULL_END 