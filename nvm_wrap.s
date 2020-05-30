;;; intercept misaligned memory accesseses to map the EEPROM into main memory
;;; space, using the AddressError Trap Vector to run routines that manipulate
;;; it behind the scenes
;;;
;;; it might also be feasible to map any access to the last 1/2/4KiB of a 32KiB
;;; data memory segment so that it refers automatically to EEPROM (for dsPIC30
;;; the area between 0x2800 and the PSV window at 0x8000 is always unmapped)
;;;
;;; using PUSH.S shadow registers to avoid stack use
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
	push.s			;void adrtrap(uint16_t* sp) {
	btss	0x0080,#3	;
	bra	adrdone		; if (INTCON1 & (1 << ADDRERR)) {

	;; as there's no SFR reflecting the EA causing the fault,
	;; will need to completely decode the instruction here :-(
	mov	[w15-2],w3	;  uint16_t flash* w3w2 = (sp[-1] << 16) | sp[-2];
	mov	[w15-4],w2	;
	mov	#0x0032,w1	;  uint16_t* w1 = &TBLPAG;
	mov	[w1],[w15++]	;  *sp++ = *w1; // stack TBLPAG7..0 to preserve
	and	#0x7f,w3	;
	mov	w3,[w1]		;  *w1 = (w3w2 >> 16) & 0x7f; // user (not config)
	tblrdh	[w2],w3		;  uint16_t w3 = , w2 = ;
	tblrdl	[w2],w2		;
;can't use PSV for high byte, need TBLRD!!!	mov	w3,[w1]		;  *w1 = w2 >> 16;
	
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
