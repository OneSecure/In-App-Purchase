# In-App-Purchase

In-App Purchase wrapper for Apple iOS App Store

Usage

```
- (void) onPurchaseProducts:(id)sender {
    if ([JailbreakDetectTool detectCurrentDeviceIsJailbroken]) {
        // warning dialog
        return;
    }

    ProductsPurchaseController *purchaseCtrl =
    [[ProductsPurchaseController alloc] initWithProductIDs:_appSettings.productsPurchased
                                                completion:^(NSDictionary *productsPurchased)
     {
        self->_appSettings.productsPurchased = productsPurchased;
        
        _stockedSettings.expiredDate = self->_appSettings.softwareExpiredDate;
        if (self->_appSettings.softwarePurchased) {
            // ...
        }
        [self updateEnabledControls];
    }];
    [purchaseCtrl setFirstBuyCallback:^{
        // ...
    }];
    purchaseCtrl.productCollection = _appSettings.productCollection;
    purchaseCtrl.originBaseDate = _appSettings.originBaseDate;
    [self.navigationController pushViewController:purchaseCtrl animated:YES];
}
```

Automatical restore

```
- (void) purchaseRestoreThread {
    if (_appSettings.autoRestorePurchases == NO) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        StoreManager *_storeManager = [StoreManager sharedInstance];
        _storeManager.purchaseNotification = ^(StoreManager *observer, id context, PurchaseStatus status) {
            [self onPurchaseNotification:observer context:context status:status];
        };
        if ([_storeManager canMakePayments]) {
            [_storeManager restore];
        }
    });
}

- (void) onPurchaseNotification:(StoreManager *)observer context:(id)context status:(PurchaseStatus)status {
    SKPaymentTransaction *transaction = (SKPaymentTransaction *)context;
    switch (status) {
        case IAPRestoredSucceeded:
            if ([transaction isKindOfClass:SKPaymentTransaction.class]) {
                NSString *purchasedID = transaction.payment.productIdentifier;
                NSDate *date = transaction.transactionDate;
                [self purchaseChanged:purchasedID date:date firstBuy:NO];
            }
            break;
        default:
            break;
    }
}

- (void) purchaseChanged:(NSString *)pID date:(NSDate*)date firstBuy:(BOOL)firstBuy {
    NSMutableDictionary<NSString *, NSDate *> *productsPurchased =
    [NSMutableDictionary dictionaryWithDictionary:_appSettings.productsPurchased];

    NSDate *oldDate = productsPurchased[pID];
    if ([oldDate isKindOfClass:[NSDate class]] == NO) {
        oldDate = _appSettings.originBaseDate;
    }
    if ([oldDate compare:date] == NSOrderedAscending) {
        productsPurchased[pID] = date;
    }
    
    _appSettings.productsPurchased = productsPurchased;
}
```
