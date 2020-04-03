
// Provide notification about the product request

#import <StoreKit/StoreKit.h>

typedef NS_ENUM(NSInteger, PurchaseStatus) {
    IAPPurchaseFailed,
    IAPPurchaseSucceeded,
    IAPRestoredFailed,
    IAPRestoredSucceeded,
    IAPDownloadStarted,
    IAPDownloadInProgress,
    IAPDownloadFailed,
    IAPDownloadSucceeded,
};

typedef void(^SKProductsResponseCallback)(NSArray<SKProduct *> *products, NSError *error);

@class StoreManager;
typedef void (^PurchaseNotificationCallback)(StoreManager *observer, id context, PurchaseStatus status);

@interface StoreManager : NSObject

@property (nonatomic, copy) NSString *message;

@property(nonatomic) float downloadProgress;
// Keep track of the purchased/restored product's identifier
@property (nonatomic, copy) NSString *purchasedID;

@property(nonatomic, strong) PurchaseNotificationCallback purchaseNotification;

+ (instancetype) sharedInstance;
- (instancetype) init NS_UNAVAILABLE;

// Query the App Store about the given product identifiers
- (void) fetchProductsForIds:(NSArray<NSString*> *)productIds
            responseCallback:(SKProductsResponseCallback)responseCallback;

- (BOOL) canMakePayments;

// Implement the purchase of a product
- (void) buy:(SKProduct *)product;

- (void) buyWithIdentifier:(NSString *)productID;

// Implement the restoration of previously completed purchases
- (void) restore;

@end
