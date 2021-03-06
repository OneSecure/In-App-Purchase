#import "StoreManager.h"
#import "ProductsPurchaseController.h"
#import <objc/runtime.h>

#ifndef OsGetMethodName
#define OsGetMethodName() ([NSString stringWithFormat:@"[%s] %@", (const char *)class_getName([self class]), NSStringFromSelector(_cmd)])
#endif

@interface ProductsPurchaseController () {
    __weak StoreManager *_storeManager;
    __weak PurchaseNotificationCallback _cachedCallback;
    
    NSMutableDictionary<NSString *, NSDate *> *_productsPurchased; // pruduct identifier - purchases date pair.
    NSArray<SKProduct*> *_productsRecievedFromAppStore;            // SKProduct objects
    
    void (^_completion)(NSDictionary<NSString*, NSDate*> *productsPurchased);
    
    UIActivityIndicatorView *_activityIndicator;
}
@end

@implementation ProductsPurchaseController

NSString *const kSubscriptionInterval = @"subscriptionInterval";
NSString *const kProductName = @"productName";

- (instancetype) initWithProductIDs:(NSDictionary<NSString*, NSDate*> *)productsPurchased
                         completion:(void (^)(NSDictionary<NSString*, NSDate*> *productsPurchased))completion
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        // Custom initialization
        _productsPurchased = [NSMutableDictionary dictionaryWithDictionary:productsPurchased];
        _completion = completion;
        
        _storeManager = [StoreManager sharedInstance];
        _cachedCallback = _storeManager.purchaseNotification;
        _storeManager.purchaseNotification = ^(StoreManager *observer, id context, PurchaseStatus status) {
            [self onPurchaseNotification:observer context:context status:status];
        };
        if (@available(iOS 13.0, *)) {
            _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        } else {
            _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        }
        
#if 0
        _productCollection = @{
            @"productOneID":    @{ kSubscriptionInterval : @(30*365*24*3600), kProductName : @"Permanent use", },
            @"productTwoID":    @{ kSubscriptionInterval : @(366*24*3600),    kProductName : @"Annual subscription", },
            @"productThreeID":  @{ kSubscriptionInterval : @(31*24*3600),     kProductName : @"Monthly subscription", },
        };
#endif
    }
    return self;
}

- (void) viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _storeManager.purchaseNotification = _cachedCallback;
    if (_completion) {
        _completion(_productsPurchased);
    }
}

- (void) viewDidLoad {
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"Purchases", nil);
    
    UIImage *img = [UIImage imageNamed:@"restore" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain target:self action:@selector(restorePurchase:)];
    
    CGPoint center = self.view.center; center.y /= 2;
    _activityIndicator.center = center;
    [self.view addSubview:_activityIndicator];
    
    [self fetchProductInformation];
}

- (void) restorePurchase:(id)sender {
    // Call StoreObserver to restore all restorable purchases
    [_storeManager restore];
}

#pragma mark - Fetch product information

// Retrieve product information from the App Store
- (void) fetchProductInformation {
    // Query the App Store for product information if the user is is allowed to make purchases.
    // Display an alert, otherwise.
    if ([_storeManager canMakePayments]) {
        NSArray *productIds = [_productCollection allKeys];
        
        if (productIds.count == 0) {
            NSAssert(NO, @"%@ - Products count can NOT zero!!!", OsGetMethodName());
            return;
        }
        [_storeManager fetchProductsForIds:productIds responseCallback:^(NSArray<SKProduct *> *products, NSError *error) {
            [self productsRequestFinished:products error:error];
        }];
        [_activityIndicator startAnimating];
    }
    else {
        // Warn the user that they are not allowed to make purchases.
        [self alertWithTitle:NSLocalizedString(@"Warning", nil)
                     message:NSLocalizedString(@"Purchases are disabled on this device.", nil)];
    }
}

#pragma mark - Handle product request notification

