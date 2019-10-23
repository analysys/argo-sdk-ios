//
//  ANSPageAutoTrack.m
//  AnalysysAgent
//
//  Created by SoDo on 2018/12/10.
//  Copyright © 2018 analysys. All rights reserved.
//

#import "ANSPageAutoTrack.h"

#import <UIKit/UIKit.h>

#import "ANSSwizzler.h"
#import "ANSSession.h"
#import "AnalysysSDK.h"
#import "AnalysysAgent.h"
#import "NSThread+ANSHelper.h"
#import "ANSConst+private.h"
#import "ANSControllerUtils.h"

@interface ANSPageAutoTrack () {
    NSString *_referrerPageUrl; // 来源页标识
}

@property (nonatomic, strong) NSMutableDictionary *lastVisitPageInfo; // 最后访问的页面信息

@end

@implementation ANSPageAutoTrack

+ (instancetype)shareInstance {
    static id singleInstance = nil;
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        singleInstance = [[self alloc] init] ;
    });
    return singleInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastVisitPageInfo = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)autoTrack {
    [NSThread AnsRunOnMainThread:^{
        void (^viewDidAppearBlock)(id, SEL, id) = ^(id obj, SEL sel, NSNumber *num) {
            UIViewController *controller = (UIViewController *)obj;
            [[ANSPageAutoTrack shareInstance] viewDidAppear:controller];
        };
        void (^viewWillDisappearBlock)(id, SEL, id) = ^(id obj, SEL sel, NSNumber *num) {
            UIViewController *controller = (UIViewController *)obj;
            [[ANSPageAutoTrack shareInstance] viewWillDisappear:controller];
        };

        [ANSSwizzler swizzleSelector:@selector(viewDidAppear:) onClass:[UIViewController class] withBlock:viewDidAppearBlock named:@"ANSViewDidAppear"];
        [ANSSwizzler swizzleSelector:@selector(viewWillDisappear:) onClass:[UIViewController class] withBlock:viewWillDisappearBlock named:@"ANSViewDidDisappear"];
    }];
}

+ (void)autoTrackLastVisitPage {
    NSDictionary *pageInfo = [ANSPageAutoTrack shareInstance].lastVisitPageInfo;
    if (pageInfo.allKeys.count) {
        [[AnalysysSDK sharedManager] autoPageView:nil properties:pageInfo];
    }
}

#pragma mark - private method

/** 是否可以进行跟踪 */
- (BOOL)canTrackViewController:(UIViewController *)controller {
    Class vClass = [controller class];
    if (!vClass) {
        return NO;
    }
    if (![[AnalysysSDK sharedManager] isViewAutoTrack]) {
        return NO;
    }
    NSString *className = NSStringFromClass(vClass);
    if ([[AnalysysSDK sharedManager] isIgnoreTrackWithClassName:className]) {
        return NO;
    }
//    if ([controller childViewControllers].count > 0) {
//        return NO;
//    }
    if ([[ANSControllerUtils systemBuildInClasses] containsObject:className]) {
        return NO;
    }
    if ([controller isKindOfClass:[UINavigationController class]] ||
        [controller isKindOfClass:[UITabBarController class]]) {
        return NO;
    }
    return YES;
}

/** 页面显示 */
- (void)viewDidAppear:(UIViewController *)controller {
    NSString *className = NSStringFromClass([controller class]);
    NSString *controllerTitle = [ANSControllerUtils titleFromViewController:controller];
    
    [[AnalysysSDK sharedManager] dispatchOnSerialQueue:^{
        //  先生成session 后记录时间
        [[ANSSession shareInstance] generateSessionId];
        [[ANSSession shareInstance] updatePageAppearDate];
        
        if ([self canTrackViewController:controller]) {
            [self.lastVisitPageInfo removeAllObjects];
            [self.lastVisitPageInfo setValue:controllerTitle forKey:ANSPageTitle];
            [self.lastVisitPageInfo setValue:className forKey:ANSPageUrl];
            
            [self autoTrackViewController:controller];
        }
    }];
}

/** 页面消失 */
- (void)viewWillDisappear:(UIViewController *)controller {
    [[AnalysysSDK sharedManager] dispatchOnSerialQueue:^{
        [[ANSSession shareInstance] updatePageDisappearDate];
    }];
}

/** 自定义参数 */
- (void)autoTrackViewController:(UIViewController *)controller {
    NSMutableDictionary *pageProperties = [NSMutableDictionary dictionary];
    NSDictionary *SDKPageTrackProperty = [self.lastVisitPageInfo copy];
    [pageProperties addEntriesFromDictionary:SDKPageTrackProperty];
    
    if (_referrerPageUrl) {
        [pageProperties setValue:_referrerPageUrl forKey:ANSPageReferrerUrl];
    }
    
    NSString *userPageUrl;
    if ([controller conformsToProtocol:@protocol(ANSAutoPageTracker)]) {
        id<ANSAutoPageTracker> vc = (id<ANSAutoPageTracker> )controller;
        if ([controller respondsToSelector:@selector(registerPageProperties)]) {
            NSDictionary *userPageProperties = [vc registerPageProperties];
            if (userPageProperties && [userPageProperties isKindOfClass:NSDictionary.class]) {
                [pageProperties addEntriesFromDictionary:userPageProperties];
            }
        }
        if ([controller respondsToSelector:@selector(registerPageUrl)]) {
            NSString *pageUrl = [vc registerPageUrl];
            if (pageUrl && [pageUrl isKindOfClass:NSString.class]) {
                [pageProperties setValue:pageUrl forKey:ANSPageUrl];
                userPageUrl = pageUrl;
                if (_referrerPageUrl) {
                    [pageProperties setValue:_referrerPageUrl forKey:ANSPageReferrerUrl];
                }
                _referrerPageUrl = pageUrl;
            }
        }
    }
    //  取自动采集
    if (!userPageUrl) {
        _referrerPageUrl = NSStringFromClass([controller class]);
    }
    
    [[AnalysysSDK sharedManager] autoPageView:nil properties:pageProperties];
}

@end