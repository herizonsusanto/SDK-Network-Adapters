package YOUR_PACKAGE_NAME;

import android.content.Context;

import com.mopub.common.MoPubAdvancedBidder;

/**
 * Include this class to use advanced bidding from AppLovin.
 */
public class AppLovinAdvancedBidder
        implements MoPubAdvancedBidder
{
    @Override
    public String getCreativeNetworkName()
    {
        return "applovin";
    }

    @Override
    public String getToken(final Context context)
    {
        return null;
    }
}
