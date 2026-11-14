# Keep JNI entry points and classes called from native code.
-keepclasseswithmembernames class * { native <methods>; }
-keep class com.vhaiup.vpn.** { *; }
