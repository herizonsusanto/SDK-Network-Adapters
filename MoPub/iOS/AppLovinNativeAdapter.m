//
// AppLovin <--> MoPub Network Adaptors
//

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC. Use the -fobjc-arc flag in the XCode build phases tab.
#endif

#import "AppLovinNativeCustomEvent.h"
#import "AppLovinNativeAdapter.h"

// Use the below import statements if not integrating our SDK as a first-class framework
//#import "ALSdk.h"

@implementation AppLovinNativeAdapter

- (id)initWithALNativeAd:(ALNativeAd *)ad
{
    self.nativeAd = ad;
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    
    [props setValue:ad.title                        forKey:kAdTitleKey];
    [props setValue:ad.descriptionText              forKey:kAdTextKey];
    [props setValue:[ad.iconURL absoluteString]     forKey:kAdIconImageKey];
    [props setValue:[ad.imageURL absoluteString]    forKey:kAdMainImageKey];
    [props setValue:[ad.starRating stringValue]     forKey:kAdStarRatingKey];
    [props setValue:ad.ctaText                      forKey:kAdCTATextKey];

    self.properties = props;
    
    return self;
}

- (void)displayContentForURL:(NSURL *)URL rootViewController:(UIViewController *)controller
{
    [self.nativeAd launchClickTarget];
}

- (void)willAttachToView:(UIView *)view
{
    [self.nativeAd trackImpressionAndNotify: self];
}

- (void)postbackService:(alnonnull ALPostbackService *)postbackService didExecutePostback:(alnonnull NSURL *)postbackURL
{
    
}

- (void)postbackService:(alnonnull ALPostbackService *)postbackService didFailToExecutePostback:(alnullable NSURL *)postbackURL errorCode:(NSInteger)errorCode
{
    [AppLovinNativeCustomEvent ALLog: @"Failed to execute impression postback."];
}

@end
