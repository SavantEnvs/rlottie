// libFuzzer harness: dotLottie (zip) archive -> rlottie::Animation::loadFromData -> render.
#include "lottie_exercise.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // The loader only unzips input that starts with the zip local-file-header signature.
    if (size < 4 || data[0] != 0x50 || data[1] != 0x4B || data[2] != 0x03 || data[3] != 0x04)
        return -1;
    return exercise_animation(data, size);
}
