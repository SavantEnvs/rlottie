// Shared by the JSON and dotLottie harnesses: load the animation from memory, then drive the public
// read/render API the way an embedder would.
#pragma once
#include <rlottie.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// Returns 0 when the bytes were a loadable animation, -1 when the library rejected them.
static inline int exercise_animation(const uint8_t *data, size_t size)
{
    std::string json(reinterpret_cast<const char *>(data), size);
    // cachePolicy=false: no model cache, so each input is independent of the previous ones.
    std::unique_ptr<rlottie::Animation> anim =
        rlottie::Animation::loadFromData(std::move(json), "", "", false);
    if (!anim) return -1;

    size_t w = 0, h = 0;
    anim->size(w, h);
    (void)anim->frameRate();
    (void)anim->duration();
    (void)anim->markers();
    (void)anim->layers();

    size_t frames = anim->totalFrame();
    (void)anim->frameAtPos(0.5);

    const size_t kSide = 64;
    std::vector<uint32_t> buf(kSide * kSide);
    size_t picks[3] = {0, frames / 2, frames ? frames - 1 : 0};
    for (size_t frame : picks) {
        rlottie::Surface surface(buf.data(), kSide, kSide, kSide * 4);
        anim->renderSync(frame, surface);
        (void)anim->renderTree(frame, kSide, kSide);
    }
    return 0;
}
