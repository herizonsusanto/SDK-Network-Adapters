//
//  GADMAppLovinExtras.h
//  NewAdMobSDK
//
//  Created by Josh Gleeson on 11/16/17.
//  Copyright © 2017 Applovin. All rights reserved.
//

@import GoogleMobileAds;

@interface GADMAppLovinExtras : NSObject<GADAdNetworkExtras>
// Optional settings
// AppLovin Zone ID to be used for rewarded video ad requests
@property (nonatomic, strong) NSString *zoneID;
@end
