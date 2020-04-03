#import "StoreManager.h"
#import "ProductsPurchaseController.h"
#import <objc/runtime.h>

#ifndef OsGetMethodName
#define OsGetMethodName() ([NSString stringWithFormat:@"[%s] %@", (const char *)class_getName([self class]), NSStringFromSelector(_cmd)])
#endif

@interface ProductsPurchaseController () {
    __weak StoreManager *_storeManager;
    __weak PurchaseNotificationCallback _cachedCallback;
    
    NSMutableDictionary<NSString *, NSDate *> *_productBoughts; // pruduct name - purchases date pair.
    NSArray<SKProduct*> *_products;            // SKProduct objects
    
    void (^_completion)(NSDictionary *ids);
    
    UIActivityIndicatorView *_activityIndicator;
}
@end

@implementation ProductsPurchaseController

- (instancetype) initWithProductIDs:(NSDictionary *)ids completion:(void (^)(NSDictionary *ids))completion {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        // Custom initialization
        _productBoughts = [NSMutableDictionary dictionaryWithDictionary:ids];
        _completion = completion;

        _storeManager = [StoreManager sharedInstance];
        _cachedCallback = _storeManager.purchaseNotification;
        _storeManager.purchaseNotification = ^(StoreManager *observer, id context, PurchaseStatus status) {
            [self onPurchaseNotification:observer context:context status:status];
        };
        if (@available(iOS 13.0, *)) {
            _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        } else {
            _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        }
    }
    return self;
}

- (void) viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _storeManager.purchaseNotification = _cachedCallback;
    if (_completion) {
        _completion(_productBoughts);
    }
}

- (void) viewDidLoad {
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"Purchases", nil);
    
    UIImage *img = [UIImage imageNamed:@"restore" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain target:self action:@selector(restorePurchase:)];
    
    _activityIndicator.center = self.view.center;
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
        NSArray *productIds = [_subscriptionIntervals allKeys];

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
- (void) productsRequestFinished:(NSArray *)products error:(NSError*)error {
    dispatch_block_t block = ^(void) {
        [self->_activityIndicator stopAnimating];
        self->_products = products;
        if (error) {
            [self alertWithTitle:NSLocalizedString(@"Warning", nil) message:error.localizedDescription];
            return;
        }
        @try {
            NSAssert((self->_products.count == self.subscriptionIntervals.count), @"something went wrong");
            (void)self->_products.count;
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

- (NSString *) titleMatchingProductIdentifier:(NSString *)identifier {
    NSString *productTitle = nil;
    // Iterate through availableProducts to find the product whose productIdentifier
    // property matches identifier, return its localized title when found
    for (SKProduct *product in _products) {
        if ([product.productIdentifier isEqualToString:identifier]) {
            productTitle = product.localizedTitle;
        }
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
            msg = [NSString stringWithFormat:@"Purchase of '%@' failed.\nbecause of '%@'", title, transaction.error.localizedDescription];
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
    NSDate *oldDate = _productBoughts[pID];
    if ([oldDate isKindOfClass:[NSDate class]] == NO) {
        oldDate = self.originBaseDate;
        if (firstBuy) {
            if (_firstBuyCallback) {
                _firstBuyCallback();
            }
        }
    }
    if ([oldDate compare:date] == NSOrderedAscending) {
        _productBoughts[pID] = date;
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

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return [_products count];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"availableProductID"];
    SKProduct *aProduct = _products[indexPath.row];
    // Show the localized title of the product
    // Show the product's price in the locale and currency returned by the App Store
    NSString *price = [NSString stringWithFormat:@"%@ %@",
                                 [aProduct.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                 [aProduct price]];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ - %@", aProduct.localizedTitle, price];
    
    cell.detailTextLabel.text = aProduct.localizedDescription;
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    [_productBoughts enumerateKeysAndObjectsUsingBlock:^(NSString *pid, NSDate *date, BOOL *stop) {
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
    NSNumber *interval = _subscriptionIntervals[pid];
    if ([date isKindOfClass:[NSDate class]] == NO) {
        date = self.originBaseDate;
    }
    NSDate *expiration = [date dateByAddingTimeInterval:interval.floatValue];
    return ([[NSDate date] compare:expiration] == NSOrderedAscending);
}

#pragma mark - UITableViewDelegate

// Start a purchase when the user taps a row
- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SKProduct *product = (SKProduct *)_products[indexPath.row];
    // Attempt to purchase the tapped product
    [_storeManager buy:product];
}

#pragma mark -
- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) dealloc {
}

@end
