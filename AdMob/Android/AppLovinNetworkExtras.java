package com.applovin.mediation;

import android.os.Bundle;

/**
 * Created by joshgleeson on 11/15/17.
 */

public class AppLovinNetworkExtras {
    private static final String ZONE_ID = "zone_id";

    /**
     * The AppLovin Zone ID to be used for the ad requests
     */
    private String mZoneID;

    public AppLovinNetworkExtras setZoneID(String zoneID ) {
        mZoneID = zoneID;
        return this;
    }

    public Bundle build() {
        Bundle extras = new Bundle();
        extras.putString( ZONE_ID, mZoneID );
        return extras;
    }
}
