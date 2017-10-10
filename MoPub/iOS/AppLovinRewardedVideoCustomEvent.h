//
//  AppLovinRewardedVideoCustomEvent.h
//
//
//  Created by Thomas So on 5/21/17.
//
//

#import "MPRewardedVideoCustomEvent.h"

// PLEASE NOTE: We have renamed this class from "AppLovinRewardedCustomEvent" to "AppLovinRewardedVideoCustomEvent", you can use either classname in your MoPub account.
@interface AppLovinRewardedVideoCustomEvent : MPRewardedVideoCustomEvent
@end

// AppLovinRewardedCustomEvent is deprecated but kept here for backwards-compatibility purposes.
@interface AppLovinRewardedCustomEvent : AppLovinRewardedVideoCustomEvent
@end
