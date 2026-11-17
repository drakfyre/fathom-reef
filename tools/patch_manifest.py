"""Makes the Godot-exported (apktool-decoded) manifest an OpenXR app for Quest.
Godot only adds these when it builds with Gradle; we patch them in instead.
usage: python3 -I patch_manifest.py <decoded>/AndroidManifest.xml"""
import sys

path = sys.argv[1]
s = open(path).read()
assert "org.khronos.openxr.permission.OPENXR" not in s, "already patched"

TOP = """
    <uses-permission android:name="org.khronos.openxr.permission.OPENXR"/>
    <uses-permission android:name="org.khronos.openxr.permission.OPENXR_SYSTEM"/>
    <uses-feature android:name="android.hardware.vr.headtracking" android:required="true" android:version="1"/>
    <queries>
        <provider android:authorities="org.khronos.openxr.runtime_broker;org.khronos.openxr.system_runtime_broker"/>
        <intent><action android:name="org.khronos.openxr.OpenXRRuntimeService"/></intent>
        <intent><action android:name="org.khronos.openxr.OpenXRApiLayerService"/></intent>
    </queries>"""
s = s.replace("<supports-screens", TOP.lstrip("\n") + "\n    <supports-screens", 1)

CATS = """<category android:name="android.intent.category.LAUNCHER"/>
                <category android:name="com.oculus.intent.category.VR"/>
                <category android:name="org.khronos.openxr.intent.category.IMMERSIVE_HMD"/>"""
assert '<category android:name="android.intent.category.LAUNCHER"/>' in s
s = s.replace('<category android:name="android.intent.category.LAUNCHER"/>', CATS, 1)

META = """<meta-data android:name="com.oculus.supportedDevices" android:value="quest2|questpro|quest3|quest3s"/>
        <meta-data android:name="org.godotengine.library.version\""""
s = s.replace('<meta-data android:name="org.godotengine.library.version"', META, 1)
# VR apps shouldn't be resizable windows or picture-in-picture
s = s.replace('android:resizeableActivity="true"', 'android:resizeableActivity="false"')
s = s.replace('android:supportsPictureInPicture="true"', 'android:supportsPictureInPicture="false"')
open(path, "w").write(s)
print("manifest patched for OpenXR/Quest")
