Rewarded Videos
====================
For rewarded videos integration, add the files GADMAdapterAppLovinRewardBasedVideoAd.h and GADMAdapterAppLovinRewardBasedVideoAd.m into your Xcode project. In the AdMob dashboard, add AppLovin as an ad network.

Note: For some versions of AdMob iOS SDK, you would also need to add the header files from the "Mediation Adapters", coming with the SDK, into your Xcode project.

Interstitials
====================
For Interstitials integration, add the files AppLovinCustomEventInterstitial.h and AppLovinCustomEventInterstitial.m into your Xcode project. In the AdMob dashboard, create a custom event with the class nane: AppLovinCustomEventInterstitial, as described [here](https://applovin.com/integration#adMobIntegration).

Banners
====================
For Banners integration, add the files AppLovinCustomEventBanner.h and AppLovinCustomEventBanner.m into your Xcode project. In the AdMob dashboard, create a custom event with the class nane: AppLovinCustomEventBanner, as described [here](https://applovin.com/integration#adMobIntegration).


Unity Integration
====================
Our Unity adapter does not include our SDK as framework but as a library (`.a` binary) with header files. Therefore, you need to edit the import statements:

1.Comment out framework import statements, i.e.:

Replace:

`#import <AppLovinSDK/AppLovinSDK.h>`

With:

`//#import <AppLovinSDK/AppLovinSDK.h>`


2.Uncomment all commented direct header import statements, for example:

Replace:

`//#import "ALInterstitialAd.h"`

With:

`#import "ALInterstitialAd.h"`
