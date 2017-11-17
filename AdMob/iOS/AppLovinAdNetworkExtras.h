//
//  AppLovinAdNetworkExtras.h
//
//  Created by Josh Gleeson on 11/16/17.
//  Copyright © 2017 Applovin. All rights reserved.
//

@import GoogleMobileAds;

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAnnotations.h"
#endif

AL_ASSUME_NONNULL_BEGIN

@interface AppLovinAdNetworkExtras : NSObject<GADAdNetworkExtras>

// AppLovin Zone ID to be used for rewarded video ad requests.
@property (nonatomic, copy, alnullable) NSString *zoneIdentifier;

@end

AL_ASSUME_NONNULL_END
