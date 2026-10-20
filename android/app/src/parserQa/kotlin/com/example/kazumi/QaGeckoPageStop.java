package com.example.kazumi;

/** QA diagnostic only: Gecko's stop callback provides no document URI. */
public final class QaGeckoPageStop {
    public final String uri = "";
    public final String detail;

    private QaGeckoPageStop(boolean success) {
        detail = "success=" + success + " uri=unattributed";
    }

    public static QaGeckoPageStop fromCallback(boolean success) {
        // Neither a requested URL nor a previous start identifies this stop.
        return new QaGeckoPageStop(success);
    }
}
