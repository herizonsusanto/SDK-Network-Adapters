package YOUR_PACKAGE_NAME;

import android.content.Context;
import android.util.Log;
import android.view.View;
import android.os.Handler;

import com.applovin.nativeAds.AppLovinNativeAd;
import com.applovin.nativeAds.AppLovinNativeAdLoadListener;
import com.applovin.sdk.AppLovinPostbackListener;
import com.applovin.sdk.AppLovinSdk;
import com.mopub.nativeads.CustomEventNative;
import com.mopub.nativeads.NativeErrorCode;
import com.mopub.nativeads.NativeImageHelper;
import com.mopub.nativeads.StaticNativeAd;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

public class AppLovinNativeAdapter extends CustomEventNative {

    private CustomEventNativeListener mNativeListener;
    private View mView;


    private String TAG = "MopubAppLovinNativeAdapter";

    @Override
    public void loadNativeAd(final Context context, CustomEventNativeListener interstitialListener, Map<String, Object> localExtras, Map<String, String> serverExtras) {


        mNativeListener = interstitialListener;


        Log.d(TAG, "Request received for new native ad.");

        AppLovinSdk sdk = AppLovinSdk.getInstance(context);
        sdk.setPluginVersion("MoPubNative-1.0");
        sdk.getNativeAdService().loadNativeAds(1, new AppLovinNativeAdLoadListener() {
            @Override
            public void onNativeAdsLoaded(List nativeAds)

            {
                Log.d(TAG, "AppLovin Native ad loaded successfully.");
                final List<AppLovinNativeAd> nativeAdsList = (List<AppLovinNativeAd>) nativeAds;
                new Handler(context.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        precacheImage(new AppLovinMopubNativeAd(nativeAdsList.get(0), context), context);
                    }
                });


            }

            @Override
            public void onNativeAdsFailedToLoad(final int errorCode) {
                if (errorCode == 204) {
                    mNativeListener.onNativeAdFailed(NativeErrorCode.NETWORK_NO_FILL);
                } else if (errorCode >= 500) {
                    mNativeListener.onNativeAdFailed(NativeErrorCode.SERVER_ERROR_RESPONSE_CODE);
                } else if (errorCode < 0) {
                    mNativeListener.onNativeAdFailed(NativeErrorCode.NETWORK_INVALID_REQUEST);
                } else {
                    mNativeListener.onNativeAdFailed(NativeErrorCode.UNSPECIFIED);
                }

            }
        });
    }


    public class AppLovinMopubNativeAd extends StaticNativeAd

    {

        AppLovinNativeAd mNativeAd;
        boolean isImpressionTracked;
        Context mContext;


        public AppLovinMopubNativeAd(AppLovinNativeAd nativeAd, Context context) {


            mNativeAd = nativeAd;
            mContext = context;

            setTitle(nativeAd.getTitle());
            setText(nativeAd.getDescriptionText());
            setIconImageUrl(nativeAd.getIconUrl());
            setMainImageUrl(nativeAd.getImageUrl());
            setCallToAction(nativeAd.getCtaText());
            double startRatingDouble = nativeAd.getStarRating();
            setStarRating(startRatingDouble);
            setClickDestinationUrl(nativeAd.getClickUrl());

            isImpressionTracked = false;

        }


        private void trackImpression(final AppLovinNativeAd nativeAd) {

            if (isImpressionTracked) return;

            final AppLovinSdk sdk = AppLovinSdk.getInstance(mContext);
            final String impressionUrl = nativeAd.getImpressionTrackingUrl();
            sdk.getPostbackService().dispatchPostbackAsync(impressionUrl, new AppLovinPostbackListener() {
                @Override
                public void onPostbackSuccess(String url) {
                    notifyAdImpressed();
                    isImpressionTracked = true;
                }

                @Override
                public void onPostbackFailure(String url, int errorCode) {
                    Log.d(TAG, "Failed to track impression.");
                }
            });
        }


        @Override
        public void prepare(View view) {
            trackImpression(mNativeAd);
        }


        /**
         * use the code below if you would like AppLovin to handle the ad clicks for you:
         *

        public void prepare(View view) {

            Log.i(TAG, "prepare is called.");

            View.OnClickListener clickListener = new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Log.i(TAG, "onClick is called.");

                    mNativeAd.launchClickTarget(mContext);

                    notifyAdClicked();
                }
            };

            mView = view;
            mView.setOnClickListener(clickListener);
            
            // If you need to make subviews of the view clickable (e.g. CTA button), apply the click listener to them:
            mView.findViewById(R.id.ID_OF_SUBVIEW).setOnClickListener(clickListener);

            trackImpression(mNativeAd);

        }

        */

        @Override
        public void clear(View view) {
            mView = null;
        }

        @Override
        public void destroy() {
            mNativeListener = null;
        }

    }

    private void precacheImage(final AppLovinMopubNativeAd appLovinMopubNativeAd, Context context) {

        String[] urls = {appLovinMopubNativeAd.getIconImageUrl(), appLovinMopubNativeAd.getMainImageUrl()};

        NativeImageHelper.preCacheImages(context, Arrays.asList(urls), new NativeImageHelper.ImageListener() {
            @Override
            public void onImagesCached() {
                Log.i(TAG, "AppLovin native ad images were loaded successfully.");
                mNativeListener.onNativeAdLoaded(appLovinMopubNativeAd);

            }

            @Override
            public void onImagesFailedToCache(NativeErrorCode nativeErrorCode) {

                mNativeListener.onNativeAdLoaded(appLovinMopubNativeAd);

            }
        });

    }


}
