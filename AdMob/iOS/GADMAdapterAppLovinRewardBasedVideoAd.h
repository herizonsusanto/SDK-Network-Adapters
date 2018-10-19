//
//  GADMAdapterAppLovinRewardBasedVideoAd.h
//
//
//  Created by Thomas So on 5/20/17.
//
//

@import GoogleMobileAds;

NS_ASSUME_NONNULL_BEGIN

@interface GADMAdapterAppLovinRewardBasedVideoAd : NSObject <GADMRewardBasedVideoAdNetworkAdapter>

@end

@interface AppLovinAdNetworkExtras : NSObject<GADAdNetworkExtras>

// AppLovin Zone ID to be used for rewarded video ad requests.
@property (nonatomic, copy, nullable) NSString *zoneIdentifier;

@end

NS_ASSUME_NONNULL_END
