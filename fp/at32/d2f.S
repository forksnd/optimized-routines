// Double-precision to single-precision conversion.
//
// Copyright (c) 1994-1998,2025, Arm Limited.
// SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception

#include "endian.h"

  .syntax unified
  .text
  .p2align 2

  .globl arm_fp_d2f
  .type arm_fp_d2f,%function
arm_fp_d2f:

  // Start with the fast path, dealing with input values that give a normalized
  // single-precision output. We handle these as quickly as possible in
  // straight-line code, and branch out of line to a single 'handle everything
  // else' label which will have to figure out what kind of unusual thing has
  // happened.

  // Split ah into the sign bit (in r3) and everything else (r2), so that we
  // can change the width of the exponent field and then put the sign back on
  // later.
  BIC     r2, ah, #0x80000000
  AND     r3, ah, #0x80000000

  // Rebias the exponent, still in its double-precision location, to account
  // for the difference between double- and single-precision exponents.
  SUB     r2, r2, #(0x3ff-0x7f) << 20

  // If the exponent field is now 0 or less, we have an underflow or an exact
  // zero. If it's 0xFF or more, we have an overflow, or a NaN or infinity as
  // input. Detect all of those in a combined test, and branch out of line.
  CMP     r2, #0x00100000       // LO if output too small
  RSBSHS  r12, r2, #0x0ff00000  // otherwise, set LS if output too large
  BLS     d2f_uncommon          // so now LS means one or the other happened

  // We've disposed of all the uncommon cases, so we know we're returning a
  // normalized float, but we might still need to round it. Shift the round bit
  // into the C flag, also setting Z if everything below that is zero.
  LSLS    r12, al, #4

  // Put the result back together, by recombining the sign (in r3) with the
  // exponent and top of the mantissa (in r2, needing to be shifted left 3
  // bits), plus the top 3 bits of al. The last of those is put on with an ADC
  // instruction, which also rounds up if the bit we just shifted into C was
  // set.
  ORR     r2, r3, r2, LSL #3    // sign + exponent + most of mantissa
  ADC     r0, r2, al, LSR #29   // low 3 bits of mantissa + maybe round up

  // If C=1 and Z=1, we need to round to even. Otherwise we're finished. So we
  // conditionally return based on one of those flags, then clear the low
  // output bit based on the other.
  //
  // Which way round? On the assumption that input mantissas are roughly
  // uniformly distributed, _almost all_ input doubles will contain a 1 bit
  // somewhere in the bottom 28 bits, so we return early in the vast majority
  // of cases by testing Z first. If we tested C first, we'd expect to return
  // early only half the time, costing two extra instructions half the time
  // instead of 1/2^28 of the time.
  //
  // (That's a bit optimistic, because of course in some situations input
  // mantissas _won't_ be that uniform. In particular, if you converted from a
  // float, did a small amount of calculation in double, and converted back,
  // the round-to-even case might come up more often. But at least _some_
  // applications will be passing doubles that make use of the whole mantissa,
  // so I think this is still the more sensible way round to do the test.)
  BXNE    lr                    // return if Z=0
  BICCS   r0, r0, #1            // Z=1, so round to even if C=1 too
  BX      lr                    // and now return unconditionally

d2f_uncommon:
  // We come here if anything at all goes wrong on the fast path. We could have
  // an interesting kind of input - zero, denormal, infinity or NaN - or we
  // could have a normalized double-precision input too large or too small to
  // yield a normalized single-precision output.
  //
  // Of the various cases, the most important one to handle quickly is a zero
  // input, because those are probably fairly common. So the very first thing
  // we do is test if the input is zero, and if so, return the same sign of
  // zero by simply using ah as the return value.
  ORRS    r12, al, ah, LSL #1   // are all bits of ah:al 0 except the sign bit?

#ifndef __BIG_ENDIAN__
  // In little-endian, ah (containing the desired sign bit) and r0 (the output
  // register) aren't the same. This instruction can be skipped in big-endian,
  // where the correct output value is already in r0.
  MOVEQ   r0, ah
