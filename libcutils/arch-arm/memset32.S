/*
 * Copyright (C) 2006 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
/* Copyright (C) ST-Ericsson SA 2011
 *
 * Added Neon hybrid implementation
 */
/*
 *  memset32.S
 *
 */

#include <machine/asm.h>
#include <machine/cpu-features.h>

    .text
    .align
#if defined(__ARM_NEON__)
    .fpu    neon
#endif
    .global android_memset32
    .type   android_memset32, %function
    .global android_memset16
    .type   android_memset16, %function

        /*
         * Optimized memset32 and memset16 for ARM.
         *
         * void android_memset16(uint16_t* dst, uint16_t value, size_t size);
         * void android_memset32(uint32_t* dst, uint32_t value, size_t size);
         *
         */

android_memset16:
        .fnstart
        cmp         r2, #1
        bxle        lr

        /* expand the data to 32 bits */
        mov         r1, r1, lsl #16
        orr         r1, r1, r1, lsr #16

        /* align to 32 bits */
        tst         r0, #2
        strneh      r1, [r0], #2
        subne       r2, r2, #2
        .fnend

android_memset32:
        .fnstart
#if defined(__ARM_NEON__) && defined(MEMSET_NEON_DIVIDER)
        cmp         r2, #MEMSET_NEON_DIVIDER
        bhi         android_memset32_arm

        vdup.32     q0, r1

#ifndef NEON_UNALIGNED_ACCESS
        /* do we have at least 16-bytes to write (needed for alignment below) */
        cmp         r2, #16
        blo         3f

        /* align destination to 16 bytes for the write-buffer */
        rsb         r3, r0, #0
        ands        r3, r3, #0xF
        beq         2f

        /* write up to 15-bytes (count in r3) */
        sub         r2, r2, r3
        tst         r3, #2
        strneh      r1, [r0], #2
        movs        ip, r3, lsl #28
        strmi       r1, [r0], #4
        bcc         1f
        vst1.32     {d0}, [r0, :64]!
1:
#endif
        /* make sure we have at least 32 bytes to write */
        subs        r2, r2, #32
        blo         2f
        vmov        q1, q0

1:      /* The main loop writes 32 bytes at a time */
        subs        r2, r2, #32
#ifndef NEON_UNALIGNED_ACCESS
        vst1.32     {d0 - d3}, [r0, :128]!
#else
        vst1.32     {d0 - d3}, [r0]!
#endif
        bhs         1b

2:      /* less than 32 left */
        add         r2, r2, #32
3:      movs        ip, r2, lsl #28
        bcc         1f
#ifndef NEON_UNALIGNED_ACCESS
        vst1.32     {d0, d1}, [r0, :128]!
#else
        vst1.32     {d0, d1}, [r0]!
#endif
1:      bge         2f
        vst1.32     {d0}, [r0]!
2:      movs        ip, r2, lsl #30
        strcs       r1, [r0], #4
        strmih      r1, [r0], #2
        bx          lr

android_memset32_arm:
#endif
        .save       {lr}
        str         lr, [sp, #-4]!

        /* align the destination to a cache-line */
        mov         r12, r1
        mov         lr, r1
        rsb         r3, r0, #0
        ands        r3, r3, #0x1C
        beq         .Laligned32
        cmp         r3, r2
        andhi       r3, r2, #0x1C
        sub         r2, r2, r3

        /* conditionally writes 0 to 7 words (length in r3) */
        movs        r3, r3, lsl #28
        stmcsia     r0!, {r1, lr}
        stmcsia     r0!, {r1, lr}
        stmmiia     r0!, {r1, lr}
        movs        r3, r3, lsl #2
        strcs       r1, [r0], #4

.Laligned32:
        mov         r3, r1
1:      subs        r2, r2, #32
        stmhsia     r0!, {r1,r3,r12,lr}
        stmhsia     r0!, {r1,r3,r12,lr}
        bhs         1b
        add         r2, r2, #32

        /* conditionally stores 0 to 30 bytes */
        movs        r2, r2, lsl #28
        stmcsia     r0!, {r1,r3,r12,lr}
        stmmiia     r0!, {r1,lr}
        movs        r2, r2, lsl #2
        strcs       r1, [r0], #4
        strmih      lr, [r0], #2

        ldr         lr, [sp], #4
        bx          lr
        .fnend
