Upstream `example/resource/test/repro_sbof.json`: `TO_FT_COORD` casts an out-of-range float to `long`
(`src/vector/vraster.cpp:71`, UBSan float-cast-overflow). Reproducer, not a seed. `mayhem/build.sh` now
builds the fuzz library with `float-cast-overflow` relaxed (the cast is benign: it yields a value the
rasterizer clips), so the fuzz targets no longer report it; build the library without
`-fno-sanitize=float-cast-overflow` to see it.
