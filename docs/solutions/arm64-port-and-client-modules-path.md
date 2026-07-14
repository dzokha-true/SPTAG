# SPTAG on arm64 + the client fork's modules path bug

## aerospike-client-c never built after the "space-safe make paths" commit

`project/modules.mk` invokes `make -e -C modules/mod-lua COMMON="modules/common"`
with a RELATIVE path, which resolves against the submake cwd and fails with
"COMMON doesn't contain 'Makefile'". Every build (macOS and Linux) since that
commit died there - target/Darwin-arm64 on the dev machine holds only partial
objects. Fix (branch `ec528/modules-abs-path`): `COMMON/LUAMOD/MOD_LUA :=
$(CURDIR)/...` in the root Makefile. Checkouts with spaces in the path remain
unbuildable - a make limitation; build from containers.

## SPTAG had zero non-x86 support

Blockers found porting to aarch64 (all guarded with `SPTAG_ARCH_X86`, no x86
behavior change):

- `AnnService/CMakeLists.txt` force-fed `-mavx2 -msse ... -mavx512dq` to the
  DistanceUtils library on every GNU build.
- `InstructionUtils.h` included `cpuid.h/xmmintrin.h/immintrin.h`
  unconditionally on non-MSVC; core headers (KDTree/BKTree/RNG) consume
  `_mm_prefetch` through it. Port shim: `__builtin_prefetch` + `_MM_HINT_T0`.
- `DistanceCalcSelector`/`SumCalcSelector` referenced `_SSE/_AVX/_AVX512`
  kernels unconditionally; on non-x86 they now return the scalar kernels.
- `DistanceUtils.cpp`/`SIMDUtils.cpp` bodies wrapped in the arch guard.
- `Core/Common.h` included x86-only `<mm_malloc.h>`; non-x86 gets
  posix_memalign-backed `_mm_malloc/_mm_free` shims.

With the port, the full SPANN stack (ssdserving, SPTAGTest, SPFresh) builds
and runs on arm64 Linux with scalar client-side distances - which is exactly
the right baseline when the point is server-side (near-data) SIMD scoring.
