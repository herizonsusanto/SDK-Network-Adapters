For Interstitial Ads integration, add the AppLovinInterstitialCustomEvent class files.

For Rewarded Video Ads integration,  add the AppLovinRewardedCustomEvent class files.

For Native Ads integration,  add the AppLovinNativeAdapter class files and the AppLovinNativeCustomEvent class files.

#Unity Integration#
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
