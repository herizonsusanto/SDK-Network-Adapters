package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;

import com.applovin.adview.AppLovinAdView;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.mediation.customevent.CustomEventBanner;
import com.google.android.gms.ads.mediation.customevent.CustomEventBannerListener;

/**
 * AppLovin Banner SDK Mediation for AdMob.
 * <p>
 * Created by thomasso on 4/12/17.
 *
 * @version 1.0
 */

public final class AppLovinCustomEventBanner
        implements CustomEventBanner
{
    private static final String TAG = "AppLovinCustomEventBanner";

    private AppLovinAdView adView;

    @Override
    public void requestBannerAd(final Context context, final CustomEventBannerListener customEventBannerListener, final String s, final AdSize adSize, final MediationAdRequest mediationAdRequest, final Bundle bundle)
    {
        // SDK versions BELOW 7.1.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 710 && !( context instanceof Activity ) )
        {
            Log.e( TAG, "Unable to request AppLovin banner. Invalid context provided." );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );

            return;
        }

        Log.d( TAG, "Requesting AppLovin banner of size: " + adSize );

        final AppLovinAdSize appLovinAdSize = appLovinAdSizeFromAdMobAdSize( adSize );
        if ( appLovinAdSize != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
            sdk.setPluginVersion( "AdMobBanner-1.0" );

            adView = new AppLovinAdView( appLovinAdSize, (Activity) context );
            adView.setAdLoadListener( new AppLovinAdLoadListener()
            {
                @Override
                public void adReceived(final AppLovinAd ad)
                {
                    Log.d( TAG, "Successfully loaded banner ad" );
                }

                @Override
                public void failedToReceiveAd(final int errorCode)
                {
                    Log.e( TAG, "Failed to load banner ad with code: " + errorCode );

                    if ( errorCode == AppLovinErrorCodes.NO_FILL )
                    {
                        customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_NO_FILL );
                    }
                    else if ( errorCode == AppLovinErrorCodes.NO_NETWORK || errorCode == AppLovinErrorCodes.FETCH_AD_TIMEOUT )
                    {
                        customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_NETWORK_ERROR );
                    }
                    else
                    {
                        customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
                    }
                }
            } );
            adView.setAdDisplayListener( new AppLovinAdDisplayListener()
            {
                @Override
                public void adDisplayed(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner displayed" );
                }

                @Override
                public void adHidden(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner dismissed" );
                }
            } );
            adView.setAdClickListener( new AppLovinAdClickListener()
            {
                @Override
                public void adClicked(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner clicked" );

                    customEventBannerListener.onAdOpened();
                    customEventBannerListener.onAdLeftApplication();
                }
            } );
            adView.loadNextAd();

            customEventBannerListener.onAdLoaded( adView );
        }
        else
        {
            Log.e( TAG, "Unable to request AppLovin banner" );

            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }
    }

    @Override
    public void onDestroy()
    {
        if ( adView != null ) adView.destroy();
    }

    @Override
    public void onPause()
    {
        if ( adView != null ) adView.pause();
    }

    @Override
    public void onResume()
    {
        if ( adView != null ) adView.resume();
    }

    private AppLovinAdSize appLovinAdSizeFromAdMobAdSize(final AdSize adSize)
    {
        if ( AdSize.BANNER.equals( adSize ) )
        {
            return AppLovinAdSize.BANNER;
        }
        else if ( AdSize.MEDIUM_RECTANGLE.equals( adSize ) )
        {
            return AppLovinAdSize.MREC;
        }
        else if ( AdSize.LEADERBOARD.equals( adSize ) )
        {
            return AppLovinAdSize.LEADER;
        }

        return null;
    }
}
