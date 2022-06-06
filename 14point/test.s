.include "14point.inc"
.include "/opt/microchip/xc16/v1.70/support/dsPIC30F/inc/p30F4013.inc"
	
	.text
	.org	0x000100
	toratio	#7,w0
	oneover	w0,w1
	mov	#3,w0		; w2 = (w1 = oneover(toratio(7))) + 3; // 22/7
	add_r_n	w1,w0,w2,w3

	mov	#0x0716,w1 	; w1 = 22.0/7.0;
	xor	w2,w1,w0	; w0 = w1 ^ w2; // should be 0
	
