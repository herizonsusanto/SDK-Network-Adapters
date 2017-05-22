//
//  AppLovinNativeCustomEvent.m
//
//
//  Created by Thomas So on 5/21/17.
//
//

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALSdk.h"
#endif

#import "AppLovinNativeCustomEvent.h"
#import "MPNativeAdError.h"
#import "MPNativeAd.h"
#import "MPNativeAdAdapter.h"
#import "MPNativeAdConstants.h"

@interface AppLovinNativeAdapter : NSObject<MPNativeAdAdapter, ALPostbackDelegate>

/**
 * The underlying MP dictionary representing the contents of the native ad.
 */
@property (nonatomic, readwrite) NSDictionary *properties;

@property (nonatomic, strong) ALNativeAd *nativeAd;


- (instancetype)initWithNativeAd:(ALNativeAd *)ad;

@end

@interface AppLovinNativeCustomEvent()<ALNativeAdLoadDelegate>
@end

@implementation AppLovinNativeCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

#pragma mark - MPNativeCustomEvent Overridden Methods

- (void)requestAdWithCustomEventInfo:(NSDictionary *)info
{
    [[self class] log: @"Requesting AppLovin native ad with info: %@", info];
    
    [[ALSdk shared] setPluginVersion: @"MoPubNative-1.0"];
    
    ALNativeAdService *nativeAdService = [ALSdk shared].nativeAdService;
    [nativeAdService loadNativeAdGroupOfCount: 1 andNotify: self];
}

#pragma mark - Ad Load Delegate

- (void)nativeAdService:(ALNativeAdService *)service didLoadAds:(NSArray al_of_type(<ALNativeAd *>) *)ads
{
    ALNativeAd *nativeAd = [ads firstObject];
    
    [[self class] log: @"Native ad did load ad: %@", nativeAd.adIdNumber];
    
    NSMutableArray al_of_type(<NSURL *>) *imageURLs = [NSMutableArray arrayWithCapacity: 2];
    
    if ( nativeAd.iconURL )
    {
        [imageURLs addObject: nativeAd.iconURL];
    }
    
    if ( nativeAd.imageURL )
    {
        [imageURLs addObject: nativeAd.imageURL];
    }
    
    [self precacheImagesWithURLs: imageURLs completionBlock:^(NSArray al_of_type(<NSError *>) *errors)
     {
         if ( errors.count == 0  )
         {
             [[self class] log: @"Native ad done precaching"];
             
             AppLovinNativeAdapter *adapter = [[AppLovinNativeAdapter alloc] initWithNativeAd: nativeAd];
             MPNativeAd *nativeAd = [[MPNativeAd alloc] initWithAdAdapter: adapter];
             
             [self.delegate nativeCustomEvent: self didLoadAd: nativeAd];
             
             [adapter willAttachToView: nil];
             [adapter displayContentForURL: nil rootViewController: [UIApplication sharedApplication].keyWindow.rootViewController];
         }
         else
         {
             [[self class] log: @"Native ad failed to precache images with error(s)", errors];
             
             NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                                  code: MPNativeAdErrorImageDownloadFailed
                                              userInfo: nil];
             
             [self.delegate nativeCustomEvent: self didFailToLoadAdWithError: error];
         }
     }];
}

- (void)nativeAdService:(ALNativeAdService *)service didFailToLoadAdsWithError:(NSInteger)code
{
    [[self class] log: @"Native ad video failed to load with error: %d", code];
    
    // TODO: Translate between AppLovin <-> MoPub error codes
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain code: MPNativeAdErrorNoInventory userInfo: nil];
    [self.delegate nativeCustomEvent:self didFailToLoadAdWithError: error];
}

#pragma mark - Utility Methods

+ (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinNativeCustomEvent: %@", message);
    }
}

@end

@implementation AppLovinNativeAdapter
@synthesize defaultActionURL;

#pragma mark - Initialization

- (instancetype)initWithNativeAd:(ALNativeAd *)ad
{
    self = [super init];
    if ( self )
    {
        self.nativeAd = ad;
        
        NSMutableDictionary al_of_type(<NSString *, NSString *>) *properties = [NSMutableDictionary dictionary];
        properties[kAdTitleKey] = ad.title;
        properties[kAdTextKey] = ad.descriptionText;
        properties[kAdIconImageKey] = ad.iconURL.absoluteString;
        properties[kAdMainImageKey] = ad.imageURL.absoluteString;
        properties[kAdStarRatingKey] = ad.starRating.stringValue;
        properties[kAdCTATextKey] = ad.ctaText;
        
        self.properties = properties;
    }
    return self;
}

#pragma mark - MPNativeAdAdapter Protocol

- (void)displayContentForURL:(NSURL *)URL rootViewController:(UIViewController *)controller
{
    [self.nativeAd launchClickTarget];
}

- (void)willAttachToView:(UIView *)view
{
    // As of >= 4.1.0, we support convenience methods for impression tracking
    if ( [self.nativeAd respondsToSelector: @selector(trackImpressionAndNotify:)] )
    {
        [self.nativeAd performSelector: @selector(trackImpressionAndNotify:) withObject: self];
    }
    else
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        ALPostbackService *postbackService = [ALSdk shared].postbackService;
        [postbackService dispatchPostbackAsync: self.nativeAd.impressionTrackingURL andNotify: self];
#pragma GCC diagnostic pop
    }
}

#pragma mark - Postback Delegate

- (void)postbackService:(ALPostbackService *)postbackService didExecutePostback:(NSURL *)postbackURL
{
    [AppLovinNativeCustomEvent log: @"Native ad impression successfully executed."];
}

- (void)postbackService:(ALPostbackService *)postbackService didFailToExecutePostback:(NSURL *)postbackURL errorCode:(NSInteger)errorCode
{
    [AppLovinNativeCustomEvent log: @"Native ad impression failed to execute."];
}

// TODO: Implement mainMediaView for our video view

@end
