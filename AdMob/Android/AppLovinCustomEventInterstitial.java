package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.util.Log;

import com.applovin.adview.AppLovinInterstitialAd;
import com.applovin.adview.AppLovinInterstitialAdDialog;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinAdVideoPlaybackListener;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitial;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitialListener;

import java.lang.reflect.Method;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK interstitial adapter for AdMob.
 * <p>
 * Created by Thomas So on 5/28/17.
 */

//
// PLEASE NOTE: We have renamed this class from "YOUR_PACKAGE_NAME.AdMobMediationInterEvent" to "YOUR_PACKAGE_NAME.AppLovinCustomEventInterstitial", you can use either classname in your AdMob account.
//
public class AppLovinCustomEventInterstitial
        implements CustomEventInterstitial, AppLovinAdLoadListener, AppLovinAdDisplayListener, AppLovinAdClickListener, AppLovinAdVideoPlaybackListener
{
    private static final boolean LOGGING_ENABLED = true;
    private static final Handler uiHandler       = new Handler( Looper.getMainLooper() );

    private Context                         context;
    private CustomEventInterstitialListener listener;

    private AppLovinAd loadedAd;

    //
    // AdMob Custom Event Methods
    //

    @Override
    public void requestInterstitialAd(final Context context, final CustomEventInterstitialListener listener, final String serverParameter, final MediationAdRequest mediationAdRequest, final Bundle customEventExtras)
    {
        log( DEBUG, "Requesting AppLovin interstitial..." );

        // SDK versions BELOW 7.2.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 720 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin interstitial. Invalid context provided." );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INVALID_REQUEST );

            return;
        }

        // Store parent objects
        this.listener = listener;
        this.context = context;

        final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
        sdk.setPluginVersion( "AdMob-2.0" );

        // Zones support is available on AppLovin SDK 7.5.0 and higher
        final String zoneId = serverParameter;
        if ( AppLovinSdk.VERSION_CODE >= 750 && !TextUtils.isEmpty( zoneId ) )
        {
            // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
            try
            {
                final Method method = sdk.getAdService().getClass().getMethod( "loadNextAdForZoneId", String.class, AppLovinAdLoadListener.class );
                method.invoke( sdk.getAdService(), zoneId, this );
            }
            catch ( Throwable th )
            {
                log( ERROR, "Unable to load ad for zone: " + zoneId + "..." );
                listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INVALID_REQUEST );
            }
        }
        else
        {
            sdk.getAdService().loadNextAd( AppLovinAdSize.INTERSTITIAL, this );
        }
    }

    @Override
    public void showInterstitial()
    {
        if ( loadedAd != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );

            final AppLovinInterstitialAdDialog interstitialAd = createInterstitial( context, sdk );
            interstitialAd.setAdDisplayListener( this );
            interstitialAd.setAdClickListener( this );
            interstitialAd.setAdVideoPlaybackListener( this );
            interstitialAd.showAndRender( loadedAd );
        }
        else
        {
            log( ERROR, "Failed to show an AppLovin interstitial before one was loaded" );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
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
        log( DEBUG, "Interstitial did load ad: " + ad.getAdIdNumber() );

        loadedAd = ad;

        runOnUiThread( new Runnable()
        {
            @Override
            public void run()
            {
                listener.onAdLoaded();
            }
        } );
    }

    @Override
    public void failedToReceiveAd(final int errorCode)
    {
        log( ERROR, "Interstitial failed to load with error: " + errorCode );

        runOnUiThread( new Runnable()
        {
            @Override
            public void run()
            {
                listener.onAdFailedToLoad( toAdMobErrorCode( errorCode ) );
            }
        } );

        // TODO: Add support for backfilling on regular ad request if invalid zone entered
    }

    //
    // Ad Display Listener
    //

    @Override
    public void adDisplayed(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial displayed" );
        listener.onAdOpened();
    }

    @Override
    public void adHidden(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial dismissed" );
        listener.onAdClosed();
    }

    //
    // Ad Click Listener
    //

    @Override
    public void adClicked(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial clicked" );
        listener.onAdLeftApplication();
    }

    //
    // Video Playback Listener
    //

    @Override
    public void videoPlaybackBegan(final AppLovinAd ad)
    {
        log( DEBUG, "Interstitial video playback began" );
    }

    @Override
    public void videoPlaybackEnded(final AppLovinAd ad, final double percentViewed, final boolean fullyWatched)
    {
        log( DEBUG, "Interstitial video playback ended at playback percent: " + percentViewed );
    }

    //
    // Utility Methods
    //

    private AppLovinInterstitialAdDialog createInterstitial(final Context context, final AppLovinSdk sdk)
    {
        AppLovinInterstitialAdDialog inter = null;

        try
        {
            // AppLovin SDK < 7.2.0 uses an Activity, as opposed to Context in >= 7.2.0
            final Class<?> contextClass = ( AppLovinSdk.VERSION_CODE < 720 ) ? Activity.class : Context.class;
            final Method method = AppLovinInterstitialAd.class.getMethod( "create", AppLovinSdk.class, contextClass );

            inter = (AppLovinInterstitialAdDialog) method.invoke( null, sdk, context );
        }
        catch ( Throwable th )
        {
            log( ERROR, "Unable to create AppLovinInterstitialAd." );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }

        return inter;
    }

    private static void log(final int priority, final String message)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinInterstitial", message );
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
     * Performs the given runnable on the main thread.
     */
    public static void runOnUiThread(final Runnable runnable)
    {
        if ( Looper.myLooper() == Looper.getMainLooper() )
        {
            runnable.run();
        }
        else
        {
            uiHandler.post( runnable );
        }
    }
}
