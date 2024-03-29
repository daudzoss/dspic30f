;;; supports two canonical 16-bit number formats.
;;; 
;;; signed integer, when 2 left sign bits match:
;;;  1100 0000 0000 0000 = 0xc000 = -16384
;;;  .
;;;  .
;;;  .
;;;  1111 1111 1111 1111 = 0xffff = -1
;;;  0000 0000 0000 0000 = 0x0000 = 0
;;;  0000 0000 0000 0001 = 0x0001 = 1
;;;  .
;;;  .
;;;  .
;;;  0011 1111 1111 1111 = 0x3fff = 16383
;;;
;;; signed ratio, when bit 14 and sign disagree:
;;;  10                  = negative quantity
;;;  01                  = positive quantity
;;;    00 0000 0         = 0x0000 = denominator 1
;;;  .
;;;  .
;;;  .
;;;    11 1111 1         = 0x3f80 = d'minator 128
;;;             000 0000 = 0x0000 = numerator 1
;;;  .
;;;  .
;;;  .
;;;             111 1111 = 0x007f = numerator 128

.equ	SIGNB,15
.equ	FORMATB,14
	
;;; w: input register int16_t in the format sfxx xxxx xxxx xxxx
;;; c: output flag 0 if s=f, 1 if s!=f (the definition of ratio representation)
.macro	isratio	w
	btst.c	\w,#SIGNB	; c = (w < 0); // 1 if a ratio
	btsc	\w,#FORMATB	; if (w & (1<<FORMATB))
	btg	0x42,#0 ; SR,#C	;  c = ~c;
.endm

;;; num: input literal or register int8_t, -128 < num < +128
;;; rat: output register ratio_t in the format sf00 0000 0nnn nnnn
.macro	toratio num,rat
	mov	\num,\rat	; rat = num;
