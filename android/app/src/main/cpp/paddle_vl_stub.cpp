// Stub native library for optional PaddleOCR-VL-1.6.
// Real inference requires linking llama.cpp (or equivalent) and implementing
// the JNI methods used by PaddleVLBridge.kt.

#include <jni.h>

extern "C" JNIEXPORT jstring JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativePing(JNIEnv* env, jobject /* this */) {
    return env->NewStringUTF("paddle_vl_stub");
}
