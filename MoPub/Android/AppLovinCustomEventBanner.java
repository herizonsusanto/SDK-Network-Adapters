package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.util.Log;

import com.applovin.adview.AppLovinAdView;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.mopub.mobileads.CustomEventBanner;
import com.mopub.mobileads.MoPubErrorCode;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.Queue;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK banner adapter for MoPub.
 * <p>
 * Created by Thomas So on 3/6/17.
 */

//
// PLEASE NOTE: We have renamed this class from "YOUR_PACKAGE_NAME.AppLovinBannerAdapter" to "YOUR_PACKAGE_NAME.AppLovinCustomEventBanner", you can use either classname in your MoPub account.
//
public class AppLovinCustomEventBanner
        extends CustomEventBanner
{
    private static final boolean LOGGING_ENABLED = true;
    private static final String  DEFAULT_ZONE    = "";

    private static final int BANNER_STANDARD_HEIGHT         = 50;
    private static final int BANNER_HEIGHT_OFFSET_TOLERANCE = 10;

    private static final String AD_WIDTH_KEY  = "com_mopub_ad_width";
    private static final String AD_HEIGHT_KEY = "com_mopub_ad_height";

    private CustomEventBannerListener customEventBannerListener;

    // A dictionary of Zone -> `AppLovinAdView` to be shared by instances of the custom event to prevent redundant recreation of our `AppLovinAdView`s.
    private static final Map<String, AppLovinAdView> GLOBAL_AD_VIEWS = new HashMap<String, AppLovinAdView>();

    // A dictionary of Zone -> Queue of `AppLovinAd`s to be shared by instances of the custom event.
    // This prevents skipping of ads as this adapter will be re-created and preloaded
    // on every ad load regardless if ad was actually displayed or not.
    private static final Map<String, Queue<AppLovinAd>> GLOBAL_AD_VIEW_ADS      = new HashMap<String, Queue<AppLovinAd>>();
    private static final Object                         GLOBAL_AD_VIEW_ADS_LOCK = new Object();

    private AppLovinAdView adView;
    private String         zoneId; // The zone identifier this instance of the custom event is loading for

    //
    // MoPub Custom Event Methods
    //

    @Override
    protected void loadBanner(final Context context, final CustomEventBannerListener customEventBannerListener, final Map<String, Object> localExtras, final Map<String, String> serverExtras)
    {
        this.customEventBannerListener = customEventBannerListener;

        // SDK versions BELOW 7.1.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 710 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin banner. Invalid context provided." );
            customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );

            return;
        }

        log( DEBUG, "Requesting AppLovin banner with localExtras: " + localExtras );

        final AppLovinAdSize appLovinAdSize = appLovinAdSizeFromLocalExtras( localExtras );
        if ( appLovinAdSize != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
            sdk.setPluginVersion( "MoPub-2.0" );

            // Zones support is available on AppLovin SDK 7.5.0 and higher
            if ( AppLovinSdk.VERSION_CODE >= 750 && serverExtras != null && serverExtras.containsKey( "zone_id" ) )
            {
                zoneId = serverExtras.get( "zone_id" );
            }
            else
            {
                zoneId = DEFAULT_ZONE;
            }

            adView = GLOBAL_AD_VIEWS.get( zoneId );
            if ( adView == null )
            {
                adView = createAdView( zoneId, appLovinAdSize, context, customEventBannerListener );
                GLOBAL_AD_VIEWS.put( zoneId, adView );
            }

            final AppLovinMoPubBannerListener listener = new AppLovinMoPubBannerListener();
            adView.setAdDisplayListener( listener );
            adView.setAdClickListener( listener );

            // If this is a default Zone, load the ad normally
            if ( DEFAULT_ZONE.equals( zoneId ) )
            {
                AppLovinSdk.getInstance( context ).getAdService().loadNextAd( appLovinAdSize, listener );
            }
            // Otherwise, use the Zones API
            else
            {
                // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
                try
                {
                    final Method method = sdk.getAdService().getClass().getMethod( "loadNextAdForZoneId", String.class, AppLovinAdLoadListener.class );
                    method.invoke( sdk.getAdService(), zoneId, listener );
                }
                catch ( Throwable th )
                {
                    log( ERROR, "Unable to load ad for zone: " + zoneId + "..." );
                    customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );
                }
            }
        }
        else
        {
            log( ERROR, "Unable to request AppLovin banner" );
            customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );
        }
    }

    @Override
    protected void onInvalidate() {}

    //
    // Utility Methods
    //

    private AppLovinAdSize appLovinAdSizeFromLocalExtras(final Map<String, Object> localExtras)
    {
        // Handle trivial case
        if ( localExtras == null || localExtras.isEmpty() )
        {
            log( ERROR, "No serverExtras provided" );
            return null;
        }

        try
        {
            final int width = (Integer) localExtras.get( AD_WIDTH_KEY );
            final int height = (Integer) localExtras.get( AD_HEIGHT_KEY );

            // We have valid dimensions
            if ( width > 0 && height > 0 )
            {
                log( DEBUG, "Valid width (" + width + ") and height (" + height + ") provided" );

                // Assume fluid width, and check for height with offset tolerance
                final int offset = Math.abs( BANNER_STANDARD_HEIGHT - height );

                if ( offset <= BANNER_HEIGHT_OFFSET_TOLERANCE )
                {
                    return AppLovinAdSize.BANNER;
                }
                else if ( height <= AppLovinAdSize.MREC.getHeight() )
                {
                    return AppLovinAdSize.MREC;
                }
                else
                {
                    log( ERROR, "Provided dimensions does not meet the dimensions required of banner or mrec ads" );
                }
            }
            else
            {
                log( ERROR, "Invalid width (" + width + ") and height (" + height + ") provided" );
            }
        }
        catch ( Throwable th )
        {
            log( ERROR, "Encountered error while parsing width and height from serverExtras", th );
        }

        return null;
    }

    //
    // Utility Methods
    //

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
        }
    }

    private AppLovinAdView createAdView(final String zoneId, final AppLovinAdSize size, final Context parentContext, final CustomEventBannerListener customEventBannerListener)
    {
        AppLovinMoPubAdView adView = null;

        try
        {
            // AppLovin SDK < 7.1.0 uses an Activity, as opposed to Context in >= 7.1.0
            final Class<?> contextClass = ( AppLovinSdk.VERSION_CODE < 710 ) ? Activity.class : Context.class;

            final Constructor<?> constructor;

            // If this is a default Zone, create the incentivized ad normally
            if ( DEFAULT_ZONE.equals( zoneId ) )
            {
                adView = new AppLovinMoPubAdView( size, parentContext );
            }
            // Otherwise, use the Zones API
            else
            {
                // Dynamically create an instance of AppLovinAdView with a given zone without breaking backwards compatibility for publishers on older SDKs.
                constructor = AppLovinMoPubAdView.class.getConstructor( AppLovinAdSize.class, String.class, contextClass );
                adView = (AppLovinMoPubAdView) constructor.newInstance( size, zoneId, parentContext );
            }

            adView.setZoneId( zoneId );
        }
        catch ( Throwable th )
        {
            log( ERROR, "Unable to get create AppLovinAdView." );
            customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );
        }

        return adView;
    }

    private static void log(final int priority, final String message)
    {
        log( priority, message, null );
    }

    private static void log(final int priority, final String message, final Throwable th)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinBanner", message + ( ( th == null ) ? "" : Log.getStackTraceString( th ) ) );
        }
    }

    private static MoPubErrorCode toMoPubErrorCode(final int applovinErrorCode)
    {
        if ( applovinErrorCode == AppLovinErrorCodes.NO_FILL )
        {
            return MoPubErrorCode.NETWORK_NO_FILL;
        }
        else if ( applovinErrorCode == AppLovinErrorCodes.UNSPECIFIED_ERROR )
        {
            return MoPubErrorCode.NETWORK_INVALID_STATE;
        }
        else if ( applovinErrorCode == AppLovinErrorCodes.NO_NETWORK )
        {
            return MoPubErrorCode.NO_CONNECTION;
        }
        else if ( applovinErrorCode == AppLovinErrorCodes.FETCH_AD_TIMEOUT )
        {
            return MoPubErrorCode.NETWORK_TIMEOUT;
        }
        else
        {
            return MoPubErrorCode.UNSPECIFIED;
        }
    }

    /**
     * The receiver object of the AppLovinAdView's and AppLovinAdService's listeners.
     */
    private class AppLovinMoPubBannerListener
            implements AppLovinAdLoadListener, AppLovinAdDisplayListener, AppLovinAdClickListener
    {
        @Override
        public void adReceived(final AppLovinAd ad)
        {
            log( DEBUG, "Successfully loaded banner ad" );

            if ( !adView.isAttachedToWindow() )
            {
                enqueueAd( ad, zoneId );
            }
            else
            {
                adView.renderAd( ad );
            }

            customEventBannerListener.onBannerLoaded( adView );
        }

        @Override
        public void failedToReceiveAd(final int errorCode)
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
                }
                else
                {
                    customEventBannerListener.onBannerFailed( toMoPubErrorCode( errorCode ) );
                }
            }
            else
            {
                customEventBannerListener.onBannerFailed( toMoPubErrorCode( errorCode ) );
            }
        }

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

            customEventBannerListener.onBannerClicked();
            customEventBannerListener.onLeaveApplication();
        }
    }

    /**
     * This subclass provides a way to have an `AppLovinAdView` to dynamically render an enqueued ad WHEN needed.
     */
    private static class AppLovinMoPubAdView
            extends AppLovinAdView
    {
        private String zoneId;

        private AppLovinMoPubAdView(final AppLovinAdSize adSize, final Context context)
        {
            super( adSize, context );
            setAutoDestroy( false );
        }

        @Override
        protected void onAttachedToWindow()
        {
            super.onAttachedToWindow();

            final AppLovinAd preloadedAd = dequeueAd( zoneId );
            if ( preloadedAd != null )
            {
                renderAd( preloadedAd );
            }
            // Something is wrong... no preloaded ad provided... manually load an ad if none provided
            else
            {
                loadNextAd();
            }
        }

        @Override
        protected void onDetachedFromWindow()
        {
            super.onDetachedFromWindow();

            // Activity has been dismissed
            GLOBAL_AD_VIEWS.clear();
        }

        private void setZoneId(final String zoneId)
        {
            this.zoneId = zoneId;
        }
    }
}
