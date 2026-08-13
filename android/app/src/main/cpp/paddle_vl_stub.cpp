/**
 * PaddleOCR-VL 1.6 native Android inference layer.
 *
 * Runtime path when llama.cpp is cloned by CI:
 *   GGUF text model + mmproj.gguf
 *        -> llama.cpp + libmtmd
 *        -> PNG/JPEG decoded by mtmd helper
 *        -> PaddleOCR-VL Spotting:
 *        -> LOC tokens + recognized text
 *        -> JSON object map for Flutter
 *
 * If the native runtime cannot load or process the model, this file returns
 * an empty object list so Flutter can use the existing ML Kit/MuPDF fallback.
 */

#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>
#include <sys/stat.h>

#define LOG_TAG "PaddleVL"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifdef HAS_LLAMA
#include "llama.h"
#endif

#ifdef HAS_MTMD
#include "mtmd.h"
#include "mtmd-helper.h"
#endif

namespace {

std::mutex g_mu;
bool g_ready = false;
#ifdef HAS_LLAMA
bool g_backend_initialized = false;
#endif
std::string g_model_path;
std::string g_mmproj_path;

#ifdef HAS_LLAMA
llama_model * g_model = nullptr;
llama_context * g_ctx = nullptr;
#endif

#ifdef HAS_MTMD
mtmd_context * g_mtmd = nullptr;
llama_pos g_n_past = 0;
#endif

bool file_ok(const char * path) {
    struct stat st{};
    if (stat(path, &st) != 0) return false;
    return S_ISREG(st.st_mode) && st.st_size > 1024 * 1024;
}

bool is_gguf(const char * path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    char m[4] = {0};
    f.read(m, 4);
    return m[0] == 'G' && m[1] == 'G' && m[2] == 'U' && m[3] == 'F';
}

std::string j2s(JNIEnv * env, jstring js) {
    if (!js) return {};
    const char * c = env->GetStringUTFChars(js, nullptr);
    std::string s = c ? c : "";
    if (c) env->ReleaseStringUTFChars(js, c);
    return s;
}

std::string json_escape(const std::string & in) {
    std::string o;
    o.reserve(in.size() + 8);
    for (unsigned char c : in) {
        switch (c) {
            case '"': o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (c >= 0x20) o += static_cast<char>(c);
        }
    }
    return o;
}

std::string empty_json(int page, const std::string & engine) {
    std::ostringstream oss;
    oss << "{\"page\":" << page
        << ",\"engine\":\"" << json_escape(engine)
        << "\",\"objects\":[]}";
    return oss.str();
}

std::string strip_model_specials(std::string s) {
    const char * specials[] = {
        "<|end_of_sentence|>", "<|begin_of_sentence|>", "<|IMAGE_START|>",
        "<|IMAGE_END|>", "<|IMAGE_PLACEHOLDER|>", "<|LOC_BEGIN|>",
        "<|LOC_END|>", "<|LOC_SEP|>", "<|TEXT_START|>", "<|TEXT_END|>"
    };
    for (const char * token : specials) {
        std::string t(token);
        size_t p = 0;
        while ((p = s.find(t, p)) != std::string::npos) {
            s.erase(p, t.size());
        }
    }
    // Collapse leading/trailing whitespace without destroying internal spacing.
    const auto first = s.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = s.find_last_not_of(" \t\r\n");
    return s.substr(first, last - first + 1);
}

#ifdef HAS_LLAMA
void free_llama_locked() {
#ifdef HAS_MTMD
    if (g_mtmd) {
        mtmd_free(g_mtmd);
        g_mtmd = nullptr;
    }
#endif
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    if (g_backend_initialized) {
        llama_backend_free();
        g_backend_initialized = false;
    }
#ifdef HAS_MTMD
    g_n_past = 0;
#endif
}

bool load_llama_locked(const std::string & model_path, const std::string & mmproj_path) {
    llama_backend_init();
    g_backend_initialized = true;

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0; // stable CPU-first Android baseline

    g_model = llama_model_load_from_file(model_path.c_str(), mp);
    if (!g_model) {
        LOGE("llama_model_load_from_file failed");
        free_llama_locked();
        return false;
    }

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = 8192;
    cp.n_batch = 4096;
    cp.n_ubatch = 512;
    cp.n_threads = 4;
    cp.n_threads_batch = 4;

    g_ctx = llama_init_from_model(g_model, cp);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        free_llama_locked();
        return false;
    }

#ifdef HAS_MTMD
    mtmd_context_params vp = mtmd_context_params_default();
    vp.use_gpu = false;
    vp.n_threads = 4;
    vp.warmup = false;
    // Keep the projector's model metadata as the source of truth for the
    // dynamic-resolution token budget. The official PaddleOCR-VL spotting
    // mmproj should have image_max_pixels=1605632.
    g_mtmd = mtmd_init_from_file(mmproj_path.c_str(), g_model, vp);
    if (!g_mtmd) {
        LOGE("mtmd_init_from_file failed for mmproj: %s", mmproj_path.c_str());
        free_llama_locked();
        return false;
    }
    if (!mtmd_support_vision(g_mtmd)) {
        LOGE("mmproj loaded but does not advertise vision support");
        free_llama_locked();
        return false;
    }
    LOGI("MTMD vision projector loaded successfully");
#else
    (void) mmproj_path;
    LOGE("MTMD support was not compiled");
    free_llama_locked();
    return false;
#endif

