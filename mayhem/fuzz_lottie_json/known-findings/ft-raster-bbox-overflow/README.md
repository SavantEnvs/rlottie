Valid animations whose frame leaves an empty raster bbox: `SW_FT_Raster_Render` computes
`ras.bound_right - ras.bound_left` on the INT_MIN/INT_MAX sentinels
(`src/vector/freetype/v_ft_raster.cpp:1391`, UBSan signed-integer-overflow). Kept out of `testsuite/`
because every seed must run rc 0; run any file here with `/mayhem/fuzz_lottie_json`.
