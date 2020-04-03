#import <UIKit/UIKit.h>
//
// http://www.himigame.com/iphone-cocos2d/550.html
//

@interface ProductsPurchaseController : UITableViewController
@property(nonatomic, strong) dispatch_block_t firstBuyCallback;
@property(nonatomic, copy) NSDictionary<NSString*, NSNumber*> *subscriptionIntervals;
@property(nonatomic, copy) NSDate *originBaseDate;

- (instancetype) initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype) initWithProductIDs:(NSDictionary *)ids completion:(void (^)(NSDictionary *ids))completion;
@end