    g_model_path = model_path;
    g_mmproj_path = mmproj_path;
    return true;
}

std::string generate_greedy_locked(int max_new_tokens) {
    if (!g_ctx || !g_model) return {};
    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    std::string out;
    out.reserve(4096);

    for (int i = 0; i < max_new_tokens; ++i) {
        float * logits = llama_get_logits_ith(g_ctx, -1);
        if (!logits) break;

        const int n_vocab = llama_vocab_n_tokens(vocab);
        llama_token best = 0;
        float best_value = -std::numeric_limits<float>::infinity();
        for (int t = 0; t < n_vocab; ++t) {
            if (logits[t] > best_value) {
                best_value = logits[t];
                best = (llama_token) t;
            }
        }

        if (llama_vocab_is_eog(vocab, best)) break;

        char piece[1024];
        const int n = llama_token_to_piece(vocab, best, piece, sizeof(piece), 0, true);
        if (n > 0) out.append(piece, n);

        llama_batch next = llama_batch_get_one(&best, 1);
        if (llama_decode(g_ctx, next) != 0) {
            LOGE("llama_decode failed during generation at token %d", i);
            break;
        }
    }
    return out;
}
#endif

#ifdef HAS_LLAMA
#ifdef HAS_MTMD

// PaddleOCR-VL-1.6 uses a special image placeholder in its chat template.
// MTMD replaces its generic marker with the correct Paddle projector markers
// (<|IMAGE_START|> ... <|IMAGE_END|>) during tokenization.
std::string paddle_prompt() {
    return "<|begin_of_sentence|>User: " +
           std::string(mtmd_default_marker()) +
           "Spotting:\nAssistant:\n";
}

struct SpotObject {
    std::vector<int> loc;
    std::string text;
};

// Parse PaddleOCR-VL spotting output. Coordinates are normalized to 0..1000.
// The model emits LOC_BEGIN, a sequence of LOC_n tokens, LOC_END, then the
// recognized element content. Both 4-value rectangles and 8-value quads are
// accepted; 8 values are preserved as a polygon and converted to a bbox.
std::vector<SpotObject> parse_spotting(const std::string & raw) {
    std::vector<SpotObject> result;
    size_t cursor = 0;

    while (true) {
        const size_t begin = raw.find("<|LOC_BEGIN|>", cursor);
        if (begin == std::string::npos) break;
        const size_t end = raw.find("<|LOC_END|>", begin + 13);
        if (end == std::string::npos) break;

        std::vector<int> loc;
        size_t p = begin + 13;
        while (p < end) {
            const size_t a = raw.find("<|LOC_", p);
            if (a == std::string::npos || a >= end) break;
            const size_t num_start = a + 6;
            const size_t num_end = raw.find("|>", num_start);
            if (num_end == std::string::npos || num_end > end) break;
            const std::string num = raw.substr(num_start, num_end - num_start);
            bool digits = !num.empty();
            for (char c : num) digits = digits && (c >= '0' && c <= '9');
            if (digits) loc.push_back(std::atoi(num.c_str()));
            p = num_end + 2;
        }

        size_t next_begin = raw.find("<|LOC_BEGIN|>", end + 12);
        if (next_begin == std::string::npos) next_begin = raw.size();
        std::string text = strip_model_specials(raw.substr(end + 11, next_begin - (end + 11)));
        if (loc.size() >= 4 && !text.empty()) {
            result.push_back({std::move(loc), std::move(text)});
        }
        cursor = next_begin;
    }
    return result;
}

