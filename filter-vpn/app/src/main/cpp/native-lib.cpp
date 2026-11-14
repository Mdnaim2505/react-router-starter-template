// JNI entry points for the Filter VPN native engine.
#include <jni.h>

#define FVPN_NATIVE_VERSION "filtervpn-native 0.1.0"

extern "C" JNIEXPORT jstring JNICALL
Java_com_vhaiup_vpn_NativeBridge_nativeVersion(JNIEnv *env, jclass /*clazz*/) {
    return env->NewStringUTF(FVPN_NATIVE_VERSION);
}
