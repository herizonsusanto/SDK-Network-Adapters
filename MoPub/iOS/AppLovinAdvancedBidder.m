//
//  AppLovinAdvancedBidder.m
//  SDK Network Adapters Test App
//
//  Created by Thomas So on 5/22/18.
//  Copyright © 2018 AppLovin Corp. All rights reserved.
//

#import "AppLovinAdvancedBidder.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALSdk.h"
#endif

@implementation AppLovinAdvancedBidder

- (NSString *)creativeNetworkName
{
    return @"applovin";
}

- (NSString *)token
{
    return [ALSdk shared].adService.bidToken;
}

@end
