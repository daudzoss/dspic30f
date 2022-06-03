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
	btg	SR,#C		;  c = ~c;
.endm

;;; num: input literal or register int8_t, -128 < num < +128
;;; rat: output register ratio_t in the format sf00 0000 0nnn nnnn
.macro	toratio num,rat
	mov	\num,\rat	; rat = num;
;	ior	\rat,\rat,\rat	;
;	bra	z,.+13		; if (rat) { // 0 can't be represented as ratio
	btsc	\rat,#SIGNB	;  if (rat < 0)
	neg.b	\rat,\rat	;   rat = (0xff00 & rat) | (0x00ff & -rat);
	bra	z,.+11		;  if (rat) { // 0 can't be represented as ratio
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
.endm

;;; rat: input register ratio_t in the format sfdd dddd dnnn nnnn
;;; numden: output register struct { uint7_t /*upper*/ den, /*lower*/ num; }
.macro	spl_rat	rat,numden
	mov	#0x3dff,\numden	;
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
	
.macro	combine	numden,sf
	lsr	\sf,#14,\sf	;
	sl	\sf,#14,\sf	; sf &= 0xc000;
	ior	\numden,\sf,\sf	; sf |= numden;
.endm

;;; rat: input/output register ratio_t in the format sfdd dddd dnnn nnnn
;;; tmp: scratch register(s)
;;; extent: input constant, 0=minimal/quick, 1=more thorough, 2=final(division!)
.macro	reratio	rat,tmp,extent
	;; check for trailing zeroes (both N-1 and D-1 odd)
	spl_rat	\rat,\tmp
	add	#0x101,\tmp	; tmp = 0x0101 + (0x7f00&(rat<<1))|(0x007f&rat);
	
	btsc	\tmp,#8		; // sign got lost, will need to restore at end!
	bra	.+5		;
	btsc	\tmp,#0		;
	bra	.+3		; while (tmp & 0x0101 == 0) {
	lsr	\tmp,\tmp	;  tmp >>= 1; // both num and den divided by two
	bra	.-5		; }

	sub	#0x101,\tmp	; tmp -= 0x0101; combine(tmp, &rat);
	uns_rat	\tmp,\tmp
	combine	\tmp,\rat
	
.if (\extent > 0)
	;; check for easy odd factors? 3?
.endif

.if (\extent > 1)
	;; full search for common factors
	spl_rat	\rat,\tmp
	add	#0x101,\tmp	;
	factor \tmp,1+\tmp,2+\tmp
	sub	#0x101,\tmp	;
	uns_rat	\tmp,\tmp
	combine	\tmp,\rat
.endif
.endm

;;; rat: input union { ratio_t rat; int16_t integer }
;;; int8: output int16_t
;;; restore: input constant, 1 leave with unconvertible rat unmodified
.macro	tointif	rat,int8,restore
	mov	\rat,\int8	;
.if restore
	isratio	\int8		;
	bra	NC,.+17		;
.endif
	sl	\int8,\int8	; // works with f or reg or lit, store sign in C
	swap	\int8		; // 7-bit numerator and bit 0 now in high byte
	and.b	#0x7f,\int8	; // FORMAT bit and 7-bit denom now in low byte
	swap	\int8		; // 7-bit numerator and bit 0 now in low byte
	rrnc	\int8,\int8	; // 7-bit numerator now in low 7 bits
.if restore
	bra	z,.+6		; // leaves as ratio if denominator isn't unity
	btsc	SR,#C		; if (c)
	bset	\int8,#SIGNB	;  int8 |= 1<<SIGNB; // negative (format left 0)
	btss	SR,#C		; else
	bset	\int8,#FORMATB	;  int8 |= 1<<FORMATB; // positive (sign left 0)
	bra	.+6		;
.else
	bra	nz,.+6		; if (rat & 0x3f80 == 0) // denominator is one
.endif
	btss	SR,#C		;  if (rat & (1<<SIGNB))
	neg	\int8,\int8	;   int8 = -(rat & 0x007f + 1);// carry is clear
	btsc	SR,#C		;  else
	dec2	\int8,\int8	;   int8 = rat & 0x007f + 1; // carry is clear
	inc	\int8		;
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
	
.macro	bumprat	rat,tmp,i
.if (\i)
	sl	\rat,\tmp	; uint8_t tmp = rat << 1; // numerator*2 in low
	add.b	#0x02,\tmp	; tmp += 2; // convert 2*0..127 to 2*1...128
	lsr	\rat,#6,\rat	; rat >>= 6; // signs in high, denom*2 in low
	and.b	#0xfe,\rat	; rat &= 0xfffe; // denominator to add/subtract
	add.b	#0x02,\rat	; rat += 2; // convert 2*0..127 to 2*1...128

	bump_1	\rat,\tmp,\i
.if (\i & 1 == 0)
	bump_1	\rat,\tmp,\i
.endif
	bra	nz,.+3		; for (j=(i<0)?-i:i; j; j--) bump_1(rat,tmp,i);
	mov	#0x0002,\rat	; if (tmp & 0xfe == 0)
	mov.b	#0x02,\tmp	;  rat = tmp = 0x0002; // spoof to get 0x0000 
;	bra	nv,.+?		; // else if (/*overflow condition*/) {}

	sub.b	#0x02,\rat	; // rat still holds sign, format, denominator:
	sub.b	#0x02,\tmp	; //  0000 00sf dddd ddd0 -> sfdd dddd d000 0000
	sl	\rat,#6,\rat	; // tmp holds new numerator:
	lsr.b	\tmp,\tmp	; //  fddd dddd nnnn nnn0
	ior.b	\tmp,\rat,\rat	; rat = (rat << 6) | (0x007f & (tmp >> 1));
.endif	
	reratio	\rat,\tmp,0
.endm	

.macro 	inc_any	rat,tmp,i
	isratio	\rat
	bra	c,.+3		; if (!isratio) switch (i) {
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
	bra	?		; } else {}
	bumprat	\rat,\tmp,\i
.endm
	
.macro	addrat	rat,tmp
	lsr	\rat,#7,\tmp	;
	and	#0x7f,\tmp	;
	inc	\tmp,\tmp	;
	mov	#0x
.endm
	

.endm
