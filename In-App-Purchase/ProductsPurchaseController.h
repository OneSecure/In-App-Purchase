#import <UIKit/UIKit.h>
//
// http://www.himigame.com/iphone-cocos2d/550.html
//

extern NSString *const kSubscriptionInterval;
extern NSString *const kProductName;

@interface ProductsPurchaseController : UITableViewController
@property(nonatomic, strong) dispatch_block_t firstBuyCallback;
@property(nonatomic, copy) NSDictionary<NSString*, NSDictionary*> *productCollection;
@property(nonatomic, copy) NSDate *originBaseDate;

- (instancetype) initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype) initWithProductIDs:(NSDictionary<NSString*, NSDate*> *)productsPurchased
                         completion:(void (^)(NSDictionary<NSString*, NSDate*> *productsPurchased))completion;
@end
