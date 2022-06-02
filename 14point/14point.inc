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
	
.macro	isratio	w
	btst.c	\w,#SIGNB	; c = (w < 0); // 1 if a ratio
	btsc	\w,#FORMATB	; if (w & (1<<FORMATB))
	btg	SR,#C		;  c = ~c;
.endm

.macro	toratio num,rat
	mov	\num,\rat	; rat = num;
;	ior	\rat,\rat,\rat	;
;	bra	z,.+13		; if (rat) { // 0 can't be represented as ratio
	btsc	\rat,#SIGNB	;  if (rat < 0)
	neg.b	\rat,\rat	;   rat = (0xff00 & rat) | (0x00ff & -rat);
	bra	z,.+10		;  if (rat) { // 0 can't be represented as ratio
	dec.b	\rat,\rat	;   rat--; // map 1..128 onto 0..127
	and.b	#0x7f,\rat	;   rat &= 0x807f; // clear denominator (i.e. 1)
	btg	\rat,#FORMATB	;   rat |= (rat & 0x8000) >> 1; // flag as ratio
	bclr	\rat,#FORMATB-1	;
	bclr	\rat,#FORMATB-2	;
	bclr	\rat,#FORMATB-3	;
	bclr	\rat,#FORMATB-4	;
	bclr	\rat,#FORMATB-5	;  } 
	bclr	\rat,#FORMATB-6	; }
.endm

.macro	reratio	rat,tmp
	;; check for trailing zeroes
	
	;; check for powers of two?
.endm

.macro	tointif	rat,int8,restore
	mov	\rat,\int8	;
.if restore
	isratio	\int8		;
	bra	NC,.+16		;
.endif
	sl	\int8,\int8	; works with f or reg or lit, sign stored in C
	swap	\int8		; 7-bit numerator and low bit 0 now in high byte
	and.b	#0x7f,\int8	; FMT bit and 7-bit denominator now in low byte
	swap	\int8		; 7-bit numerator and low bit 0 now in low byte
	rrnc	\int8,\int8	; 7-bit numerator now in low 7 bits
.if restore
	bra	z,.+6		; leaves it a ratio if denominator isn't unity
	btsc	SR,#C		; if (c)
	bset	\int8,#SIGNB	;  int8 |= 1<<SIGNB; // negative (format left 0)
	btss	SR,#C		; else
	bset	\int8,#FORMATB	;  int8 |= 1<<FORMATB; // positive (sign left 0)
	bra	.+6		;
.else
	bra	nz,.+6		; if (rat & 0x3f80 == 0) // denominator is one
.endif
	btss	SR,#C		;  if (rat & (1<<SIGNB))
	neg	\int8,\int8	;   int8 = -(rat & 0x007f + 1);
	btsc	SR,#C		;  else
	dec2	\int8,\int8	;   int8 = rat & 0x007f + 1;
	inc	\int8		; // carry should be clear
.endm

.macro	toanint	rat,int8
	tointif	\rat,\int8,0
.endm

.macro	incrat	rat,tmp	
	lsr	\rat,#6,\tmp	;
	and.b	#0xfe,\tmp	;
	inc2	\tmp,\tmp	; tmp = ((0x007f & (rat >> 7)) + 1) << 1; // D*2
	sl.b	\rat,\rat	; rat = (0xff00 & rat) | ((0x007f & rat) << 1);
	add.b	\tmp,\rat	; uint9_t c = (0x00fe & rat) + tmp;
	bra	c,.+4		; rat = (0xff00 & rat) | (0x00fe & c);
	lsr	\tmp,\tmp	; if (c < 0x100) { // C 0 if no overflow, else 1
	dec	\tmp,\tmp	;  tmp = (tmp >> 1)  - 1; // cf. 0x007f&(rat>>7)
	rrc	\tmp,\tmp	;  rat = (0xff00 & rat) | ((tmp&1) ? 0x0080 : 0)
	rrc.b	\rat,\rat	;        (0x007f & (rat >> 1)); }
.endm

.macro	addrat	rat,tmp
	lsr	\rat,#7,\tmp	;
	and	#0x7f,\tmp	;
	inc	\tmp,\tmp	;
	mov	#0x
.endm
	

.macro	addlit	lit,
.endm

.macro	addifany
	
.endm
	
.macro	subifany
.endm
.macro	mulifany
.endm
.macro	divifany
	
.endm
