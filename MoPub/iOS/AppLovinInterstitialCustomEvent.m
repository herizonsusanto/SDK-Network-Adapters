//
//  AppLovinInterstitialCustomEvent.m
//
//
//  Created by Thomas So on 5/21/17.
//
//

#import "AppLovinInterstitialCustomEvent.h"
#import "MPError.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALInterstitialAd.h"
#endif

@interface AppLovinInterstitialCustomEvent() <ALAdLoadDelegate, ALAdDisplayDelegate, ALAdVideoPlaybackDelegate>

@property (nonatomic, strong) ALInterstitialAd *interstitialAd;
@property (nonatomic, strong) ALAd *loadedAd;

@end

@implementation AppLovinInterstitialCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

#pragma mark - MPInterstitialCustomEvent Overridden Methods

- (void)requestInterstitialWithCustomEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin interstitial with info: %@", info];
    
    [[ALSdk shared] setPluginVersion: @"MoPub-2.2"];
    
    ALAdService *adService = [ALSdk shared].adService;
    
    // Zones support is available on AppLovin SDK 4.5.0 and higher
    NSString *zoneIdentifier = info[@"zone_id"];
    if ( [ALSdk versionCode] >= 450 && zoneIdentifier.length > 0 )
    {
        [adService performSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)
                        withObject: zoneIdentifier
                        withObject: self];
    }
    else
    {
        [adService loadNextAd: [ALAdSize sizeInterstitial] andNotify: self];
    }
}

- (void)showInterstitialFromRootViewController:(UIViewController *)rootViewController
{
    if ( self.loadedAd )
    {
        self.interstitialAd = [[ALInterstitialAd alloc] initWithSdk: [ALSdk shared]];
        self.interstitialAd.adDisplayDelegate = self;
        self.interstitialAd.adVideoPlaybackDelegate = self;
        [self.interstitialAd showOver: rootViewController.view.window andRender: self.loadedAd];
    }
    else
    {
        [self log: @"Failed to show an AppLovin interstitial before one was loaded"];
        
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adaptor requested to display an interstitial before one was loaded"}];
        
        [self.delegate interstitialCustomEvent: self didFailToLoadAdWithError: error];
    }
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Interstitial did load ad: %@", ad.adIdNumber];
    
    self.loadedAd = ad;
    
    [self.delegate interstitialCustomEvent: self didLoadAd: ad];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Interstitial failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                         code: [self toMoPubErrorCode: code]
                                     userInfo: nil];
    [self.delegate interstitialCustomEvent: self didFailToLoadAdWithError: error];
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Interstitial displayed"];
    
    [self.delegate interstitialCustomEventWillAppear: self];
    [self.delegate interstitialCustomEventDidAppear: self];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Interstitial dismissed"];
    
    [self.delegate interstitialCustomEventWillDisappear: self];
    [self.delegate interstitialCustomEventDidDisappear: self];
    
    self.interstitialAd = nil;
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Interstitial clicked"];
    
    [self.delegate interstitialCustomEventDidReceiveTapEvent: self];
    [self.delegate interstitialCustomEventWillLeaveApplication: self];
}

#pragma mark - Video Playback Delegate

- (void)videoPlaybackBeganInAd:(ALAd *)ad
{
    [self log: @"Interstitial video playback began"];
}

- (void)videoPlaybackEndedInAd:(ALAd *)ad atPlaybackPercent:(NSNumber *)percentPlayed fullyWatched:(BOOL)wasFullyWatched
{
    [self log: @"Interstitial video playback ended at playback percent: %lu", percentPlayed.unsignedIntegerValue];
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
        
        NSLog(@"AppLovinInterstitialCustomEvent: %@", message);
    }
}

- (MOPUBErrorCode)toMoPubErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return MOPUBErrorAdapterHasNoInventory;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return MOPUBErrorNetworkTimedOut;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return MOPUBErrorServerError;
    }
    else
    {
        return MOPUBErrorUnknown;
    }
}

@end
