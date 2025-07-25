// Single-precision to double-precision conversion.
//
// Copyright (c) 1994-1998,2025, Arm Limited.
// SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception

#include "endian.h"

  .syntax unified
  .text
  .p2align 2

  .globl arm_fp_f2d
  .type arm_fp_f2d,%function
arm_fp_f2d:

  // Start with the fast path, dealing with normalized single-precision inputs.
  // We handle these as quickly as possible in straight-line code, and branch
  // out of line to a single 'handle everything else' label which will have to
  // figure out what kind of unusual thing has happened.

  // Extend the exponent field by 3 bits, by shifting the sign bit off the top
  // of r0 into the carry flag, shifting the rest of the input word right by 3,
  // then using RRX to put the sign back. So we end up with a word shaped like
  // the top half of a double, but the exponent field is still biased by the
  // single-precision offset of 0x7f instead of the double-precision 0x3ff.
  LSLS    r3, r0, #1
  LSR     r12, r3, #3
  RRX     r12, r12

  // For a normalized number, the remaining steps are to rebias the exponent,
  // recover the remaining 3 mantissa bits from r0 which aren't included in the
  // word we've just made, and move both into the right output registers.
  //
  // But we must also check for the difficult cases. These occur when the input
  // exponent is either 0 or 0xFF. Those two values can be identified by the
  // property that exp XOR (exp << 1) has the top 7 bits all zero.

  // Do the test for uncommon values. Instead of using a shifter operand in the
  // obvious way (EOR output, r0, r0, LSL #1), we use the fact that the setup
  // code above already has a shifted-left copy of the input word in r3. In
  // Thumb, this makes the EORS a 16-bit instruction instead of 32-bit.
  EORS    r3, r3, r0

  // Now prepare the output, for normal inputs.
  //
  // We make this pair of instructions conditional on NE, i.e. we skip it if r3
  // and r0 were actually equal (which could only happen if r0 was 0, i.e. the
  // input was +0). This is fine, because in that situation the input wasn't
  // normalized, so we aren't going to return this output anyway.
  //
  // The _point_ of conditionalizing these two instructions is that this way we
  // have only one IT instruction on the fast path, and it's _here_, where this
  // comment is, so that it comes immediately after the above 16-bit EORS and
  // can be executed in the same cycle by Cortex-M3.
  LSLNE   al, r0, #29           // al now has the bottom 3 input mantissa bits
  ADDNE   ah, r12, #(0x3ff - 0x7f) << 20 // rebias exponent in ah

  // Finally, check whether the test word in r3 has its top 7 exponent bits
  // zero. If not, we can return the fast-path answer.
  TSTNE   r3, #0x7f000000
  BXNE    lr

  // Now we've handled the fast-path cases as fast as we know how, what do we
  // do next? We almost certainly don't have the input value in r0 any more,
  // because we overwrote it by writing an unused output to ah:al in the above
  // code. Worse, we didn't _reliably_ overwrite it, because those writes to
  // ah:al might not have happened if the whole test word in r3 was zero. So
  // where can we find the input bits?
  //
  // We have r3 = input XOR (input << 1). That's actually an invertible
  // transformation, so in principle we could recover the full original input
  // float from just r3. The quickest way to do that involves these five
  // instructions (in any order, since they commute):
  //
  //   EOR     r3, r3, r3, LSL #16
  //   EOR     r3, r3, r3, LSL #8
  //   EOR     r3, r3, r3, LSL #4
  //   EOR     r3, r3, r3, LSL #2
  //   EOR     r3, r3, r3, LSL #1
  //
  // But that's rather slow, and we can do better. r12 contains most of the
  // input bits in a more usable form: we inserted three zero bits between the
  // sign and the top of the exponent, but everything from the input is there
  // _somewhere_, except for the low 3 bits.
  //
  // However, on one code path below we'll use a subset of those EOR
  // instructions to recover the low 3 bits of the input.

  // First, find out whether the input exponent was 0 (zero or denormal), or
  // 0xFF (infinity or NaN). We know it was one of the two, or we would have
  // taken the early return from the fast path. So it's enough to test any
  // single bit of the exponent in r12.
  TST     r12, #1<<27           // bit 27 is topmost bit of the 8-bit exponent
  BNE     f2d_inf_or_nan

  // If we didn't take that branch, we have a denormal or zero. Zeroes are
  // likely to be common, so we'd prefer to handle those with highest priority.
  //
  // r3 = (input XOR (input << 1)) will take the values 0 or 0x80000000 for a
  // zero input. So it contains precisely the right value to return in ah.
  //
  // The BICS here combines the zeroing of al with the test of r3, because it
  // sets Z if and only if the input was one of those two values, and if so,
  // sets al=0.
  //
  // Unfortunately this has the side effect of clobbering al in the case where
  // we _don't_ take the early return, so now we've lost our verbatim copy of
  // the low 3 input bits! On the denormal-handling path we'll have to recover
  // those from r3 more awkwardly. But denormal handling is rare, and slow
  // anyway, so it's worth the awkwardness to save a cycle in the much more
  // common case of a zero input.
  BICS    al, r3, #0x80000000   // EQ if output is zero
  MOVEQ   ah, r3                // if so, copy input sign into ah
  BXEQ    lr                    // and return

  // Now we know we're dealing with a denormal, so we need to recover the whole
  // input mantissa. Most of it is in r12, but those last three bits now need
  // to be reconstructed from r3 by using part of the shift+EOR trick shown
  // above. We only need the left shifts by 1 and by 2, because the other three
  // don't affect the bottom 3 bits at all.
  EOR     r3, r3, r3, LSL #2
  EOR     r3, r3, r3, LSL #1
  AND     r3, r3, #7

  // Now r3 contains just the low bits of the mantissa. The rest of the
  // mantissa is in r12, shifted right by 3 bits, so this instruction rebuilds
  // the entire input mantissa in ah. (The exponent field is known to be zero,
  // and the sign bit at the top of r12 is discarded by the left shift.)
  ORR     ah, r3, r12, LSL #3

  // Renormalize that input mantissa so that its high bit is at the top of the
  // word.
  CLZ     r2, ah
  LSL     ah, ah, r2

  // Compute the right sign + exponent to go with that mantissa.
  //
  // If the input mantissa had had only its low bit set, then the input float
  // would be 2^-149, which has a double-precision exponent of 0x36a. In that
  // situation we'd have r2 = 31 (output from the CLZ). So we need the output
  // exponent to be (0x389 - r2). But the leading bit of the mantissa will
  // increment the exponent field when we add them together, so in fact we want
  // to calculate (0x388 - r2). That's particularly convenient, because 0x388
  // fits in an AArch32 immediate field!
  AND     r3, r12, #0x80000000  // get the sign bit from the top of r12
  ADD     r3, r3, #0x388 << 20  // add the exponent bias as calculated above
  SUB     r3, r3, r2, LSL #20   // subtract the CLZ output

  // Finally, distribute the normalized mantissa across the two output words,
  // and combine the top half with the exponent we just computed.
  LSLS    al, ah, #21           // low word = low 3 bits of normalized mantissa
  ADD     ah, r3, ah, LSR #11   // high word = sign + exp + rest of mantissa
  BX      lr

f2d_inf_or_nan:
  // We come here if the input was either infinity or a NaN. In this situation
  // we can be sure that the instructions that set up the fast-path return
  // value _did_ happen, because the input was nonzero. Also we branched away
  // before the test for a zero input clobbered al.
  //
  // So ah:al will contain what _would_ be the right output value if 0xFF were
  // not a special input: the exponent field will be 0x47f, and the sign and
  // mantissa will be in place.
  //
  // This is almost exactly what we really want to return, except for two
  // things: the exponent should be corrected to 0x7ff for an output infinity
  // or NaN, and if the mantissa is nonzero at all (so that we're returning a
  // NaN and not an infinity) then we should set its top bit to make it a quiet
  // NaN.
  ORRS    ah, ah, #0x7f000000   // set the missing bits in the exponent field
  ORRS    r2, al, ah, LSL #12   // is any bit of the mantissa set?
  ORRNE   ah, ah, #0x00080000   // if so, set the top mantissa bit
  BX      lr

  .size arm_fp_f2d, .-arm_fp_f2d
