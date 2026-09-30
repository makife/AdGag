# ADGAG PATCH (live AR) — consumer R8 rules for the app.
#
# ML Kit finds its components (the face detector factory, ...) by creating
# every com.google.firebase.components.ComponentRegistrar listed in the
# manifest by REFLECTION (Class.forName(...).getDeclaredConstructor().newInstance()).
# R8 full mode kept those classes' names (the manifest references them) but
# removed their no-argument constructors, so no registrar could be created,
# the face detector factory was never registered, and
# FaceDetection.getClient() failed with "NullPointerException: ... getClass()
# on a null object reference" (device report, confirmed by dexdump: the
# FaceRegistrar class in the release APK had no <init>).
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