// Update the UI according to the notification result
- (void) productsRequestFinished:(NSArray<SKProduct *> *)products error:(NSError*)error {
    dispatch_block_t block = ^(void) {
        [self->_activityIndicator stopAnimating];
        self->_productsRecievedFromAppStore = products;
        NSInteger count = products.count;
        if (error) {
            [self alertWithTitle:NSLocalizedString(@"Warning", nil) message:error.localizedDescription];
            return;
        }
        @try {
            NSAssert((count == self.productCollection.count), @"something went wrong");
            (void)count;
        } @catch (NSException *exception) {
            [self alertWithTitle:NSLocalizedString(@"Warning", nil) message:exception.reason];
        } @finally {
            // Reload the tableview to update it
            [self.tableView reloadData];
        }
    };
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            block();
        });
    }
}

- (SKProduct*) findSKProduct:(NSString*)identifier {
    SKProduct *found = nil;
    // Iterate through availableProducts to find the product whose productIdentifier
    // property matches identifier, return its localized title when found
    for (SKProduct *product in _productsRecievedFromAppStore) {
        if ([product.productIdentifier isEqualToString:identifier]) {
            found = product;
        }
    }
    return found;
}

- (NSString *) titleMatchingProductIdentifier:(NSString *)identifier {
    NSString *productTitle = nil;
    SKProduct *product = [self findSKProduct:identifier];
    if (product) {
        productTitle = product.localizedTitle;
    }
    if (productTitle == nil) {
        productTitle = _productCollection[identifier][kProductName];
        NSAssert(productTitle, @"productTitle");
    }
    return productTitle;
}

#pragma mark - Handle purchase request notification

// Update the UI according to the notification result
- (void) onPurchaseNotification:(StoreManager *)observer context:(id)context status:(PurchaseStatus)status {
    NSString *title;
    NSString *displayedTitle;
    NSString *purchasedID = observer.purchasedID;
    NSString *msg;
    SKPaymentTransaction *transaction = (SKPaymentTransaction *)context;
    NSDate *date;
    
    switch (status)
    {
        case IAPPurchaseSucceeded:
            NSAssert([transaction isKindOfClass:SKPaymentTransaction.class], @"%@ something went wrong", OsGetMethodName());
            title = [self titleMatchingProductIdentifier:purchasedID];
            
            // Display the product's title associated with the payment's product identifier if it exists
            // or the product identifier, otherwise
            displayedTitle = (title.length > 0) ? title : purchasedID;
            msg = [NSString stringWithFormat:NSLocalizedString(@"'%@' was successfully purchased.", nil), displayedTitle];
            [self alertWithTitle:NSLocalizedString(@"Purchase Status", nil) message:msg];
            
            date = transaction.transactionDate;
            [self purchaseChanged:purchasedID date:date firstBuy:YES];
            break;
            
        case IAPPurchaseFailed:
            NSAssert([transaction isKindOfClass:SKPaymentTransaction.class], @"%@ something went wrong", OsGetMethodName());
            title = [self titleMatchingProductIdentifier:transaction.payment.productIdentifier];
            msg = [NSString stringWithFormat:NSLocalizedString(@"Purchase of '%@' failed.\nbecause of '%@'", nil), title, transaction.error.localizedDescription];
            [self alertWithTitle:NSLocalizedString(@"Purchase Status", nil) message:msg];
            break;
            
        case IAPRestoredSucceeded:
            NSAssert([transaction isKindOfClass:SKPaymentTransaction.class], @"%@ something went wrong", OsGetMethodName());
            // Switch to the iOSPurchasesList view controller when receiving a successful restore notification
            purchasedID = transaction.payment.productIdentifier;
            date = transaction.transactionDate;
            [self purchaseChanged:purchasedID date:date firstBuy:NO];
            break;
            
        case IAPRestoredFailed:
        {
            NSError *error = (NSError*)context;
            NSAssert([error isKindOfClass:NSError.class], @"%@ something went wrong", OsGetMethodName());
            [self alertWithTitle:NSLocalizedString(@"Purchase Status", nil) message:error.localizedDescription];
            break;
        }
        case IAPDownloadStarted:
            // Notify the user that downloading is about to start when receiving a download started notification
            //self.hasDownloadContent = YES;
            //[self.view addSubview:self.statusMessage];
            NSAssert(NO, @"%@ Not implement yet", OsGetMethodName());
            break;
            
        case IAPDownloadInProgress:
            // Display a status message showing the download progress
            //self.hasDownloadContent = YES;
            title = [self titleMatchingProductIdentifier:purchasedID];
            displayedTitle = (title.length > 0) ? title : purchasedID;
            //self.statusMessage.text = [NSString stringWithFormat:@"Downloading %@ %.2f%%",displayedTitle, observer.downloadProgress];
            NSAssert(NO, @"%@ Not implement yet", OsGetMethodName());
            break;
            
        case IAPDownloadSucceeded:
            // Downloading is done, remove the status message
            //self.hasDownloadContent = NO;
            //self.statusMessage.text = @"Download complete: 100%";
            // Remove the message after 2 seconds
            //[self performSelector:@selector(hideStatusMessage) withObject:nil afterDelay:2];
            NSAssert(NO, @"%@ Not implement yet", OsGetMethodName());
            break;
            
        default:
            break;
    }
}

