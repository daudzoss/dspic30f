;;; intercept misaligned memory accesseses to map the EEPROM into main memory
;;; space, using the AddressError Trap Vector to run routines that manipulate
;;; it behind the scenes
;;; use PUSH.S shadow registers to avoid stack use? option to do so?
	org	0x000000
	goto	main

	org	0x000008
	dw	adrtrap

	org	0x000088
	dw	0x7ffc00
	
	org	0x000100
adrtrap:	
.if B0REQUIRED1
EE	equ	0x0001
.else
EE	equ	0x0000
.endif	
	push.s			;void adrtrap(void) {
	btss	0x0080,#3	;
	bra	adrdone		; if (INTCON1 & (1 << ADDRERR)) {

	;; as there's no SFR reflecting the EA causing the fault,
	;; will need to completely decode the instruction here :-(
	mov	[w15-4],w1	;  
	

	mov	0x0034,WREG	;
	mov	W0,[w15++]	;  *sp++ = PSVPAG;
	
	;; clear the fault bit before returning to prevent a bounceback
	bclr	0x0080,#3	;  INTCON1 &= ~(1 << ADDRERR);
.if SD_CACHE_WRITEBACK
.endif
adrdone:
	pop.s			; }
	retfie			;}

coo1cpy:	
	mov	#0xc001,W0	;void coo1cpy(uint16_t** ee0x000) {
	mov	WREG,EE|0x0000	; do { 
	mov	#EE|0x0000,W1	;  *ee0x000 = EE | ((uint16_t*) 0);   
	mov	[W1],W2		;
	cpseq	W2,W0		;  **ee0x000 = 0xc001;
	bra	coo1cpy		; } while (**ee0x000 != 0xc001);
	return			;}
	
main:
	rcall	coo1cpy		;void main(void) {
	mov	#adrtrap,W0	; uint16_t w2, * ee_base, * flash_base;
	mov	#0x03fe,W2	; coo1cpy(&ee_base);
autocpy:
	mov	[W0+W2],[W1+W2]	; flash_base = 0x000100;
	dec2	W2		; for (w2 = 0x3fe; w2 >= 0; w2--)
	bra	N,autocpy	;  ee_base[w2] = flash_base[w2];

;;; now try switching to the alternate vector table and doing another copy!
	bset	0xINTCON2,#15	; INTCON2 |= (1 << ALTIVT);
	rcall	coo1cpy		; coo1cpy(&ee_base);
alldone:
	goto	alldone		;}
