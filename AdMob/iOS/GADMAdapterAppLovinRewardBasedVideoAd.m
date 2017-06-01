
//
//  GADMAdapterAppLovinRewardBasedVideoAd.m
//
//
//  Created by Thomas So on 5/20/17.
//
//

#import "GADMAdapterAppLovinRewardBasedVideoAd.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALSdk.h"
    #import "ALIncentivizedInterstitialAd.h"
#endif

@interface GADMAdapterAppLovinRewardBasedVideoAd() <ALAdLoadDelegate, ALAdDisplayDelegate, ALAdVideoPlaybackDelegate, ALAdRewardDelegate>

@property (nonatomic, strong) ALIncentivizedInterstitialAd *incent;

@property (nonatomic, assign) BOOL fullyWatched;
@property (nonatomic, strong) GADAdReward *reward;

@property (nonatomic,   weak) id<GADMRewardBasedVideoAdNetworkConnector> connector;

@end

@implementation GADMAdapterAppLovinRewardBasedVideoAd

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALAdMobMediationErrorDomain = @"com.applovin.sdk.mediation.admob.errorDomain";
static NSString *const kALAdMobAdapterVersion = @"AdMob-2.0";

#pragma mark - GADMRewardBasedVideoAdNetworkAdapter Protocol

+ (NSString *)adapterVersion
{
    return kALAdMobAdapterVersion;
}

+ (Class<GADAdNetworkExtras>)networkExtrasClass
{
    return nil;
}

- (instancetype)initWithRewardBasedVideoAdNetworkConnector:(id<GADMRewardBasedVideoAdNetworkConnector>)connector
{
    self = [super init];
    if ( self )
    {
        self.connector = connector;
    }
    return self;
}

- (void)setUp
{
    [[ALSdk shared] initializeSdk];
    [[ALSdk shared] setPluginVersion: kALAdMobAdapterVersion];
    
    [self.connector adapterDidSetUpRewardBasedVideoAd: self];
}

- (void)requestRewardBasedVideoAd
{
    [self log: @"Requesting AppLovin rewarded video"];
    
    NSString *adapterVersion = [[self class] adapterVersion];
    [[ALSdk shared] setPluginVersion: adapterVersion];
    
    if ( self.incent.readyForDisplay )
    {
        [self.connector adapterDidReceiveRewardBasedVideoAd: self];
    }
    else
    {
        [self.incent preloadAndNotify: self];
    }
}

- (void)presentRewardBasedVideoAdWithRootViewController:(UIViewController *)viewController
{
    if ( self.incent.readyForDisplay )
    {
        self.reward = nil;
        self.fullyWatched = NO;
        
        [self.incent showAndNotify: self];
    }
    else
    {
        [self log: @"Failed to show an AppLovin rewarded video before one was loaded"];
        
        NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adaptor requested to display a rewarded video before one was loaded"}];
        
        [self.connector adapter: self didFailToSetUpRewardBasedVideoAdWithError: error];
    }
}

- (void)stopBeingDelegate
{
    self.connector = nil;
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Rewarded video did load ad: %@", ad.adIdNumber];
    [self.connector adapterDidReceiveRewardBasedVideoAd: self];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Rewarded video failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                         code: [self toAdMobErrorCode: code]
                                     userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adaptor requested to display a rewarded video before one was loaded"}];
    [self.connector adapter: self didFailToLoadRewardBasedVideoAdwithError: error];
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Rewarded video displayed"];
    [self.connector adapterDidOpenRewardBasedVideoAd: self];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Rewarded video dismissed"];
    
    if ( self.fullyWatched && self.reward )
    {
        [self.connector adapter: self didRewardUserWithReward: self.reward];
    }
    
    [self.connector adapterDidCloseRewardBasedVideoAd: self];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Rewarded video clicked"];
    
    [self.connector adapterDidGetAdClick: self];
    [self.connector adapterWillLeaveApplication: self];
}

#pragma mark - Video Playback Delegate

- (void)videoPlaybackBeganInAd:(ALAd *)ad
{
    [self log: @"Interstitial video playback began"];
    [self.connector adapterDidStartPlayingRewardBasedVideoAd: self];
}

- (void)videoPlaybackEndedInAd:(ALAd *)ad atPlaybackPercent:(NSNumber *)percentPlayed fullyWatched:(BOOL)wasFullyWatched
{
    [self log: @"Interstitial video playback ended at playback percent: %lu", percentPlayed.unsignedIntegerValue];
    
    self.fullyWatched = wasFullyWatched;
}

#pragma mark - Reward Delegate

- (void)rewardValidationRequestForAd:(ALAd *)ad didExceedQuotaWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request for ad did exceed quota with response: %@", response];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didFailWithError:(NSInteger)responseCode
{
    [self log: @"Rewarded video validation request for ad failed with error code: %ld", responseCode];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad wasRejectedWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request was rejected with response: %@", response];
}

- (void)userDeclinedToViewAd:(ALAd *)ad
{
    [self log: @"User declined to view rewarded video"];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didSucceedWithResponse:(NSDictionary *)response
{
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString: response[@"amount"]];
    NSString *currency = response[@"currency"];
    
    [self log: @"Rewarded %@ %@", amount, currency];
    
    self.reward = [[GADAdReward alloc] initWithRewardType: currency rewardAmount: amount];
}

#pragma mark - Incentivized Interstitial

- (ALIncentivizedInterstitialAd *)incent
{
    if ( !_incent )
    {
        _incent = [[ALIncentivizedInterstitialAd alloc] initWithSdk: [ALSdk shared]];
        _incent.adVideoPlaybackDelegate = self;
        _incent.adDisplayDelegate = self;
    }
    
    return _incent;
}

#pragma mark - Utility Methods

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinCustomEventRewardedVideo: %@", message);
    }
}

- (GADErrorCode)toAdMobErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return kGADErrorMediationNoFill;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return kGADErrorTimeout;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return kGADErrorReceivedInvalidResponse;
    }
    else if ( appLovinErrorCode == kALErrorCodeUnableToRenderAd )
    {
        return kGADErrorServerError;
    }
    else
    {
        return kGADErrorInternalError;
    }
}

@end
