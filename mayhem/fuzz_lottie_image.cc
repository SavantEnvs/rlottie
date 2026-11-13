// libFuzzer harness: the stb_image decoder rlottie uses for images embedded in an animation (PNG/JPEG).
#include <cstddef>
#include <cstdint>

extern "C" {
unsigned char *lottie_image_load_from_data(const char *imageData, int len, int *x, int *y,
                                           int *comp, int req_comp);
void           lottie_image_free(unsigned char *data);
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size == 0 || size > 0x7fffffff) return -1;
    int            x = 0, y = 0, n = 0;
    unsigned char *pixels = lottie_image_load_from_data(reinterpret_cast<const char *>(data),
                                                         static_cast<int>(size), &x, &y, &n, 4);
    if (!pixels) return -1;
    lottie_image_free(pixels);
    return 0;
}
