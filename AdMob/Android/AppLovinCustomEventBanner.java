package AdMob.Android;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
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

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.Queue;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK banner adapter for AdMob.
 * <p>
 * Created by thomasso on 4/12/17.
 */

public class AppLovinCustomEventBanner
        implements CustomEventBanner, AppLovinAdLoadListener
{
    private static final boolean LOGGING_ENABLED = true;
    private static final Handler UI_HANDLER      = new Handler( Looper.getMainLooper() );
    private static final String  DEFAULT_ZONE    = "";

    private static final int BANNER_STANDARD_HEIGHT         = 50;
    private static final int BANNER_HEIGHT_OFFSET_TOLERANCE = 10;

    // A dictionary of Zone -> Queue of `AppLovinAd`s to be shared by instances of the custom event.
    // This prevents skipping of ads as this adapter will be re-created and preloaded
    // on every ad load regardless if ad was actually displayed or not.
    private static final Map<String, Queue<AppLovinAd>> GLOBAL_AD_VIEW_ADS      = new HashMap<String, Queue<AppLovinAd>>();
    private static final Object                         GLOBAL_AD_VIEW_ADS_LOCK = new Object();

    private CustomEventBannerListener customEventBannerListener;

    private AppLovinAdView adView;
    private String         zoneId; // The zone identifier this instance of the custom event is loading for

    //
    // AdMob Custom Event Methods
    //

    @Override
    public void requestBannerAd(final Context context, final CustomEventBannerListener customEventBannerListener, final String serverParameter, final AdSize adSize, final MediationAdRequest mediationAdRequest, final Bundle customEventExtras)
    {
        this.customEventBannerListener = customEventBannerListener;

        // SDK versions BELOW 7.1.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 710 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin banner. Invalid context provided." );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );

            return;
        }

        log( DEBUG, "Requesting AppLovin banner of size: " + adSize );

        final AppLovinAdSize appLovinAdSize = appLovinAdSizeFromAdMobAdSize( adSize );
        if ( appLovinAdSize != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
            sdk.setPluginVersion( "AdMob-2.1" );

            // Zones support is available on AppLovin SDK 7.5.0 and higher
            if ( AppLovinSdk.VERSION_CODE >= 750 && customEventExtras != null && customEventExtras.containsKey( "zone_id" ) )
            {
                zoneId = customEventExtras.getString( "zone_id" );
            }
            else
            {
                zoneId = DEFAULT_ZONE;
            }

            adView = createAdView( zoneId, appLovinAdSize, context, customEventBannerListener );

            // Already have a preloaded ad
            if ( hasEnqueuedAd( zoneId ) )
            {
                log( DEBUG, "Found enqueued ad while requesting for banner. Using that..." );
                customEventBannerListener.onAdLoaded( adView );
            }
            else
            {
                // If this is a default Zone, load the ad normally
                if ( DEFAULT_ZONE.equals( zoneId ) )
                {
                    log( DEBUG, "Loading next ad for default zone" );
                    AppLovinSdk.getInstance( context ).getAdService().loadNextAd( appLovinAdSize, this );
                }
                // Otherwise, use the Zones API
                else
                {
                    // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
                    try
                    {
                        log( DEBUG, "Loading next ad for custom zone: " + zoneId );
                        final Method method = sdk.getAdService().getClass().getMethod( "loadNextAdForZoneId", String.class, AppLovinAdLoadListener.class );
                        method.invoke( sdk.getAdService(), zoneId, this );
                    }
                    catch ( Throwable th )
                    {
                        log( ERROR, "Unable to load ad for zone: " + zoneId + "..." );
                        customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INVALID_REQUEST );
                    }
                }
            }
        }
        else
        {
            log( ERROR, "Unable to request AppLovin banner" );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }
    }

    @Override
    public void onDestroy() {}

    @Override
    public void onPause()
    {
        log( DEBUG, "onPause() called" );
        if ( adView != null ) adView.pause();
    }

    @Override
    public void onResume()
    {
        log( DEBUG, "onResume() called" );
        if ( adView != null ) adView.resume();
    }

    //
    // Ad Load Listener
    //

    @Override
    public void adReceived(final AppLovinAd ad)
    {
        // AdMob requires `onAdLoaded()` and `onAdFailedToLoad()` callbacks to be called on main queue
        UI_HANDLER.post( new Runnable()
        {
            @Override
            public void run()
            {
                log( DEBUG, "Successfully loaded banner ad" );

                if ( !adView.isAttachedToWindow() )
                {
                    log( DEBUG, "Enqueuing loaded ad..." );
                    enqueueAd( ad, zoneId );
                }
                else
                {
                    log( DEBUG, "Rendering loaded ad..." );
                    adView.renderAd( ad );
                }

                customEventBannerListener.onAdLoaded( adView );
            }
        } );
    }

    @Override
    public void failedToReceiveAd(final int errorCode)
    {
        // AdMob requires `onAdLoaded()` and `onAdFailedToLoad()` callbacks to be called on main queue
        UI_HANDLER.post( new Runnable()
        {
            @Override
            public void run()
            {
                log( ERROR, "Failed to load banner ad with code: " + errorCode );

                // If CURRENT ad request was a no fill, check against enqueued ads
                if ( errorCode == AppLovinErrorCodes.NO_FILL )
                {
                    final AppLovinAd preloadedAd = dequeueAd( zoneId );

                    // There is an enqueued ad, use that
                    if ( preloadedAd != null )
                    {
                        log( DEBUG, "Using enqueued ad instead..." );
                        adReceived( preloadedAd );

                        return;
                    }
                }

                customEventBannerListener.onAdFailedToLoad( toAdMobErrorCode( errorCode ) );
            }
        } );
    }

    //
    // Utility Methods
    //

    private static boolean hasEnqueuedAd(final String zoneId)
    {
        synchronized ( GLOBAL_AD_VIEW_ADS_LOCK )
        {
            final Queue<AppLovinAd> preloadedAds = GLOBAL_AD_VIEW_ADS.get( zoneId );
            return preloadedAds != null && !preloadedAds.isEmpty();
        }
    }

    private static AppLovinAd dequeueAd(final String zoneId)
    {
        synchronized ( GLOBAL_AD_VIEW_ADS_LOCK )
        {
            AppLovinAd preloadedAd = null;

            final Queue<AppLovinAd> preloadedAds = GLOBAL_AD_VIEW_ADS.get( zoneId );
            if ( preloadedAds != null && !preloadedAds.isEmpty() )
            {
                preloadedAd = preloadedAds.poll();
            }

            log( DEBUG, "Dequeued ad: " + preloadedAd + " for zone: " + zoneId );

            return preloadedAd;
        }
    }

    private static void enqueueAd(final AppLovinAd ad, final String zoneId)
    {
        synchronized ( GLOBAL_AD_VIEW_ADS_LOCK )
        {
            Queue<AppLovinAd> preloadedAds = GLOBAL_AD_VIEW_ADS.get( zoneId );
            if ( preloadedAds == null )
            {
                preloadedAds = new LinkedList<AppLovinAd>();
                GLOBAL_AD_VIEW_ADS.put( zoneId, preloadedAds );
            }

            preloadedAds.offer( ad );

            log( DEBUG, "Enqueued ad: " + ad + " for zone: " + zoneId + ". Size: " + preloadedAds.size() );
        }
    }

    private AppLovinAdView createAdView(final String zoneId, final AppLovinAdSize size, final Context parentContext, final CustomEventBannerListener customEventBannerListener)
    {
        AppLovinAdMobAdView adView = null;

        try
        {
            // AppLovin SDK < 7.1.0 uses an Activity, as opposed to Context in >= 7.1.0
            final Class<?> contextClass = ( AppLovinSdk.VERSION_CODE < 710 ) ? Activity.class : Context.class;

            final Constructor<?> constructor;

            // If this is a default Zone, create the incentivized ad normally
            if ( DEFAULT_ZONE.equals( zoneId ) )
            {
                adView = new AppLovinAdMobAdView( size, parentContext );
            }
            // Otherwise, use the Zones API
            else
            {
                // Dynamically create an instance of AppLovinAdView with a given zone without breaking backwards compatibility for publishers on older SDKs.
                constructor = AppLovinAdMobAdView.class.getConstructor( getClass(), AppLovinAdSize.class, String.class, contextClass );
                adView = (AppLovinAdMobAdView) constructor.newInstance( this, size, zoneId, parentContext );
            }

            final AppLovinAdMobBannerListener listener = new AppLovinAdMobBannerListener();
            adView.setAdDisplayListener( listener );
            adView.setAdClickListener( listener );
        }
        catch ( Throwable th )
        {
            log( ERROR, "Unable to create AppLovinAdView. Because of: " + Log.getStackTraceString( th ) );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }

        return adView;
    }

    private AppLovinAdSize appLovinAdSizeFromAdMobAdSize(final AdSize adSize)
    {
        if ( AdSize.BANNER.equals( adSize ) || AdSize.LARGE_BANNER.equals( adSize ) )
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
        // This is not a one of AdMob's predefined size
        else
        {
            // Assume fluid width, and check for height with offset tolerance
            final int offset = Math.abs( BANNER_STANDARD_HEIGHT - adSize.getHeight() );
            if ( offset <= BANNER_HEIGHT_OFFSET_TOLERANCE )
            {
                return AppLovinAdSize.BANNER;
            }
        }

        return null;
    }

    private static void log(final int priority, final String message)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinBanner", message );
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
     * The receiver object of the AppLovinAdView's and AppLovinAdService's listeners.
     */
    private class AppLovinAdMobBannerListener
            implements AppLovinAdDisplayListener, AppLovinAdClickListener
    {
        @Override
        public void adDisplayed(final AppLovinAd ad)
        {
            log( DEBUG, "Banner displayed" );
        }

        @Override
        public void adHidden(final AppLovinAd ad)
        {
            log( DEBUG, "Banner dismissed" );
        }

        @Override
        public void adClicked(final AppLovinAd ad)
        {
            log( DEBUG, "Banner clicked" );

            customEventBannerListener.onAdOpened();
            customEventBannerListener.onAdLeftApplication();
        }
    }

    /**
     * This subclass provides a way to have an `AppLovinAdView` to dynamically render an enqueued ad WHEN needed.
     */
    public class AppLovinAdMobAdView
            extends AppLovinAdView
    {
        private AppLovinAdMobAdView(final AppLovinAdSize adSize, final Context context)
        {
            this( adSize, DEFAULT_ZONE, context );
        }

        public AppLovinAdMobAdView(final AppLovinAdSize adSize, final String zoneId, final Context context)
        {
            // TODO: Make dynamic
            super( adSize, zoneId, context );

            // To prevent weird AdMob case where it quickly sets visibility to GONE _after_ attaching to window and displaying ad, causing us to render an empty ad
            setAutoDestroy( false );
        }

        @Override
        protected void onAttachedToWindow()
        {
            super.onAttachedToWindow();

            log( DEBUG, "AppLovinAdView attached to window" );

            final AppLovinAd preloadedAd = dequeueAd( zoneId );
            if ( preloadedAd != null )
            {
                log( DEBUG, "Rendering enqueued ad..." );
                renderAd( preloadedAd );
            }
            // Something is wrong... no preloaded ad provided... manually load an ad if none provided
            else
            {
                log( DEBUG, "Loading new ad..." );
                loadNextAd();
            }
        }
    }
}
