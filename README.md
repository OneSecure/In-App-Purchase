# In-App-Purchase

In-App Purchase wrapper for Apple iOS App Store

usage
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
