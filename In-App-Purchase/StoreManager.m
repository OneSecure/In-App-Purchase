/*
 File: StoreManager.m
 Abstract: Retrieves product information from the App Store using SKRequestDelegate, SKProductsRequestDelegate,SKProductsResponse, and
 SKProductsRequest. Notifies its observer with a list of products available for sale along with a list of invalid product
 identifiers. Logs an error message if the product request failed.
 
 Version: 1.0
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import <StoreKit/StoreKit.h>
#import "StoreManager.h"

@interface StoreManager()<SKProductsRequestDelegate, SKPaymentTransactionObserver>
@end

@implementation StoreManager {
    SKProductsResponseCallback _responseCallback;
    SKProductsResponse *_response;
    __weak SKPaymentQueue *_paymentQueue;
}

+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    static StoreManager * storeManagerSharedInstance;
    
    dispatch_once(&onceToken, ^{
        storeManagerSharedInstance = [[StoreManager alloc] init];
    });
    return storeManagerSharedInstance;
}

- (instancetype) init {
    if ((self = [super init])) {
        // Attach an observer to the payment queue
        _paymentQueue = [SKPaymentQueue defaultQueue];
        [_paymentQueue addTransactionObserver:self];
    }
    return self;
}

- (void) dealloc {
    // Remove the observer
    [_paymentQueue removeTransactionObserver:self];
}

#pragma mark -
#pragma mark Request information

// Fetch information about your products from the App Store
- (void) fetchProductsForIds:(NSArray<NSString*> *)productIds
            responseCallback:(SKProductsResponseCallback)responseCallback
{
    // Create a product request object and initialize it with our product identifiers
    NSSet *ids = [NSSet setWithArray:productIds];
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:ids];
    request.delegate = self;
    
    // Send the request to the App Store
    [request start];
    
    _responseCallback = responseCallback;
}

#pragma mark - SKProductsRequestDelegate & SKRequestDelegate

// Used to get the App Store's response to your request and notifies your observer
- (void) productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    _response = response;
}

- (void) requestDidFinish:(SKRequest *)request {
    [self doResponseCallback:nil];
}

// Called when the product request failed.
- (void) request:(SKRequest *)request didFailWithError:(NSError *)error {
    [self doResponseCallback:error];
}

- (void) doResponseCallback:(NSError*)error {
    if (_responseCallback) {
        _responseCallback(_response.products, error);
        _responseCallback = nil;
    }
    _response = nil;
}

#pragma mark - Make a purchase

- (BOOL) canMakePayments {
    return [SKPaymentQueue canMakePayments];
}

// Create and add a payment request to the payment queue
- (void) buy:(SKProduct *)product {
    SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
    [_paymentQueue addPayment:payment];
}

#pragma mark - Restore purchases

- (void) restore {
    [_paymentQueue restoreCompletedTransactions];
}

#pragma mark - SKPaymentTransactionObserver methods

// Called when there are trasactions in the payment queue
- (void) paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    PurchaseStatus status;
    for(SKPaymentTransaction * transaction in transactions) {
        switch (transaction.transactionState ) {
            case SKPaymentTransactionStatePurchasing:
                break;
                
            case SKPaymentTransactionStatePurchased:
                // The purchase was successful
                self.purchasedID = transaction.payment.productIdentifier;
                //[[NSString alloc]initWithData:transaction.transactionReceipt encoding:NSUTF8StringEncoding];
                
                NSLog(@"Deliver content for %@", transaction.payment.productIdentifier);
                // Check whether the purchased product has content hosted with Apple.
                status = (transaction.downloads && transaction.downloads.count > 0) ? IAPDownloadStarted : IAPPurchaseSucceeded;
                [self completeTransaction:transaction status:status];
                break;
                
            case SKPaymentTransactionStateRestored:
                // There are restored products
                self.purchasedID = transaction.payment.productIdentifier;
                
                NSLog(@"Deliver content for %@",transaction.payment.productIdentifier);
                // Send a IAPDownloadStarted notification if it has
                status = (transaction.downloads && transaction.downloads.count > 0) ? IAPDownloadStarted : IAPRestoredSucceeded;
                [self completeTransaction:transaction status:status];
                break;
                
            case SKPaymentTransactionStateFailed:
                // The transaction failed
                self.message = [NSString stringWithFormat:@"Purchase of %@ failed.",transaction.payment.productIdentifier];
                [self completeTransaction:transaction status:IAPPurchaseFailed];
                break;
                
            default:
                break;
        }
    }
}

// Called when the payment queue has downloaded content
- (void) paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray<SKDownload *> *)downloads {
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    for (SKDownload* download in downloads) {
#if TARGET_OS_IOS
        SKDownloadState state = (download.downloadState);
#else
        SKDownloadState state = (download.state);
#endif
        switch (state)
        {
            case SKDownloadStateActive:
                // The content is being downloaded. Let's provide a download progress to the user
                self.purchasedID = download.transaction.payment.productIdentifier;
                self.downloadProgress = download.progress*100;
                if (_purchaseNotification) {
                    _purchaseNotification(self, download, IAPDownloadInProgress);
                }
                break;
                
            case SKDownloadStateCancelled:
                // StoreKit saves your downloaded content in the Caches directory. Let's remove it
                // before finishing the transaction.
                [defaultManager removeItemAtURL:download.contentURL error:nil];
                [self finishDownloadTransaction:download.transaction];
                break;
                
            case SKDownloadStateFailed:
                // If a download fails, remove it from the Caches, then finish the transaction.
                // It is recommended to retry downloading the content in this case.
                [defaultManager removeItemAtURL:download.contentURL error:nil];
                [self finishDownloadTransaction:download.transaction];
                break;
                
            case SKDownloadStatePaused:
                NSLog(@"Download was paused");
                break;
                
            case SKDownloadStateFinished:
                // Download is complete. StoreKit saves the downloaded content in the Caches directory.
                NSLog(@"Location of downloaded file %@",download.contentURL);
                [self finishDownloadTransaction:download.transaction];
                break;
                
            case SKDownloadStateWaiting:
                NSLog(@"Download Waiting");
                [_paymentQueue startDownloads:@[download]];
                break;
                
            default:
                break;
        }
    }
}

// Logs all transactions that have been removed from the payment queue
- (void) paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    for(SKPaymentTransaction * transaction in transactions) {
        NSLog(@"%@ was removed from the payment queue.", transaction.payment.productIdentifier);
    }
}

// Called when an error occur while restoring purchases. Notify the user about the error.
- (void) paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    if (error.code != SKErrorPaymentCancelled) {
        self.message = [error localizedDescription];
        if (_purchaseNotification) {
            _purchaseNotification(self, error, IAPRestoredFailed);
        }
    }
}

// Called when all restorable transactions have been processed by the payment queue
- (void) paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    NSLog(@"All restorable transactions have been processed by the payment queue.");
}

- (BOOL) paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product {
    return YES;
}

- (void) paymentQueueDidChangeStorefront:(SKPaymentQueue *)queue {
}

#pragma mark - Complete transaction

// Notify the user about the purchase process. Start the download process if status is
// IAPDownloadStarted. Finish all transactions, otherwise.
- (void) completeTransaction:(SKPaymentTransaction *)transaction status:(PurchaseStatus)status {
    // Do not send any notifications when the user cancels the purchase
    if (transaction.error.code != SKErrorPaymentCancelled) {
        // Notify the user
        if (_purchaseNotification) {
            _purchaseNotification(self, transaction, status);
        }
    }
    
    if (status == IAPDownloadStarted) {
        // The purchased product is a hosted one, let's download its content
        [_paymentQueue startDownloads:transaction.downloads];
    } else {
        // Remove the transaction from the queue for purchased and restored statuses
        [_paymentQueue finishTransaction:transaction];
    }
}

#pragma mark - Handle download transaction

- (void) finishDownloadTransaction:(SKPaymentTransaction*)transaction {
    //allAssetsDownloaded indicates whether all content associated with the transaction were downloaded.
    BOOL allAssetsDownloaded = YES;
    
    // A download is complete if its state is SKDownloadStateCancelled, SKDownloadStateFailed, or SKDownloadStateFinished
    // and pending, otherwise. We finish a transaction if and only if all its associated downloads are complete.
    // For the SKDownloadStateFailed case, it is recommended to try downloading the content again before finishing the transaction.
    for (SKDownload* download in transaction.downloads) {
#if TARGET_OS_IOS
        SKDownloadState downloadState = download.downloadState;
#else
        SKDownloadState downloadState = download.state;
#endif
        if (downloadState != SKDownloadStateCancelled &&
            downloadState != SKDownloadStateFailed &&
            downloadState != SKDownloadStateFinished )
        {
            //Let's break. We found an ongoing download. Therefore, there are still pending downloads.
            allAssetsDownloaded = NO;
            break;
        }
    }
    
    // Finish the transaction and post a IAPDownloadSucceeded notification if all downloads are complete
    if (allAssetsDownloaded) {
        if (_purchaseNotification) {
            _purchaseNotification(self, transaction, IAPDownloadSucceeded);
        }
        [_paymentQueue finishTransaction:transaction];
    }
}

@end
