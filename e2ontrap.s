;;; intercept misaligned memory accesseses to map the EEPROM into main memory
;;; space, using the AddressError Trap Vector to run routines that manipulate
;;; it behind the scenes
;;;
;;; it might also be feasible to map any access to the last 1/2/4KiB of a 32KiB
;;; data memory segment so that it refers automatically to EEPROM (for dsPIC30
;;; the area between 0x2800 and the PSV window at 0x8000 is always unmapped)
;;;
;;; can't utilize PUSH.S shadow registers to speed entry/exit since not readable
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
	mov.d	w0,[w15++]	;void adrtrap(uint16_t* sp) {
	mov.d	w2,[w15++]	; *sp++ = w0, *sp++ = w1;
	btss	0x0080,#3	; *sp++ = w2, *sp++ = w3;
	bra	adrdone		; if (INTCON1 & (1 << ADDRERR)) { // is bus trap

	;; as there's no SFR reflecting the EA causing the fault,
	;; will need to completely decode the instruction here :-(
	mov	[w15-10],w3	;  uint32_t* w3w2 = (sp[-5] << 16) | sp[-6];
	mov	[w15-12],w2	;
	mov	#0x0032,w1	;  uint16_t* w1 = &TBLPAG;
	mov	[w1],[w15++]	;  *sp++ = *w1; // stack TBLPAG to preserve
	mov	w3,[w1]		;  *w1 = (w3w2 >> 16) & 0x7f; // user (not cfg)
	tblrdh	[w2],w3		;  uint16_t w3 = *w3w2 >> 16; // opcode in w3
	tblrdl	[w2],w2		;  uint16_t w2 = *w3w2 & 0x00ffff;; // arg in w2
	
	;; march through all opcodes, looking for register-indirect destinations
op0x1X:	
	lsr	w3,#4,w0	;
	mov	#0x0001,w1	;
	cpseq	w0,w1		;
	bra	op0x2X		;  if (w3 & 0xfff0 == SUBR_BR) { //SUBR or SUBBR
	rcall	rewrite		;   rewrite(&w0, &w1, w2, &w3);

op0x2X:	


op0x01b:	
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
op0x:	
	mov	#,w0		;
	cpseq	w3,w0		;
	bra	op0x		;
	
	;; w0 holds src word address, w1 holds dest word address
adrw0w1:
	btsc	w0,#0		;
	bra	srcadok		;


srcadok:
	btsc	w1,#0		;
	bra	dstadok		;
	
dstadok:
	;; perform any required pre-increment or -decrement

	;; now perform the operation in the original opcode

	;; stash the status bits on the stack

	;; perform any required post-increment or -decrement

	;; advance the stacked PC by one instruction (if not a branch)
	btsc	?,?		;
	bra	poptpag		;  if () // PC not already updated
	subr	#6,w15,w1	;
	inc2	[w1],[w1]	;
	bra	nc,poptpag	;
	subr	#4,w15,w1	;
	inc	[w1],[w1]	;   *((uint32_t*) &sp[-3]) += 2; // PC += 2
poptpag:

.if SD_CACHE_WRITEBACK
.endif
	mov	#0x0032,w1	;  w1 = &TBLPAG;
	mov	[--w15],[w1]	;  *w1 = *--w15; // TBLPAG restored
adrdone:
	;; clear the fault bit before returning to prevent a bounceback
	bclr	0x0080,#3	;  INTCON1 &= ~(1 << ADDRERR);
	mov.d	[--w15],w2	;  w3 = *--sp, w2 = *--sp;
	mov.d	[--w15],w0	;  w1 = *--sp, w0 = *--sp; } 
	retfie			;} // adrtrap()

addrmod:
	lsr	w2,#4,w0	;uint16_t addrmod(uint16_t w2) {
	and	#0x007,w0	; w0 = w2 >> 4;
	bra	w0		; switch (w0 & 0x0070) { // src indirect addr
	goto	direct		;  case 0: return direct(w2);
	goto	indir		;  case 1: return indir(w2);
	goto	postdec		;  case 2: return postdec(w2);
	goto	postinc		;  case 3: return postinc(w2);
	goto	predec		;  case 4: return predec(w2);
	goto	preinc		;  case 5: return preinc(w2);
	nop			; }        return 0;
	retlw	#0,w0		;} // addrmod()

rewrite:	
	mov	0x0060,w1	;void rewrite(uint16_t* w0/*d*/,uint16_t* w1,//s
	and	w1,w2,w0	;             uint16_t w2, uint16_t* w3) {//base
	cpseq	w0,w1		;
	bra	sconst		; if (w2 & 0x0060 != 0x0060) // src not const.
	rcall	addrmod		;  *w1 = addrmod(w2);
	bra	srcdone		; else
sconst:	
	and	w2,#0x1f,w0	;  *w1 = w2 & 0x1f; // constant encoded in instr
srcdone:
	mov	w0,w1		; // now handle the base register (FIXME: w4-w14 only!)

	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rcall	addrmod		; *w0 = addrmod(w2 << 7);
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	sl	w2,#1,w2	; *w3 = 2 * ((*w3 << 1) | (w2 >> 15)); // base reg
	rlc	w3,#2,w3	; w2 <<= 1;
	and	#0x01e,w3	; *w3 &= 0x01e; // w3 now the memory mapped base
	bclr	0x0042,#0	;
	btsc	w3,#1		;
	bset	0x0042,#0	;
	rrc	w2,#1,w2	; w2 = (w2 >> 1) | (*w3 << 14); // back unchanged
	
	mov	[w3],w3		; *w3 = **w3;
	return			;} // rewrite()
	
	
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