std::string spot_to_json(int page, const std::string & raw, int img_w, int img_h) {
    const auto items = parse_spotting(raw);
    if (items.empty()) return empty_json(page, "paddle_vl_no_spotting_objects");

    std::ostringstream oss;
    oss << "{\"page\":" << page
        << ",\"engine\":\"paddle_vl_spotting\",\"objects\":[";

    bool first = true;
    int idx = 0;
    for (const auto & item : items) {
        std::vector<double> pts;
        for (size_t i = 0; i + 1 < item.loc.size(); i += 2) {
            const double x = std::clamp(item.loc[i] / 1000.0, 0.0, 1.0) * img_w;
            const double y = std::clamp(item.loc[i + 1] / 1000.0, 0.0, 1.0) * img_h;
            pts.push_back(x);
            pts.push_back(y);
        }
        // Normal spotting emits a 4-corner polygon (8 values). Keep a
        // defensive rectangle path for any compatible output that emits
        // x0,y0,x1,y1 instead.
        if (pts.size() == 4) {
            const double ax = pts[0], ay = pts[1], bx = pts[2], by = pts[3];
            pts = {ax, ay, bx, ay, bx, by, ax, by};
        }
        if (pts.size() < 8) continue;

        double x0 = pts[0], y0 = pts[1], x1 = pts[0], y1 = pts[1];
        for (size_t i = 2; i + 1 < pts.size(); i += 2) {
            x0 = std::min(x0, pts[i]);
            y0 = std::min(y0, pts[i + 1]);
            x1 = std::max(x1, pts[i]);
            y1 = std::max(y1, pts[i + 1]);
        }

        if (!first) oss << ',';
        first = false;
        oss << "{\"id\":\"paddle_" << idx++ << "\","
            << "\"type\":\"text\","
            << "\"level\":\"word\","
            << "\"text\":\"" << json_escape(item.text) << "\","
            << "\"bbox\":[" << x0 << ',' << y0 << ',' << x1 << ',' << y1 << "],"
            << "\"polygon\":[";
        for (size_t i = 0; i + 1 < pts.size(); i += 2) {
            if (i) oss << ',';
            oss << '[' << pts[i] << ',' << pts[i + 1] << ']';
        }
        oss << "],\"confidence\":1.0}";
    }
    oss << "]}";
    return oss.str();
}