#endif
  BXEQ    lr

  // Separate the remaining cases into three types: too small (underflow,
  // whether or not the input was a denormal), too big (overflow or input
  // infinity, which we treat the same in the absence of FP exceptions), and
  // NaN.
  //
  // At this stage r2 contains the output exponent, rebiased to its
  // single-precision value, but at bit 20 (that is, still in the
  // double-precision position). Detect underflow by doing a signed comparison
  // against the minimum normalized single-precision exponent.
  CMP     r2, #0x00100000
  BLT     d2f_underflow

  // Now figure out whether we had a NaN as input, by shifting ah left by a bit
  // (discarding the sign) and setting the new low bit if al != 0. This gives a
  // value which is greater than 0xFFE00000 (in an unsigned comparison) for
  // precisely NaN inputs.
  CMP     al, #1                // set C if al != 0
  ADC     r12, ah, ah           // shift that in to the bottom of ah
  CMN     r12, #0x00200000      // is the result > 0xFFE00000?
  BHI     d2f_nan               // if so, go and handle a NaN

  // If we're still here, we have a finite overflow, or an input infinity. We
  // don't have to figure out which: we return an infinity of the appropriate
  // sign in both cases. So keep just the sign of ah, and make an infinity out
  // of the rest of the bits.
  MVN     r0, ah, LSR #31       // shift sign bit down to bit 0 and flip it
  MVN     r0, r0, LSL #8        // flip it back, putting 8 set bits below it
  LSL     r0, r0, #23           // and shift those 9 bits back up to the top
  BX      lr

d2f_nan:
  // We have a double-precision NaN input. The Arm NaN handling rules say that
  // we make the output single-precision NaN by keeping the sign and as much of
  // the mantissa as possible (starting from the top bit). But we also set the
  // top bit of the mantissa, which makes the output NaN quiet even if the
  // input one was signaling.
  //
  // So this code looks a bit like a miniature version of the fast path: we
  // keep the bottom 8 bits of the exponent in ah as the output exponent (we
  // know it's all 1s, which is what we want), plus all the mantissa bits below
  // it; shift all of that 3 bits left and recombine with the sign; then
  // combine with the top 3 bits of al. Finally, set the top mantissa bit.
  BIC     r2, ah, #0xF0000000   // everything from ah we want to shift left
  ORR     r0, r3, al, LSR #29   // combine sign with low 3 output mantissa bits
  ORR     r0, r0, r2, LSL #3    // combine that with the shifted-up value in r2
  ORR     r0, r0, #0x00400000   // set the top mantissa bit to make it a QNaN
  BX      lr

d2f_underflow:
  // We have an input value small enough to underflow. The basic strategy is to
  // leave __funder to deal with the details.
  //
  // Normally __funder expects to get a value that's already been rounded, and
  // will re-round it, for which it also needs to know which way the value has
  // been rounded already. In this case we haven't rounded _yet_. Rather than
  // carefully rounding to nearest, it's easier to just make the __funder input
  // value by truncating the mantissa (i.e. round towards zero), and set the
  // rounding direction accordingly.

  // Rebias the exponent (again) to make an IEEE 754 underflow intermediate. If
  // this still doesn't make r2 positive, then the result is so small that it
  // will underflow to 0 anyway, so it doesn't really matter what exponent we
  // do provide - we just clear the top 8 bits of r2 to ensure the sign is
  // right and the exponent is _something_ small.
  ADDS    r2, r2, #0x0c000000   // exponent bias (still shifted down 3 bits)
  BICMI   r2, r2, #0xff000000   // handle exponent still being negative

  // Test the bits we're going to shift off the mantissa, to see if any are
  // zero. This will determine the rounding direction we pass to __funder,
  // because although we never round _up_ on this path, we must still tell it
  // whether the value we pass it was rounded down or was already exact.
  LSLS    r12, al, #3           // set Z if the intermediate value is exact

  // Put together the intermediate value to pass to __funder.
  ORR     r2, r3, r2, LSL #3    // sign + exponent + most of mantissa
  ORR     r0, r2, al, LSR #29   // combine with top 3 bits of al

  // Set the rounding direction flag based on the test above.
  MOVEQ   r1, #0                // intermediate is exact
  MOVNE   r1, #1                // intermediate is too small (we didn't round)

  // And tailcall __funder to do the rest of the job.
  B       __funder

  .size arm_fp_d2f, .-arm_fp_d2f
