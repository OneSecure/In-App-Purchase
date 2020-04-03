//
//  JailbreakDetectTool.h
//  OneSecure
//
//  Created by OneSecure on 2020/3/25.
//  Copyright © 2020 OneSecure. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JailbreakDetectTool : NSObject
+ (BOOL) detectCurrentDeviceIsJailbroken;
@end

NS_ASSUME_NONNULL_END