- (void) purchaseChanged:(NSString *)pID date:(NSDate*)date firstBuy:(BOOL)firstBuy {
    NSDate *oldDate = _productsPurchased[pID];
    if ([oldDate isKindOfClass:[NSDate class]] == NO) {
        oldDate = self.originBaseDate;
        if (firstBuy) {
            if (_firstBuyCallback) {
                _firstBuyCallback();
            }
        }
    }
    if ([oldDate compare:date] == NSOrderedAscending) {
        _productsPurchased[pID] = date;
    }
    
    [self.tableView reloadData];
}

#pragma mark - Display message

// Display an alert with a given title and message
- (void) alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alertCtrl =
    [UIAlertController alertControllerWithTitle:title
                                        message:message
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* ok =
    [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                             style:UIAlertActionStyleCancel
                           handler:nil];
    [alertCtrl addAction:ok];
    [self presentViewController:alertCtrl animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // This stupid code was caused by Apple Inc., not me.
    return _productCollection.count; // return [_productsRecievedFromAppStore count];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"availableProductID"];
    
    NSString *pID = _productCollection.allKeys[indexPath.row];
    SKProduct *aProduct = [self findSKProduct:pID];
    if (aProduct) {
        // Show the localized title of the product
        // Show the product's price in the locale and currency returned by the App Store
        NSString *price = [NSString stringWithFormat:@"%@ %@",
                           [aProduct.priceLocale objectForKey:NSLocaleCurrencySymbol],
                           [aProduct price]];
        NSString *localizedTitle = aProduct.localizedTitle?:_productCollection[pID][kProductName];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ - %@", localizedTitle, price];
        
        cell.detailTextLabel.text = aProduct.localizedDescription?:NSLocalizedString(@"No more detail information", nil);
    } else {
        cell.textLabel.text = _productCollection[pID][kProductName];
        cell.detailTextLabel.text = NSLocalizedString(@"Loading information from App Store", nil);
    }
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    [_productsPurchased enumerateKeysAndObjectsUsingBlock:^(NSString *pid, NSDate *date, BOOL *stop) {
        if ([pid isEqualToString:aProduct.productIdentifier]) {
            if ([self isPurchased:pid date:date]) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            *stop = YES;
        }
    }];
    
    return cell;
}

- (BOOL) isPurchased:(NSString*)pid date:(NSDate*)date {
    NSNumber *interval = _productCollection[pid][kSubscriptionInterval];
    if ([date isKindOfClass:[NSDate class]] == NO) {
        date = self.originBaseDate;
    }
    NSDate *expiration = [date dateByAddingTimeInterval:interval.floatValue];
    return ([[NSDate date] compare:expiration] == NSOrderedAscending);
}

#pragma mark - UITableViewDelegate

// Start a purchase when the user taps a row
- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *pID = _productCollection.allKeys[indexPath.row];
    SKProduct *product = [self findSKProduct:pID];
    if (product) {
        // Attempt to purchase the tapped product
        [_storeManager buy:product];
    } else {
        [_storeManager buyWithIdentifier:pID];
    }
}

#pragma mark -
- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) dealloc {
}

@end
