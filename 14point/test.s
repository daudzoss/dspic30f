.include "14point.inc"
.include "crt1_standard.s"	
	.text
_main:	
	toratio	#7,w0
	oneover	w0,w1
	mov	#3,w0		; w2 = (w1 = oneover(toratio(7))) + 3; // 22/7
	add_r_n	w1,w0,w2,w3

	mov	#0x0716,w3 	;
	mov	#0x4000,w1	; w1 = 22.0/7.0;
	uns_rat	w3,w3
	combine	w3,w1
	xor	w2,w1,w0	; w0 = w1 ^ w2; // should be 0
	
