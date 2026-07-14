#ifndef _SPTAG_COMMON_INSTRUCTIONUTILS_H_
#define _SPTAG_COMMON_INSTRUCTIONUTILS_H_

#include <string>
#include <vector>
#include <bitset>
#include <array>

#ifndef GPU

// EC528: x86 headers/intrinsics only exist on x86; on other architectures
// (e.g. aarch64) provide a prefetch shim and no CPUID. InstructionSet then
// reports no x86 ISA support and the distance selectors fall back to the
// portable scalar kernels. No behavior change on x86.
#if defined(__x86_64__) || defined(__i386__) || defined(_M_X64) || defined(_M_IX86)
#define SPTAG_ARCH_X86 1
#endif

#if !defined(_MSC_VER) && defined(SPTAG_ARCH_X86)
#include <cpuid.h>
#include <xmmintrin.h>
#include <immintrin.h>

void cpuid(int info[4], int InfoType);

#elif defined(_MSC_VER) && defined(SPTAG_ARCH_X86)
#include <intrin.h>
#define cpuid(info, x)    __cpuidex(info, x, 0)
#else
#ifndef _MM_HINT_T0
#define _MM_HINT_T0 3
#endif
static inline void _mm_prefetch(const char* p, int hint)
{
    (void)hint;
    __builtin_prefetch(p);
}
#endif

#endif

namespace SPTAG {
    namespace COMMON {

        class InstructionSet
        {
            // forward declarations
            class InstructionSet_Internal;

        public:
            // getters
            static bool AVX(void);
            static bool SSE(void);
            static bool SSE2(void);
            static bool AVX2(void);
            static bool AVX512(void);
            static void PrintInstructionSet(void);

        private:
            static const InstructionSet_Internal CPU_Rep;

            class InstructionSet_Internal
            {
            public:
                InstructionSet_Internal();
                bool HW_SSE;
                bool HW_SSE2;
                bool HW_AVX;
                bool HW_AVX2;
                bool HW_AVX512;
            };
        };
    }
}

#endif
