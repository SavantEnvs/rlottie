#!/usr/bin/env bash
#
# mayhem/build.sh — build rlottie's fuzz harnesses (sanitized, instrumented) and its upstream test suite.
# Runs in the commit image as `mayhem` in /mayhem; re-runnable and offline (rlottie bundles every
# dependency: zip, freetype, pixman, stb, rapidjson).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
# CMake takes the compiler from the exported CC/CXX; passing -DCMAKE_*_COMPILER=clang makes a re-run (CMake
# resolves the name to /usr/bin/clang) wipe the cache and drop every other -D of that invocation.
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# `build/` is covered by upstream's .gitignore, so both trees below vanish on `git clean -ffdX`.
FUZZ_DIR="$SRC/build/fuzz"
TEST_DIR="$SRC/build/tests"

# 1) The library for fuzzing: static, sanitized, DWARF 3, with SanCov (-fsanitize=fuzzer-no-link)
#    on the library itself so Mayhem sees coverage of the fuzzed code. LOTTIE_MODULE=OFF links stb_image
#    in statically instead of dlopen()ing librlottie-image-loader.so (embedded images then decode).
#    A custom build type keeps CMake from adding -DNDEBUG/-O flags of its own (asserts stay on).
#    Benign upstream UB patterns fire on every valid input and would halt the target before it fuzzes
#    anything: VArenaAlloc computes null+offset from a fresh arena (pointer-overflow), the rasterizer calls a
#    callback through a mismatched pointer type (function), layer code binds members of an unallocated
#    CApiData (null; real null derefs still SEGV under ASan); those three are relaxed with
#    -fno-sanitize), and miniz does unaligned u32 loads (its own MINIZ_USE_UNALIGNED_LOADS_AND_STORES=0
#    switch selects the byte-wise readers). Two more flood on benign patterns: float-cast-overflow (the
#    animation's float colors, coordinates and time-remap values are cast to int/long unchecked in
#    Color::toColor, TO_FT_COORD, Layer::timeRemap and ShapeLayer::render; clang yields a saturated or
#    INT_MIN value that the renderer then clips, with no memory effect) and shift-base (255<<24 into the
#    sign bit of an int in VColor::premulARGB, defined by clang). Left halting, they produced 15 of
#    the 18 defects of a 5-minute run and would mask any deeper bug. Overflowing *integer*
#    arithmetic (signed-integer-overflow), bounds and the rest of UBSan stay on, so the raster bbox
#    overflow in v_ft_raster.cpp is still reported. ASan and the rest of UBSan stay on and halting.
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link -fno-sanitize=pointer-overflow,function,null,float-cast-overflow,shift-base -DMINIZ_USE_UNALIGNED_LOADS_AND_STORES=0"
cmake -S . -B "$FUZZ_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Fuzz -DBUILD_SHARED_LIBS=OFF -DLOTTIE_MODULE=OFF \
    -DCMAKE_C_FLAGS="$FUZZ_CFLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_CFLAGS" \
    -DCMAKE_ASM_FLAGS="$FUZZ_CFLAGS" \
    -DCMAKE_C_FLAGS_FUZZ="" -DCMAKE_CXX_FLAGS_FUZZ="" -DCMAKE_ASM_FLAGS_FUZZ=""
cmake --build "$FUZZ_DIR" --target rlottie -j"$MAYHEM_JOBS"
LIB="$FUZZ_DIR/librlottie.a"

# 2) Harnesses, each linked twice: the libFuzzer binary and a run-once -standalone reproducer.
#    The standalone driver is C, so it is compiled as a C object (clang++ would mangle its harness ref).
HARNESS_CXXFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++14 -I$SRC/inc"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FUZZ_DIR/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_DIR/standalone_main.o"
for t in fuzz_lottie_json fuzz_lottie_dotlottie fuzz_lottie_image; do
    $CXX $HARNESS_CXXFLAGS "$SRC/mayhem/$t.cc" "$FUZZ_DIR/lsan_off.o" "$LIB" \
        $LIB_FUZZING_ENGINE -lpthread -ldl -o "$SRC/$t"
    $CXX $HARNESS_CXXFLAGS "$SRC/mayhem/$t.cc" "$FUZZ_DIR/lsan_off.o" "$FUZZ_DIR/standalone_main.o" "$LIB" \
        -lpthread -ldl -o "$SRC/$t-standalone"
done

# 3) The upstream gtest suites + a known-answer probe, with the project's NORMAL flags (no sanitizers,
#    no DWARF override), so mayhem/test.sh only runs them. The sanitizer/env flags must not leak in.
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S . -B "$TEST_DIR" -G Ninja \
    -DLOTTIE_TEST=ON -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$TEST_DIR" --target vectorTestSuite animationTestSuite -j"$MAYHEM_JOBS"
$CXX -O1 -std=c++14 $COVERAGE_FLAGS -I"$SRC/inc" "$SRC/mayhem/kat.cc" \
    -L"$TEST_DIR" -lrlottie -Wl,-rpath,"$TEST_DIR" -o "$TEST_DIR/rlottie_kat"