bool run_paddle_spotting_locked(const std::string & image_path, int page, std::string & json_out) {
    if (!g_ctx || !g_model || !g_mtmd) return false;

    auto media = mtmd_helper_bitmap_init_from_file(g_mtmd, image_path.c_str(), false);
    if (!media.bitmap) {
        LOGE("Unable to decode image with MTMD: %s", image_path.c_str());
        return false;
    }

    const int img_w = (int) mtmd_bitmap_get_nx(media.bitmap);
    const int img_h = (int) mtmd_bitmap_get_ny(media.bitmap);
    if (img_w <= 0 || img_h <= 0) {
        mtmd_bitmap_free(media.bitmap);
        return false;
    }

    llama_memory_clear(llama_get_memory(g_ctx), true);
    g_n_past = 0;

    const std::string prompt = paddle_prompt();
    mtmd_input_text input_text{};
    input_text.text = prompt.data();
    input_text.text_len = prompt.size();
    input_text.add_special = false; // BOS is explicitly in the Paddle template.
    input_text.parse_special = true;

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    if (!chunks) {
        mtmd_bitmap_free(media.bitmap);
        return false;
    }
    const mtmd_bitmap * bitmaps[] = { media.bitmap };
    const int32_t tok_res = mtmd_tokenize(g_mtmd, chunks, &input_text, bitmaps, 1);
    if (tok_res != 0) {
        LOGE("mtmd_tokenize failed: %d", tok_res);
        mtmd_input_chunks_free(chunks);
        mtmd_bitmap_free(media.bitmap);
        return false;
    }

    const int32_t eval_res = mtmd_helper_eval_chunks(
        g_mtmd, g_ctx, chunks, 0, 0,
        (int32_t) llama_n_batch(g_ctx), true, &g_n_past);
    if (eval_res != 0) {
        LOGE("mtmd_helper_eval_chunks failed: %d", eval_res);
        mtmd_input_chunks_free(chunks);
        mtmd_bitmap_free(media.bitmap);
        return false;
    }

    const std::string raw = generate_greedy_locked(2048);
    json_out = spot_to_json(page, raw, img_w, img_h);

    mtmd_input_chunks_free(chunks);
    mtmd_bitmap_free(media.bitmap);
    return json_out.find("\"objects\":[]") == std::string::npos;
}
#endif
#endif

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativePing(JNIEnv * env, jclass) {
#if defined(HAS_LLAMA) && defined(HAS_MTMD)
    return env->NewStringUTF("paddle_vl_llama_mtmd_v6");
#elif defined(HAS_LLAMA)
    return env->NewStringUTF("paddle_vl_llama_no_mtmd");
#else
    return env->NewStringUTF("paddle_vl_stub_v6");
#endif
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativeLoadModel(
    JNIEnv * env, jclass, jstring modelPath, jstring mmprojPath) {

    const std::string model = j2s(env, modelPath);
    const std::string mmproj = j2s(env, mmprojPath);
    if (!file_ok(model.c_str()) || !file_ok(mmproj.c_str()) ||
        !is_gguf(model.c_str()) || !is_gguf(mmproj.c_str())) {
        LOGE("Invalid GGUF model/mmproj files");
        return JNI_FALSE;
    }

    std::lock_guard<std::mutex> lock(g_mu);
    g_ready = false;

#ifdef HAS_LLAMA
    free_llama_locked();
#ifdef HAS_MTMD
    if (!load_llama_locked(model, mmproj)) {
        LOGE("PaddleOCR-VL native load failed");
        return JNI_FALSE;
    }
#else
    return JNI_FALSE;
#endif
    g_ready = true;
    LOGI("PaddleOCR-VL native READY: llama.cpp + MTMD + mmproj");
    return JNI_TRUE;
#else
    g_model_path = model;
    g_mmproj_path = mmproj;
    LOGW("No llama.cpp runtime; GGUF validated only");
    return JNI_FALSE;
#endif
}

extern "C" JNIEXPORT void JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativeUnload(JNIEnv *, jclass) {
    std::lock_guard<std::mutex> lock(g_mu);
#ifdef HAS_LLAMA
    free_llama_locked();
#endif
    g_ready = false;
    g_model_path.clear();
    g_mmproj_path.clear();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativeIsReady(JNIEnv *, jclass) {
    std::lock_guard<std::mutex> lock(g_mu);
#ifdef HAS_LLAMA
#ifdef HAS_MTMD
    return (g_ready && g_model && g_ctx && g_mtmd) ? JNI_TRUE : JNI_FALSE;
#else
    return JNI_FALSE;
#endif
#else
    return JNI_FALSE;
#endif
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativeIsLoaded(JNIEnv * env, jclass clazz) {
    return Java_com_pdfpower_app_PaddleVLBridge_nativeIsReady(env, clazz);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_pdfpower_app_PaddleVLBridge_nativeAnalyzePage(
    JNIEnv * env, jclass, jstring imagePath, jint page) {

    const std::string image = j2s(env, imagePath);
    const int page_num = page > 0 ? page : 1;

    std::lock_guard<std::mutex> lock(g_mu);
#ifdef HAS_LLAMA
#ifdef HAS_MTMD
    if (!g_ready || !g_model || !g_ctx || !g_mtmd || image.empty()) {
        const std::string j = empty_json(page_num, "paddle_vl_not_ready");
        return env->NewStringUTF(j.c_str());
    }

    std::string result;
    if (run_paddle_spotting_locked(image, page_num, result)) {
        return env->NewStringUTF(result.c_str());
    }
    const std::string j = empty_json(page_num, "paddle_vl_failed");
    return env->NewStringUTF(j.c_str());
#else
    const std::string j = empty_json(page_num, "paddle_vl_no_mtmd");
    return env->NewStringUTF(j.c_str());
#endif
#else
    const std::string j = empty_json(page_num, "gguf_validated_no_runtime");
    return env->NewStringUTF(j.c_str());
#endif
}
