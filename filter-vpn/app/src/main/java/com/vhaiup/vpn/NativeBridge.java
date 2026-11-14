package com.vhaiup.vpn;

/**
 * Thin JNI facade over the native tunnel engine (libfiltervpn.so).
 *
 * <p>Phase 1 exposes only a version probe. Later phases add start/stop of the
 * user-space TCP/IP stack that reads the TUN file descriptor.
 */
public final class NativeBridge {

    static {
        System.loadLibrary("filtervpn");
    }

    private NativeBridge() {
    }

    /** @return the native engine version string, e.g. "filtervpn-native 0.1.0". */
    public static String version() {
        return nativeVersion();
    }

    private static native String nativeVersion();
}
