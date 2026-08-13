# Native PaddleOCR-VL 1.6 integration

Implemented in this release:
- llama.cpp + libmtmd CMake integration
- real GGUF text-model load
- real mmproj load through `mtmd_init_from_file`
- PNG/JPEG decode through MTMD helper
- PaddleOCR-VL `Spotting:` prompt with Paddle image markers
- multimodal evaluation through `mtmd_helper_eval_chunks`
- greedy token generation
- LOC token parsing into normalized page-image coordinates
- bbox + polygon JSON output
- empty-result fallback preserved for ML Kit/MuPDF
- page number propagated to native JSON

The runtime intentionally remains CPU-first (`n_gpu_layers=0`) for the arm64 Android baseline.
