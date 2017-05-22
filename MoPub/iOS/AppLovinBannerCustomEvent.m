//
//  AppLovinBannerCustomEvent.m
//
//
//  Created by Thomas So on 3/6/17.
//
//

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
#endif

#import "AppLovinBannerCustomEvent.h"
#import "MPConstants.h"

@interface AppLovinBannerCustomEvent()<ALAdLoadDelegate, ALAdDisplayDelegate>
@end

@implementation AppLovinBannerCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

#pragma mark - MPBannerCustomEvent Overridden Methods

- (void)requestAdWithSize:(CGSize)size customEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin banner of size %@ with info: %@", NSStringFromCGSize(size), info];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *adSize = [self appLovinAdSizeFromRequestedSize: size];
    if ( adSize )
    {
        [[ALSdk shared] setPluginVersion: @"MoPubBanner-1.0"];
        
        ALAdView *adView = [[ALAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height) size: adSize sdk: [ALSdk shared]];
        adView.adLoadDelegate = self;
        adView.adDisplayDelegate = self;
        [adView loadNextAd];
        
        [self.delegate bannerCustomEvent: self didLoadAd: adView];
    }
    else
    {
        [self log: @"Failed to create an AppLovin banner with invalid size"];
        
        NSString *failureReason = [NSString stringWithFormat: @"Adaptor requested to display a banner with invalid size: %@.", NSStringFromCGSize(size)];
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : failureReason}];
        
        [self.delegate bannerCustomEvent: self didFailToLoadAdWithError: error];
    }
}

- (BOOL)enableAutomaticImpressionAndClickTracking
{
    return NO;
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Banner did load ad: %@", ad.adIdNumber];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain code: code userInfo: nil];
    [self.delegate bannerCustomEvent: self didFailToLoadAdWithError: error];
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Banner displayed"];
    [self.delegate trackImpression];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Banner dismissed"];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Banner clicked"];
    
    [self.delegate trackClick];
    [self.delegate bannerCustomEventWillLeaveApplication: self];
}

#pragma mark - Utility Methods

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(CGSize)size
{
    if ( CGSizeEqualToSize(size, MOPUB_BANNER_SIZE) )
    {
        return [ALAdSize sizeBanner];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_MEDIUM_RECT_SIZE) )
    {
        return [ALAdSize sizeMRec];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_LEADERBOARD_SIZE) )
    {
        return [ALAdSize sizeLeader];
    }
    
    return nil;
}

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinBannerCustomEvent: %@", message);
    }
}

@end
