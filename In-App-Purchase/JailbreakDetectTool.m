//
//  JailbreakDetectTool.m
//  OneSecure
//
//  Created by OneSecure on 2020/3/25.
//  Copyright © 2020 OneSecure. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "JailbreakDetectTool.h"

#define ARRAY_SIZE(a) sizeof(a)/sizeof(a[0])

@implementation JailbreakDetectTool

// 四种检查是否越狱的方法, 只要命中一个, 就说明已经越狱.
+ (BOOL) detectCurrentDeviceIsJailbroken {
    BOOL result =  YES;
    do {
        if ([self detectJailBreakByJailBreakFileExisted]) {
            break;
        }
        if ([self detectJailBreakByAppPathExisted]) {
            break;
        }
        if ([self detectJailBreakByEnvironmentExisted]) {
            break;
        }
        if ([self detectJailBreakByCydiaPathExisted]) {
            break;
        }
        result = NO;
    } while (NO);
    return result;
}

/**
 * 判定常见的越狱文件
 * 这个表可以尽可能的列出来，然后判定是否存在，只要有存在的就可以认为机器是越狱了。
 */
const char *jailbreak_tool_pathes[] = {
    "/Applications/Cydia.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/bin/bash",
    "/usr/sbin/sshd",
    "/etc/apt"
};

+ (BOOL) detectJailBreakByJailBreakFileExisted {
    for (int i = 0; i<ARRAY_SIZE(jailbreak_tool_pathes); i++) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:jailbreak_tool_pathes[i]]]) {
            return YES;
        }
    }
    return NO;
}

/**
 * 判断cydia的URL scheme.
 */
+ (BOOL) detectJailBreakByCydiaPathExisted {
#if 1
    Class appClass = NSClassFromString(@"UIApplication");
    if (appClass) {
        UIApplication *app = [appClass performSelector:@selector(sharedApplication)];
        if (app) {
            IMP imp = [app methodForSelector:@selector(canOpenURL:)];
            BOOL (*func)(id, SEL, id) = (void *)imp;
            return func(app, @selector(canOpenURL:), [NSURL URLWithString:@"cydia://"]);
        }
    }
    return NO;
#else
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://"]];
#endif
}

/**
 * 读取系统所有应用的名称.
 * 这个是利用不越狱的机器没有这个权限来判定的。
 */
#define USER_APP_PATH                 @"/User/Applications/"
+ (BOOL) detectJailBreakByAppPathExisted {
    if ([[NSFileManager defaultManager] fileExistsAtPath:USER_APP_PATH]) {
        NSArray *applist = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:USER_APP_PATH error:nil];
        NSLog(@"applist = %@", applist);
        return YES;
    }
    return NO;
}

/**
 * 这个DYLD_INSERT_LIBRARIES环境变量，在非越狱的机器上应该是空，越狱的机器上基本都会有Library/MobileSubstrate/MobileSubstrate.dylib.
 */
char* printEnv(void) {
    return getenv("DYLD_INSERT_LIBRARIES");
}

+ (BOOL) detectJailBreakByEnvironmentExisted {
    if (printEnv()) {
        return YES;
    }
    return NO;
}

@end
