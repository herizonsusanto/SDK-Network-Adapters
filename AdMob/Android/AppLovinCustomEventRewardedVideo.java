package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;

import com.applovin.adview.AppLovinIncentivizedInterstitial;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdRewardListener;
import com.applovin.sdk.AppLovinAdVideoPlaybackListener;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.reward.RewardItem;
import com.google.android.gms.ads.reward.mediation.MediationRewardedVideoAdAdapter;
import com.google.android.gms.ads.reward.mediation.MediationRewardedVideoAdListener;

import java.util.Map;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK rewarded video adapter for AdMob.
 * <p>
 * Created by Thomas So on 5/29/17.
 *
 * @version 2.0
 */

// Please note: We have renamed this class from "ApplovinAdapter" to "AppLovinCustomEventRewardedVideo", please make sure you have the appropriate class name in your GADs account
public class AppLovinCustomEventRewardedVideo
        implements MediationRewardedVideoAdAdapter,
        AppLovinAdLoadListener, AppLovinAdDisplayListener, AppLovinAdClickListener, AppLovinAdVideoPlaybackListener, AppLovinAdRewardListener
{
    private static final boolean LOGGING_ENABLED = true;

    private boolean initialized;

    private AppLovinIncentivizedInterstitial incentivizedInterstitial;
    private Context                          context;
    private MediationRewardedVideoAdListener listener;

    private boolean    fullyWatched;
    private RewardItem reward;

    //
    // AdMob Custom Event Methods
    //

    @Override
    public void initialize(final Context context, final MediationAdRequest adRequest, final String userId, final MediationRewardedVideoAdListener listener, final Bundle serverParameters, final Bundle networkExtras)
    {
        // SDK versions BELOW 7.2.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 720 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin rewarded video. Invalid context provided." );
            listener.onInitializationFailed( this, AdRequest.ERROR_CODE_INVALID_REQUEST );

            return;
        }

        log( DEBUG, "Initializing AppLovin rewarded video..." );

        this.context = context;
        this.listener = listener;

        if ( !initialized )
        {
            AppLovinSdk.initializeSdk( context );
            AppLovinSdk.getInstance( context ).setPluginVersion( "AdMob-2.0" );

            initialized = true;

            incentivizedInterstitial = AppLovinIncentivizedInterstitial.create( context );
        }

        listener.onInitializationSucceeded( this );
    }

    @Override
    public boolean isInitialized()
    {
        return initialized;
    }

    @Override
    public void loadAd(final MediationAdRequest adRequest, final Bundle serverParameters, final Bundle networkExtras)
    {
        log( DEBUG, "Requesting AppLovin rewarded video with networkExtras: " + networkExtras );

        if ( incentivizedInterstitial.isAdReadyToDisplay() )
        {
            listener.onAdLoaded( this );
        }
        else
        {
            incentivizedInterstitial.preload( this );
        }
    }

    @Override
    public void showVideo()
    {
        if ( incentivizedInterstitial.isAdReadyToDisplay() )
        {
            fullyWatched = false;
            reward = null;

            incentivizedInterstitial.show( context, null, this, this, this, this );
        }
        else
        {
            log( ERROR, "Failed to show an AppLovin rewarded video before one was loaded" );
            listener.onAdFailedToLoad( this, AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }
    }

    @Override
    public void onPause() {}

    @Override
    public void onResume() {}

    @Override
    public void onDestroy() {}

    //
    // Ad Load Listener
    //

    @Override
    public void adReceived(final AppLovinAd ad)
    {
        log( DEBUG, "Rewarded video did load ad: " + ad.getAdIdNumber() );
        listener.onAdLoaded( this );
    }

    @Override
    public void failedToReceiveAd(final int errorCode)
    {
        log( DEBUG, "Rewarded video failed to load with error: " + errorCode );
        listener.onAdFailedToLoad( this, toAdMobErrorCode( errorCode ) );
    }

    //
    // Ad Display Listener
    //

    @Override
    public void adDisplayed(final AppLovinAd ad)
    {
        log( DEBUG, "Rewarded video displayed" );
        listener.onAdOpened( this );

    }

    @Override
    public void adHidden(final AppLovinAd ad)
    {
        log( DEBUG, "Rewarded video dismissed" );

        if ( fullyWatched && reward != null )
        {
            listener.onRewarded( this, reward );
        }

        listener.onAdClosed( this );
    }

    //
    // Ad Click Listener
    //

    @Override
    public void adClicked(final AppLovinAd ad)
    {
        log( DEBUG, "Rewarded video clicked" );

        listener.onAdClicked( this );
        listener.onAdLeftApplication( this );
    }

    //
    // Video Playback Listener
    //

    @Override
    public void videoPlaybackBegan(AppLovinAd ad)
    {
        log( DEBUG, "Rewarded video playback began" );
        listener.onVideoStarted( this );
    }

    @Override
    public void videoPlaybackEnded(AppLovinAd ad, double percentViewed, boolean fullyWatched)
    {
        log( DEBUG, "Rewarded video playback ended at playback percent: " + percentViewed );
        this.fullyWatched = fullyWatched;
    }

    //
    // Reward Listener
    //

    @Override
    public void userOverQuota(final AppLovinAd appLovinAd, final Map<String, String> map)
    {
        log( ERROR, "Rewarded video validation request for ad did exceed quota with response: " + map );
    }

    @Override
    public void validationRequestFailed(final AppLovinAd appLovinAd, final int errorCode)
    {
        log( ERROR, "Rewarded video validation request for ad failed with error code: " + errorCode );
    }

    @Override
    public void userRewardRejected(final AppLovinAd appLovinAd, final Map<String, String> map)
    {
        log( ERROR, "Rewarded video validation request was rejected with response: " + map );
    }

    @Override
    public void userDeclinedToViewAd(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "User declined to view rewarded video" );
    }

    @Override
    public void userRewardVerified(final AppLovinAd ad, final Map<String, String> map)
    {
        final String currency = map.get( "currency" );
        final int amount = (int) Double.parseDouble( map.get( "amount" ) ); // AppLovin returns amount as double

        log( DEBUG, "Rewarded " + amount + " " + currency );

        reward = new AppLovinRewardItem( amount, currency );
    }

    //
    // Utility Methods
    //

    private static void log(final int priority, final String message)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinCustomEventRewardedVideo", message );
        }
    }

    private static int toAdMobErrorCode(final int applovinErrorCode)
    {
        if ( applovinErrorCode == AppLovinErrorCodes.NO_FILL )
        {
            return AdRequest.ERROR_CODE_NO_FILL;
        }
        else if ( applovinErrorCode == AppLovinErrorCodes.NO_NETWORK || applovinErrorCode == AppLovinErrorCodes.FETCH_AD_TIMEOUT )
        {
            return AdRequest.ERROR_CODE_NETWORK_ERROR;
        }
        else
        {
            return AdRequest.ERROR_CODE_INTERNAL_ERROR;
        }
    }

    /**
     * Reward item wrapper class.
     */
    private static final class AppLovinRewardItem
            implements RewardItem
    {
        private final int    amount;
        private final String type;

        private AppLovinRewardItem(final int amount, final String type)
        {
            this.amount = amount;
            this.type = type;
        }

        @Override
        public String getType()
        {
            return type;
        }

        @Override
        public int getAmount()
        {
            return amount;
        }
    }
}