;	ior	\rat,\rat,\rat	;
;	bra	z,Lend\@toratio	; if (rat) { // 0 can't be represented as ratio
	btsc	\rat,#SIGNB	;  if (rat < 0)
	neg.b	\rat,\rat	;   rat = (0xff00 & rat) | (0x00ff & -rat);
	cp0	\rat		;
	bra	z,Lend\@toratio	;  if (rat) { // 0 can't be represented as ratio
	dec.b	\rat,\rat	;   rat--; // map 1..128 onto 0..127
	and.b	#0x7f,\rat	;   rat &= 0x807f; // clear denominator (i.e. 1)
	btg	\rat,#FORMATB	;   rat |= (rat & 0x8000) >> 1; // flag as ratio
	bclr	\rat,#FORMATB-1	;
	bclr	\rat,#FORMATB-2	;
	bclr	\rat,#FORMATB-3	;
	bclr	\rat,#FORMATB-4	;
	bclr	\rat,#FORMATB-5	;
	bclr	\rat,#FORMATB-6	;  }
;	bclr	\rat,#FORMATB-7	; }
Lend\@toratio:
.endm

;;; rat: input register ratio_t in the format sfdd dddd dnnn nnnn
;;; numden: output register struct { uint7_t /*upper*/ den, /*lower*/ num; }
.macro	spl_rat	rat,numden
	mov	#0x3fff,\numden	;
	and \numden,\rat,\numden;
	sl	\numden,\numden	;
	lsr.b	\numden,\numden	; numden = (0x7f00 & (rat<<1)) | (0x007f & rat);
.endm

;;; numden: input register struct { uint7_t /*upper*/ den, /*lower*/ num; }
;;; packed: output register ratio_t in the unsigned format 00dd dddd dnnn nnnn
.macro	uns_rat	numden,packed
	sl.b	\numden,\packed	;
	lsr	\packed,\packed	; packed = ((0x7f00&numden)>>1)|(0x007f&numden);
.endm
	
;;; numden: input register ratio_t in the format 00dd dddd dnnn nnnn
;;; sf: input register ratio_t in the format sf00 0000 0000 0000
;;; sf: output register ratio_t in the format sfdd dddd dnnn nnnn
.macro	combine	numden,sf
	lsr	\sf,#14,\sf	;
	sl	\sf,#14,\sf	; sf &= 0xc000;
	ior	\numden,\sf,\sf	; sf |= numden;
.endm

;;; rat: input/output register ratio_t in the format sfdd dddd dnnn nnnn
;;; tmp,tmp1,tmp2: scratch register(s)
;;; extent: input constant, 0=minimal/quick, 1=more thorough, 2=final(division!)
.macro	reratio	rat,tmp,tmp1,tmp2,extent
	;; check for trailing zeroes (both N-1 and D-1 odd)
	spl_rat	\rat,\tmp
	add	#0x101,\tmp	; tmp = 0x0101 + (0x7f00&(rat<<1))|(0x007f&rat);
Lshr\@reratio:	
	btsc	\tmp,#8		; // sign got lost, will need to restore at end!
	bra	Lnot\@reratio	;
	btsc	\tmp,#0		;
	bra	Lnot\@reratio	; while (tmp & 0x0101 == 0) {
	lsr	\tmp,\tmp	;  tmp >>= 1; // both num and den divided by two
	bra	Lshr\@reratio	; }
Lnot\@reratio:
	sub	#0x101,\tmp	; tmp -= 0x0101; combine(tmp, &rat);
	uns_rat	\tmp,\tmp
	combine	\tmp,\rat
	
;.if (\extent)
	;; full search for common factors
;	spl_rat	\rat,\tmp
;	add	#0x101,\tmp	;
;	factor \tmp,\tmp1,\tmp2
;	sub	#0x101,\tmp
;	uns_rat	\tmp,\tmp
;	combine	\tmp,\rat
;.endif
.endm

;;; rat: input union { ratio_t rat; int16_t integer }
;;; int8: output int16_t
;;; restore: input constant, 1 leave with unconvertible rat unmodified
.macro	tointif	rat,int8,restore
	mov	\rat,\int8	;
.if restore
	isratio	\int8		;
	bra	NC,Lend\@tointif	;
.endif
	sl	\int8,\int8	; // works with f or reg or lit, store sign in C
	swap	\int8		; // 7-bit numerator and bit 0 now in high byte
	and.b	#0x7f,\int8	; // FORMAT bit and 7-bit denom now in low byte
	swap	\int8		; // 7-bit numerator and bit 0 now in low byte
	rrnc	\int8,\int8	; // 7-bit numerator now in low 7 bits
.if restore
	bra	z,Lden1\@tointif; // leaves as ratio if denominator isn't unity
	btsc	0x42,#0 ; SR,#C	; if (c)
	bset	\int8,#SIGNB	;  int8 |= 1<<SIGNB; // negative (format left 0)
	btss	0x42,#0 ; SR,#C	; else
	bset	\int8,#FORMATB	;  int8 |= 1<<FORMATB; // positive (sign left 0)
	bra	Lend\@tointif	;
.else
	bra	nz,Lend\@tointif; if (rat & 0x3f80 == 0) // denominator is one
.endif
Lden1\@tointif:
	btss	0x42,#0 ; SR,#C	;  if (rat & (1<<SIGNB))
	neg	\int8,\int8	;   int8 = -(rat & 0x007f + 1);// carry is clear
	btsc	0x42,#0 ; SR,#C	;  else
	dec2	\int8,\int8	;   int8 = rat & 0x007f + 1; // carry is clear
	inc	\int8		;
Lend\@tointif:
.endm

.macro	toanint	rat,int8
	tointif	\rat,\int8,0
.endm

;;; del: input uint10_t delta to apply to (0 < delta < 254, sign in bit 9)...
;;; tot: input/output uint8_t running total according to...
;;; i: literal int1_t increment dir, -del or +del regardless of actual magnitude
.macro	bump_i	del,tot,i
.if (\i>0)
	btsc	\del,#9		; if ((i>0) && (del & 0x0200 != 0) // inc a neg
.else
	btss	\del,#9		;   ||(i<0) && (del & 0x0200 == 0)) // dec a pos
.endif
	sub.b	\tot,\del,\tot	;  tot -= del; // make total lower
.if (\i>0)
	btss	\del,#9		; else // inc a pos
.else
	btsc	\del,#9		;      // or dec a neg
.endif
	add.b	\tot,\del,\tot	;  tot += del; // make total higher
.endm
	
;;; rat: input ratio_t to adjust
;;; tmp: register uint16_t, clobbered
;;; i: literal int1_t increment to adjust by
.macro	bumprat	rat,tmp,i
.if (\i)
	sl	\rat,\tmp	; uint8_t tmp = rat << 1; // numerator*2 in low
	add.b	#0x02,\tmp	; tmp += 2; // convert 2*0..127 to 2*1...128
	lsr	\rat,#6,\rat	; rat >>= 6; // signs in high, denom*2 in low
	and.b	#0xfe,\rat	; rat &= 0xfffe; // denominator to add/subtract
	add.b	#0x02,\rat	; rat += 2; // convert 2*0..127 to 2*1...128

	bump_i	\rat,\tmp,\i
.if (\i & 1 == 0)
	bump_i	\rat,\tmp,\i
.endif
	bra	nz,Lno0\@bumprat; for (j=(i<0)?-i:i; j; j--) bump_1(rat,tmp,i);
	mov	#0x0002,\rat	; if (tmp & 0xfe == 0)
	mov.b	#0x02,\tmp	;  rat = tmp = 0x0002; // spoof to get 0x0000 
;	bra	nov,.+?		; // else if (/*overflow condition*/) {}
Lno0\@bumprat:	
	sub.b	#0x02,\rat	; // rat still holds sign, format, denominator:
	sub.b	#0x02,\tmp	; //  0000 00sf dddd ddd0 -> sfdd dddd d000 0000
	sl	\rat,#6,\rat	; // tmp holds new numerator:
	lsr.b	\tmp,\tmp	; //  fddd dddd nnnn nnn0
	ior.b	\tmp,\rat,\rat	; rat = (rat << 6) | (0x007f & (tmp >> 1));
.endif	
	reratio	\rat,\tmp
.endm	

.macro	mulnord	int9,fac,tmp2
	
.endm	

;;; sign: input any ratio_t sfdd dddd dnnn nnnn
;;; num: output int16_t numerator ssss ssss nnnn nnnn
;;; den: output uint16_t denominator 0000 0000 dddd dddd (after adding 1)
.macro	sgn_rat	sign,num,den
	spl_rat	\sign,\num
	add	#0x101,\num	;
	lsr	\num,#8,\den	; den = (0x007f & (sign>>7)) + 1;
	and	#0xff,\num	; num = (0x007f & sign) + 1;
	btsc	\sign,#SIGNB	; if (sign < 0)
	neg	\num,\num	;  num = -num;
.endm

;;; sign: input register int16_t sxxx xxxx xxxx xxxx
;;; den: input/output register ratio_t xxdd dddd dxxx xxxx->sfdd dddd d000 0000
.macro	fmt_den	sign,den
	rlnc	\den,\den	; // keep format bit opposite of sign bit
	btst.c	\sign,#SIGNB	; if (sign < 0) {
	rrc	\den,\den	;  den |= (1 << SIGNB)
	btss	\den,#SIGNB	;  den &= ~(1 << FORMATB); // ...
	bset	\den,#FORMATB	; } else {
	btsc	\den,#SIGNB	;  den &= ~(1 << SIGNB);
	bclr	\den,#FORMATB	;  den |= 1 << FORMATB; 
	lsr	\den,#7,\den	; }
	sl	\den,#7,\den	; den &= 0xff80; // mask off bits for numerator
.endm
	
;;; hi|lo: register int32_t result of multiplication (MUL.SS or MUL.SU)
;;; lobits: literal uint4_t number of unsigned bits that lo is allowed to retain
;;; v flag set (and z flag cleared) if product was unrepresentable (ie overflow)
.macro	mul_ovf	hi,lo,lobits
	bclr	0x42,#2		; v = 0;
	btss	\hi,#SIGNB	; z = 1;
	bra	Lpos\@mul_ovf	; if (hi < 0) {
	com	\hi,\hi		;  hi = ~hi;
	bra	nz,Lend\@mul_ovf;  if (hi) z = 0;
	com	\lo,\hi		;  else hi = ~lo;
	bra	Lshf\@mul_ovf	; } else if (hi)
Lpos\@mul_ovf:
	cp0	\hi		;  z = 0;
	bra	nz,Lend\@mul_ovf; if (z)
Lshf\@mul_ovf:
	lsr	\lo,\lobits,\hi	;  z = (hi >> lobits) == 0;
Lend\@mul_ovf:
	btss	0x42,#0		;
	bset	0x42,#2		; v = ~z;  
.endm	

.macro	mul_128	hi,lo,if128
	bclr	0x42,#2		; v = 0;
	cp0	\hi		;
	bra	z,Lno0\@mul_128	;
	xor	#128,\lo	;
	btsc	0x42,#2		;
	bset	\lo,#7		;
	bra	z,\if128	; if ((hi == 0x0000) && (lo == 0x0080) ||
	bra	Lend\@mul_128	;     (hi = 0xffff) && (lo == 0xff80))
Lno0\@mul_128:	
	com	\hi,\hi		;
	bra	nz,Lun2\@mul_128;
	com	\lo,\lo		;
	xor	#128,\lo	;
	bra	nz,Lun1\@mul_128;
	xor	#128,\lo	;
	com	\lo,\lo		;
	bra	\if128		;  goto if128;
Lun1\@mul_128:
	xor	#128,\lo	;
	com	\lo,\lo		;
Lun2\@mul_128:
	com	\hi,\hi		;
Lend\@mul_128:	
.endm

.macro	mul_r_n	rat,by,dst,dst1
	isratio	\rat
	bra	c,Lis\@mul_r_n	; if (!isratio(rat))
	mul.ss	\rat,\by,\dst	;  dst = rat * by;
	mul_ovf	\dst1,\dst,#14
	bra	Lend\@mul_r_n	; else {
Lis\@mul_r_n:
	sgn_rat	\rat,\dst,\dst1
	cp	\dst1,#1	;  sgn_rat(rat, &dst);
	bra	nz,Lno1\@mul_r_n;  if (dst[1] /*denominator*/ == 1)
	mul.ss	\dst,\by,\dst	;   dst = dst[0] /*numerator*/ * by;
	mul_ovf	\dst1,\dst,#14
	bra	Lend\@mul_r_n	;  else {
Lno1\@mul_r_n:	
	mul.ss	\dst,\by,\dst	;   dst = dst[0] /*numerator*/ * by;
	mul_128	\dst1,\dst,Lskp\@mul_r_n
	mul_ovf	\dst1,\dst,#7
	bra	ov,Lend\@mul_r_n	;   if (((dst<0) ? -dst : dst) > 128) v = 1;
Lskp\@mul_r_n:
	btsc	\dst,#SIGNB	;   else if (dst < 0)
	neg	\dst,\dst	;    dst = 0x8000 | (0x3f8&rat) | (0x7f&-dst);
	lsr	\dst,\dst	;
	xor	\rat,\by,\dst1	; // recover the sign since dst1 was clobbered
	fmt_den	\dst1,\rat
	ior	\rat,\dst,\dst	;   else dst = 0x4000 |(0x3f8&rat)|(0x7f&dst);
	reratio	\dst,\dst1,0
Lend\@mul_r_n:
.endm

.macro	mul_any	rat1,rat2,dst,dst1,dst2,dst3
	isratio	\rat1
	bra	c,Lis1\@mul_any	; if (!isratio(rat1))
	mul_r_n	\rat2,\rat1,\dst,\dst1
	bra	Lend\@mul_any	;  mul_r_n(rat2, rat1, dst, dst1);
Lis1\@mul_any:
	isratio	\rat2
	bra	c,Lis2\@mul_any	; else if (!isratio(rat2))
	mul_r_n	\rat1,\rat2,\dst,\dst1
	bra	Lend\@mul_any	;  mul_r_n(rat1, rat2, dst, dst1); else { //fixme: eliminate the 2nd expansion but still maintain rat1 and rat2 by end
Lis2\@mul_any:
	sgn_rat \rat1,\dst,\dst1
	sgn_rat	\rat2,\dst2,\dst3
	mov	\dst,\rat1	;  rat1 = /*num1*/; dst2 = /*num2*/;
	mov	\dst1,\rat2	;  rat2 = /*den1*/; dst3 = /*den2*/;
	mul.ss	\rat1,\dst2,\dst;  dst = rat1*dst2; // num, numerator product
	mul.uu \rat2,\dst3,\dst2;  dst2 = rat2*dst3; // den, denominator product
	bclr	0x42,#0		;
	rrc	\dst3,\dst3	;
	bra	nz,Lrot\@mul_any-2;
	rrc	\dst2,\dst2	;
	bra	nz,Lrot\@mul_any-4;
	mul_ovf	\dst1,\dst,#14
	bra	Lend\@mul_any	;
;;; Lrot\@mul_any-4:
	rlc	\dst3,\dst3	;
;;; Lrot\@mul_any-2:
	rlc	\dst3,\dst3	;  if (dst2 /*den*/ != 1) { // not a simple case
Lrot\@mul_any:
	mul_128	\dst1,\dst,Lnov\@mul_any
	mul_ovf	\dst1,\dst,#7
	bra	nov,Lnov\@mul_any;  while (dst /*num*/ > (1<<7) /*128*/) {
	btst.c	\dst1,#SIGNB	;   
	asr	\dst1,#1,\dst1	;
	rrc	\dst,\dst	;    dst /*num*/ /= 2; // signed
	bclr	0x42,#0		;
	rrc	\dst3,\dst3	;
	rrc	\dst2,\dst2	;    dst2 /*den*/ /= 2; // unsigned
	bra	Lrot\@mul_any	;   }
Lnov\@mul_any:	
	mul_128	\dst3,\dst2,Lskp\@mul_any
	mul_ovf	\dst3,\dst2,#7
	bra	nov,Lskp\@mul_any;
	xor	\dst,\dst,\dst	; dst = 0;
	bra	Lend\@mul_any	;
Lskp\@mul_any:
	sl	\dst2,#7,\dst2	; dst2 <<= 7; // den positive, shift into place
	mov	\dst,\dst1	; dst1 = dst; // preserve sign
	btsc	\dst,#SIGNB	; if (dst < 0)
	neg	\dst,\dst	;  dst = -dst; // absolute value
	fmt_den	\dst1,\dst2
	ior	\dst,\dst2,\dst	; dst = 0x4000 |(0x3f8&rat)|(0x7f&dst);
	reratio	\dst,\dst1,0
Lend\@mul_any:
.endm

.macro	oneover	rat,dst
	isratio	\rat
	bra	nc,Lend\@oneover; if (isratio(rat))
	spl_rat	\rat,\dst
	swap	\dst		;
	uns_rat	\dst,\dst	;
	btsc	\rat,#SIGNB	;
	bset	\dst,#SIGNB	;  dst = (0xc000 & rat) |
	btsc	\rat,#FORMATB	;        (0x3f80 & (rat << 7)) |
	bset	\dst,#FORMATB	;        (0x007f & (rat >> 7)); // swap num, den
Lend\@oneover:
.endm	

;;; A/B = A * (1/B) = 1/[(1/A) * B]
.macro	div_r_n	rat1,rat2,dst,dst1,dst2,dst3
	isratio	\rat1
	bra	nc,Lend\@div_r_n; if (isratio(rat1)) {
	oneover	\rat1,\dst
	mov	\dst,\rat1	;  dst = (rat1 = 1.0 / rat1) * rat2;
	mul_r_n	\rat1,\rat2,\dst,\dst1,\dst2,\dst3
	mov	\dst,\dst1	;  dst = 1.0 / dst;
	oneover	\dst1,\dst
	mov	\rat1,\dst1	;  rat1 = 1.0 / rat1; }
	oneover	\dst1,\rat1
Lend\@div_r_n:
.endm

.macro 	inc_any	rat,tmp,i
	isratio	\rat
	bra	c,Lend\@inc_any	; if (!isratio) switch (i) {
.if (\i == -2)
	dec2	\rat,\rat	;  case -2: rat -= 2;
.endif
.if (\i == -1)
	dec	\rat,\rat	;  case -1: rat--;
.endif
.if (\i == 1)
	inc	\rat,\rat	;  case +1: rat++;
.endif
.if (\i == 2)
	inc2	\rat,\rat	;  case +2: rat += 2;
.endif
.if (\i == 0)
	nop			;  default: ;
.endif
	bra	Lend\@inc_any	; } else {}
	bumprat	\rat,\tmp,\i
Lend\@inc_any:
.endm
	
.macro	add_r_n	rat,offs,dst,dst1
	isratio	\rat
	bra	c,Lis\@add_r_n	; if (!isratio(rat))
	add	\rat,\offs,\dst	;  dst = rat + by;
	bra	Lend\@add_r_n	; else {
Lis\@add_r_n:	
	sgn_rat	\rat,\dst,\dst1
	cp	\dst1,#1	;  sgn_rat(rat, dst);
	bra	nz,Lno1\@add_r_n;  if (dst[1] /*denominator*/ == 1) {
	btss	\dst,#SIGNB	;   if (dst[0] /*numerator*/ >= 0)
	add	\dst,\offs,\dst	;    dst = dst[0] /*numerator*/ + offs;
	btsc	\dst,#SIGNB	;   else
	sub	\dst,\offs,\dst	;    dst = dst[0] /*numerator*/ - offs;
	bra	Lend\@add_r_n	;  } else {
Lno1\@add_r_n:
	mul.ss	\dst1,\offs,\dst;
	mov	\dst,\offs	;   offs *= dst[1] /*denominator*/;
	sgn_rat	\rat,\dst,\dst1
	btss	\dst,#SIGNB	;   if (dst[0] /*numerator*/ >= 0)
	add	\dst,\offs,\dst	;    dst = dst[0] /*numerator*/ + offs;
	btsc	\dst,#SIGNB	;   else
	sub	\dst,\offs,\dst	;    dst = dst[0] /*numerator*/ - offs;
	
	btsc	\dst,#SIGNB	;   if (dst < 0)
	neg	\dst,\dst	;    dst = 0x8000|(0x3f8&rat)|(0x7f&-(dst-1));
	dec	\dst,\dst	;
	fmt_den	\dst,\dst1
	ior	\rat,\dst,\dst	;   else dst =0x4000|(0x3f8&rat)|(0x7f&(dst-1));
	reratio	\dst,\dst1
Lend\@add_r_n:
.endm
