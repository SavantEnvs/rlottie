// Known-answer probe for mayhem/test.sh, linked dynamically against the NORMAL-flags librlottie.so.
// Prints facts computed by the library from fixed inputs; test.sh compares them to exact values.
#include <rlottie.h>

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

static const char *kInline =
    "{\"v\":\"5.0.0\",\"fr\":25,\"ip\":0,\"op\":50,\"w\":200,\"h\":100,\"nm\":\"kat\",\"ddd\":0,"
    "\"assets\":[],\"layers\":[{\"ddd\":0,\"ind\":1,\"ty\":1,\"nm\":\"Solid\",\"sr\":1,"
    "\"ks\":{\"o\":{\"a\":0,\"k\":100},\"r\":{\"a\":0,\"k\":0},\"p\":{\"a\":0,\"k\":[100,50,0]},"
    "\"a\":{\"a\":0,\"k\":[100,50,0]},\"s\":{\"a\":0,\"k\":[100,100,100]}},\"ao\":0,"
    "\"sw\":200,\"sh\":100,\"sc\":\"#ff0000\",\"ip\":0,\"op\":50,\"st\":0,\"bm\":0}]}";

static void describe(const char *tag, rlottie::Animation *a)
{
    size_t w = 0, h = 0;
    a->size(w, h);
    std::printf("%s frames=%zu size=%zux%zu fps=%g duration=%g layers=%zu\n", tag, a->totalFrame(),
                w, h, a->frameRate(), a->duration(), a->layers().size());
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    std::string dir = argv[1];

    auto missing = rlottie::Animation::loadFromFile(dir + "/does-not-exist.json", false);
    std::printf("missing=%s\n", missing ? "loaded" : "null");

    auto garbage = rlottie::Animation::loadFromData("this is not json", "k", "", false);
    std::printf("garbage=%s\n", garbage ? "loaded" : "null");

    auto mask = rlottie::Animation::loadFromFile(dir + "/mask.json", false);
    if (!mask) { std::printf("mask=null\n"); return 1; }
    describe("mask", mask.get());

    auto solid = rlottie::Animation::loadFromData(kInline, "kat", "", false);
    if (!solid) { std::printf("solid=null\n"); return 1; }
    describe("solid", solid.get());

    // Render the opaque red solid into a 200x100 surface: every pixel is premultiplied ARGB 0xffff0000.
    std::vector<uint32_t> buf(200 * 100, 0);
    rlottie::Surface      surface(buf.data(), 200, 100, 200 * 4);
    solid->renderSync(10, surface);
    size_t red = 0;
    for (uint32_t px : buf) red += (px == 0xffff0000u);
    std::printf("solid red_pixels=%zu corner=%08x center=%08x\n", red, buf[0], buf[50 * 200 + 100]);
    return 0;
}
