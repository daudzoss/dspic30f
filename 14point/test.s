.include "14point.inc"
.include "crt1_standard.s"	

	.text
_main:	
	toratio	#7,w0
	oneover	w0,w1
	mov	#3,w0		; w2 = (w1 = oneover(toratio(7))) + 3; // 22/7
	add_r_n	w1,w0,w2,w3

	mov	#0x0716,w3 	;
	sub	#0x0101,w3	;
	uns_rat	w3,w3
	mov	#0x4000,w1	; w1 = 22.0/7.0;
	combine	w3,w1
	xor	w2,w1,w8	; w8 = w1 ^ w2; // should be 0
	
	mov	#0x4663,w0	;
	sub	#0x0101,w0	;
	uns_rat	w0,w0
	bset	w0,#FORMATB	; w0 = 99.0/70.0; // approx sqrt(3)
	mov	w0,w6		;
	mul_any	w0,w6,w2,w3,w4,w5
	mov	w2,w0		; w0 = w0 * w0; // should be a ratio close to 3 [20220624: but instead is 0x6f49 == 73/94]
	mul_any	w1,w2,w2,w3,w4,w5; w2 *= w1 /*pi*/; // should be between 9 and 10
	
	mov	#-9,w0		;
	toratio	w0,w0
;	add_any	w2,w0,w4
	mov	w4,w9		; w9 = w2 - 9; // should be positive
	mov	#-10,w0		;
	toratio	w0,w0
;	add_any	w2,w0,w4	;
	mov	w4,w10		; w10 = w2 - 10; // should be negative

