;;; e2ontrap.s
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
	.pword	adrtrap

	org	0x000088
	.pword	0x7ffc00
	
	org	0x000100
	
	;; stack upon entry:
	;; SP-0x02=PC15..0 of instruction resulting in trap (?)
	;; SP-0x04=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
	;; 
	;; soon thereafter:
	;; SP-0x02=W3 when instruction trap occurred
	;; SP-0x04=W2 when instruction trap occurred
	;; SP-0x06=W1 when instruction trap occurred
	;; SP-0x08=W0 when instruction trap occurred
	;; SP-0x0a=0\TBLPAG7..0 when instruction trap occurred
	;; SP-0x0c=PC15..0 of instruction resulting in trap (?)
	;; SP-0x0e=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
adrtrap:	
.if B0REQUIRED1
EE	equ	0x0001
.else
EE	equ	0x0000
.endif	
	mov.d	w0,[w15++]	;void adrtrap(uint16_t* sp) {
	mov.d	w2,[w15++]	; *sp++ = w0, *sp++ = w1;
	btss	0x0080,#3	; *sp++ = w2, *sp++ = w3;
	bra	adrdone		; if (INTCON1 & (1 << ADDRERR)) { // is adr trap

	;; as there's no SFR reflecting the EA causing the fault,
	;; will need to completely decode the instruction here :-(
	mov	[w15-10],w3	;  uint32_t* w3w2 = (sp[-5] << 16) | sp[-6];
;	and	#0x07f,w3	;  w3w2 &= 0x7fffff;
	mov	[w15-12],w2	;
	mov	#0x0032,w1	;  uint16_t* w1 = &TBLPAG;
	mov	[w1],[w15++]	;  *sp++ = *w1; // stack TBLPAG to preserve
	mov	w3,[w1]		;  *w1 = (w3w2 >> 16) & 0x7f; // user (not cfg)
	tblrdh	[w2],w3		;  uint16_t w3 = *w3w2 >> 16; // opcode in w3
	tblrdl	[w2],w2		;  uint16_t w2 = *w3w2 & 0x00ffff;; // arg in w2
	
	;; march through all opcodes, looking for register-indirect destinations
op0x10:	
	lsr	w3,#4,w0	;
	mov.b	#0x01,w1	;
	cpseq.b	w0,w1		;
	bra	op0x40		;  if (w3 & 0x00f0 == SUBR_BR) { //SUBR or SUBBR
	btsc	w3,#3		;
	bra	op0x18		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBR.B	w3,w1,w1	;      __asm__("SUBR.B W3,W1,W1");
	btss	w2,#14		;    else
	SUBR	w3,w1,w1	;      __asm__("SUBR W3,W1,W1");
	bra	op0x1X		;   } else {
op0x18:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov.b	[w15-13],w2	;
	mov.b	w2,0x0042	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //B
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBBR.B	w3,w1,w1	;     __asm__("SUBBR.B W3,W1,W1");
	btss	w2,#14		;    else
	SUBBR	w3,w1,w1	;     __asm__("SUBBR W3,W1,W1");
op0x1X:
	mov.b	0x0042,w3	;   }
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;
	
op0x40:	
	lsr	w3,#4,w0	;
	mov.b	#0x04,w1	;
	cpseq.b	w0,w1		;
	bra	op0x50		;  } else if (w3 & 0x00f0 == ADDADDC) {
	btsc	w3,#3		;
	bra	op0x48		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	ADD.B	w3,w1,w1	;     __asm__("ADD.B W3,W1,W1");
	btss	w2,#14		;    else
	ADD	w3,w1,w1	;     __asm__("ADD W3,W1,W1");
	bra	op0x4X		;   } else {
op0x48:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov.b	[w15-13],w2	;
	mov.b	w2,0x0042	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //C
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	ADDC.B	w3,w1,w1	;     __asm__("ADDC.B W3,W1,W1");
	btss	w2,#14		;    else
	ADDC	w3,w1,w1	;     __asm__("ADDC W3,W1,W1");
op0x4X:
	mov.b	0x0042,w3	;   }
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x50:	
	lsr	w3,#4,w0	;
	mov.b	#0x05,w1	;
	cpseq.b	w0,w1		;
	bra	op0x60		;  } else if (w3 & 0x00f0 == SUBSUBB) {
	btsc	w3,#3		;
	bra	op0x58		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUB.B	w3,w1,w1	;     __asm__("SUB.B W3,W1,W1");
	btss	w2,#14		;    else
	SUB	w3,w1,w1	;     __asm__("SUB W3,W1,W1");
	bra	op0x5X		;   } else {
op0x58:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov.b	[w15-13],w2	;
	mov.b	w2,0x0042	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //B
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBB.B	w3,w1,w1	;     __asm__("SUBB.B W3,W1,W1");
	btss	w2,#14		;    else
	SUBB	w3,w1,w1	;     __asm__("SUBB W3,W1,W1");
op0x5X:
	mov.b	0x0042,w3	;   }
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x60:	
	lsr	w3,#4,w0	;
	mov.b	#0x06,w1	;
	cpseq.b	w0,w1		;
	bra	op0x70		;  } else if (w3 & 0x00f0 == ANDXOR) {
	btsc	w3,#3		;
	bra	op0x68		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	AND.B	w3,w1,w1	;     __asm__("AND.B W3,W1,W1");
	btss	w2,#14		;    else
	AND	w3,w1,w1	;     __asm__("AND W3,W1,W1");
	bra	op0x6X		;   } else {
op0x68:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	XOR.B	w3,w1,w1	;     __asm__("XOR.B W3,W1,W1");
	btss	w2,#14		;    else
	XOR	w3,w1,w1	;     __asm__("XOR W3,W1,W1");
op0x6X:
	mov.b	0x0042,w3	;   }
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x70:	
	lsr	w3,#4,w0	;
	mov.b	#0x07,w1	;
	cpseq.b	w0,w1		;
	bra	op0x90		;  } else if (w3 & 0x00f0 == IORMOV) {
	btsc	w3,#3		;
	bra	op0x78		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	IOR.B	w3,w1,w1	;     __asm__("IOR.B W3,W1,W1");
	btss	w2,#14		;    else
	IOR	w3,w1,w1	;     __asm__("IOR W3,W1,W1");
	bra	op0x7X		;   } else {
op0x78:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
;;;  // FIXME: rewrite() must finish with w3 clear if not offset indirect access
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	MOV.B	[w1+w3],w1	;     __asm__("MOV.B [W1+W3],W1");
	btss	w2,#14		;    else
	MOV	[w1+w3],w1	;     __asm__("MOV [W1+W3],W1");
op0x7X:
	mov.b	0x0042,w3	;   }
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x90:	lsr	w3,#4,w0	;
	mov.b	#0x09,w1	;
	cpseq	w0,w1		;
	bra	op0x		;  } else if (w3 & 0x00f0 == MOVSOFF) {
	rcall	rewrmov		;   rewrmov(&w0, &w1, w2, &w3); // no pre/posts
	btsc	w2,#14		;   if (w2 & (1 << 14)) // Byte access
	MOV.B	[w1],w1		;    __asm__("MOV.B [W1],W1");
	btss	w2,#14		;   else
	MOV	[w1],w1		;    __asm__("MOV [W1],W1");
	mov.b	0x0042,w3	;
	mov.b	w3,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;
	
op0x:	
	lsr	w3,#4,w0	;
	mov	#0x,w1		;
	cpseq	w0,w1		;
	bra	op0x		;
op0x:	
	lsr	w3,#4,w0	;
	mov	#0x,w1		;
	cpseq	w0,w1		;
	bra	op0x		;
op0x:	
	lsr	w3,#4,w0	;
	mov	#0x,w1		;
	cpseq	w0,w1		;
	bra	op0x		;
op0x:	
	lsr	w3,#4,w0	;
	mov	#0x,w1		;
	cpseq	w0,w1		;
	bra	op0x		;
	
	;; advance the stacked PC by one instruction (if not a branch)
advanpc:
	sub	w15,#0x00c,w1	;
	inc2	[w1],[w1]	;
	bra	nc,poptpag	;
	sub	w15,#0x00e,w1	;  *((uint32_t*) &sp[-3]) += 2; // PC += 2
	inc	[w1],[w1]	;  poptpag: // above skippable with goto poptpag
poptpag:

.if SD_CACHE_WRITEBACK
.endif
	mov	#0x0032,w1	;  w1 = &TBLPAG;
	mov	[--w15],[w1]	;  *w1 = *--w15; // TBLPAG restored
	;; clear the fault bit before returning to prevent a bounceback
adrdone:
	bclr	0x0080,#3	; } INTCON1 &= ~(1 << ADDRERR);
	mov.d	[--w15],w2	; w3 = *--sp, w2 = *--sp;
	mov.d	[--w15],w0	; w1 = *--sp, w0 = *--sp;
	retfie			;} // adrtrap()

.macro	fixwadr	w
	btsc	\w,#0		;inline void fixwadr(uint16_t* *w) {
	bra	1f		;// access EEPROM mapped into a RAM word
	btss	\w,#14		;// if in EEPROM, will return LSB set, to
	bra	2f		;// indicate that TBLWR/TBLRD must be used
	btss	\w,#13		;
	bra	2f		; if (((*w) & 0x0001) ||
	btss	\w,#12		;     (((*w) & 0x7000 == 0x7000) &&
	bra	2f		;      (EEPROM_SIZE >= 0x1000)) ||
.if EEPROM_SIZE < 4096
	btsc	\w,#11		;     (((*w) & 0x7800 == 0x7800) &&
	bra	2f		;      (EEPROM_SIZE >= 0x0800)) ||
.endif
.if EEPROM_SIZE < 2048
	btsc	\w,#10		;     (((*w) & 0x7c00 == 0x7c00) &&
	bra	2f		;      (EEPROM_SIZE >= 0x0400))) {
.endif
1:
	sl	\w,#12,\w	;
	bset	0x0042,#0	;
	asr	\w,#12,\w	;  (*w) |= 0xf001; // fool it, get it? ;-)
.if EEPROM_SIZE < 4096
	bset	\w,#11		;  if (EEPROM_SIZE < 0x1000) (*w) |= 0x0800;
.endif
.if EEPROM_SIZE < 2048
	bset	\w,#10		;  if (EEPROM_SIZE < 0x0800) (*w) |= 0x0400;
.endif
	bset	\w,#0		;  } } // fixwadr()
2:
.endm

	;; stack upon entry:
	;; SP-0x02=PC15..0 of return instruction in addrmod()
	;; SP-0x04=PC22..16 of return instruction in addrmod()
	;; SP-0x06=PC15..0 of return instruction in rewrite()
	;; SP-0x08=PC22..16 of return instruction in rewrite()
	;; SP-0x0a=PC15..0 of return instruction in adrtrap()
	;; SP-0x0c=PC22..16 of return instruction in adrtrap()
	;; SP-0x0e=TBLPAG when instruction trap occurred
	;; SP-0x10=W3 when instruction trap occurred
	;; SP-0x12=W2 when instruction trap occurred
	;; SP-0x14=W1 when instruction trap occurred
	;; SP-0x16=W0 when instruction trap occurred
	;; SP-0x18=PC15..0 of instruction resulting in trap (?)
	;; SP-0x1a=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
.macro	relolow	\addr,\fullchk
.if \fullchk
	btsc	\addr,#15	;inline uint16_t relolow(uint16_t* addr,
	bra	1f		;                        uint1_t fullchk) {
	btsc	\addr,#14	;
	bra	1f		;
	btsc	\addr,#13	;
	bra	1f		;
	btsc	\addr,#12	;
	bra	1f		;
	btsc	\addr,#13	;
	bra	1f		;
	btsc	\addr,#12	;
	bra	1f		;
	btsc	\addr,#11	;
	bra	1f		;
	btsc	\addr,#10	;
	bra	1f		;
	btsc	\addr,#9	;
	bra	1f		;
	btsc	\addr,#8	;
	bra	1f		;
	btsc	\addr,#7	;
	bra	1f		;
	btsc	\addr,#6	;
	bra	1f		;
	btsc	\addr,#5	;
	bra	1f		;
.endif	
	btsc	\addr,#4	; // check addr really one of the stacked w0..w4
	bra	1f		; if ((fullchk & (addr/2 < 4)) ||
	btsc	\addr,#3	;     ((addr & 0x001e)/2 < 4))
	bra	1f		;  addr = &sp[w0/2 - 11];
	add	w15,\addr,w0	; return addr;
	sub	w0,#0x16	;} // relolow()
1:	
.endm
.macro	addrnum \rnum
	sl	\rnum,#1,w0	;inline uint16_t addrnum(uint4_t rnum) {
	and	#0x01e,w0	; return relolow((rnum << 1) & 0x001e);
	relolow	w0,0		;} // addrnum()
.endm
direct:
	addrnum	w2		;uint16_t direct(uint16_t w2){return addrnum(w2)
	return			;} // direct()
indir:
	addrnum	w2		;uint16_t indir(uint16_t w2) {
	mov	[w0],w0		;
	relolow	w0,1		; return relolow(*addrnum(w2));
	return			;} // indir()
postdec:
	addrnum	w2		;uint16_t postdec(uint16_t w2, uint1_t B) {
	mov	[w0],[w15++]	; uint16_t temp =*((uint16_t*)w0 = addrnum(w2));
	btsc	#0x0042,#0	; if (B)
	dec	[w0]		;  *(w0 = (uint8_t*) w0)++;
	btss	#0x0042,#0	; else
	dec2	[w0]		;  *(w0 = (uint16_t*) w0)++;
	mov	[--w15],w0	;
	relolow	w0,1		; return relolow(temp);
	return			;} // postdec()
postinc:
	addrnum	w2		;uint16_t postinc(uint16_t w2, uint1_t B) {
	mov	[w0],[w15++]	; uint16_t temp =*((uint16_t*)w0 = addrnum(w2));
	btsc	#0x0042,#0	; if (B)
	inc	[w0]		;  *(w0 = (uint8_t*) w0)++;
	btss	#0x0042,#0	; else
	inc2	[w0]		;  *(w0 = (uint16_t*) w0)++;
	mov	[--w15],w0	;
	relolow	w0,1		; return relolow(temp);
	return			;} // postinc()
predec:
	addrnum	w2		;uint16_t predec(uint16_t w2, uint1_t B) {
	btsc	#0x0042,#0	; if (B)
	dec	[w0],[w0]	;  --*((uint8_t*) w0);
	btss	#0x0042,#0	; else
	dec2	[w0],[w0]	;  --*((uint16_t*) w0);
	mov	[w0],w0		;
	relolow	w0,1		; return relolow(*w0);
	return			;} // predec()
preinc:
	addrnum	w2		;uint16_t preinc(uint16_t w2, uint1_t B) {
	btsc	#0x0042,#0	; if (B)
	inc	[w0],[w0]	;  ++*((uint8_t*) w0);
	btss	#0x0042,#0	; else
	inc2	[w0],[w0]	;  ++*((uint16_t*) w0);
	mov	[w0],w0		;
	relolow	w0,1		; return relolow(*w0);
	return			;} // preinc()

	;; stack upon entry:
	;; SP-0x02=PC15..0 of return instruction in rewrite()
	;; SP-0x04=PC22..16 of return instruction in rewrite()
	;; SP-0x06=PC15..0 of return instruction in adrtrap()
	;; SP-0x08=PC22..16 of return instruction in adrtrap()
	;; SP-0x0a=TBLPAG when instruction trap occurred
	;; SP-0x0c=W3 when instruction trap occurred
	;; SP-0x0e=W2 when instruction trap occurred
	;; SP-0x10=W1 when instruction trap occurred
	;; SP-0x12=W0 when instruction trap occurred
	;; SP-0x14=PC15..0 of instruction resulting in trap (?)
	;; SP-0x16=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
addrmod:
	rrnc	w2,#4,w0	;uint16_t addrmod(uint16_t w2, uint1_t B) {
	and	#0x007,w0	; w0 = w2 >> 4;
	bra	w0		; switch (w0 & 0x0070) { // src indirect addr
	bra	direct		;  case 0: return direct(w2, B);
	bra	indir		;  case 1: return indir(w2, B);
	bra	postdec		;  case 2: return postdec(w2, B);
	bra	postinc		;  case 3: return postinc(w2, B);
	bra	predec		;  case 4: return predec(w2, B);
	bra	preinc		;  case 5: return preinc(w2, B);
	bra	indir		; }        return indir(w2, B); // reg+off "mov"
	bra	indir		;} // addrmod()

	;; stack upon entry:
	;; SP-0x02=PC15..0 of return instruction in adrtrap()
	;; SP-0x04=PC22..16 of return instruction in adrtrap()
	;; SP-0x06=TBLPAG when instruction trap occurred
	;; SP-0x08=W3 when instruction trap occurred
	;; SP-0x0a=W2 when instruction trap occurred
	;; SP-0x0c=W1 when instruction trap occurred
	;; SP-0x0e=W0 when instruction trap occurred
	;; SP-0x10=PC15..0 of instruction resulting in trap (?)
	;; SP-0x12=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
.macro	eepromw	code,scratch,adreg
	mov	#0x4044,\scratch;inline void eepromw(int code, uint16_t adreg) {
	mov	\scratch,0x0760	; NVMCON = 0x4044; // per DS70138C EXAMPLE 6-3,4
	mov	0x007f,\scratch	;
	mov	\adreg,0x0762	; NVMADR = adreg;
	mov	\scratch,0x0764	; NVMADRU = 0x007f;
	mov	\scratch,0x0032	; TBLPAG = 0x007f; // need for write (not erase)
	disi	#5		;
	mov	#0x0055,\scratch;
	mov	\scratch,0x0766	; NVMKEY = 0x0055;
	mov	#0x00aa,\scratch;
	mov	\scratch,0x0766	; NVMKEY = 0x00aa;
	bset	0x0760,#15	; NVMCON |= (1 << WR); // initiate erase seq.
	nop			;
	nop			;
	btsc	0x0760,#15	; do {} while (NVMCON & (1 << WR));
	bra	.-2		;}
.endm	
	
writebk:	
	fixwadr	w0		;void writebk(uint16_t* w0, uint16_t w1) {//a,d
	btsc	w0,#0		; fixwadr(w0);
	bra	e2write		; if (w0 & 1 == 0) { // RAM address
	mov	w1,[w0]		;  *w0 = w1;
	return			; } else {// valid EEPROM address above 0x007000
e2write:
	bclr	w0,#0		;  eepromw(w2 = EEPROM_ERASE_WORD,w0 &= 0xfffe);
	eepromw	0x4044,w2,w0	;  *w0 = w1; // put the data into the latch
        tblwtl	w1,[w0]		;  eepromw(w2 = EEPROM_WRITE_WORD, w0);
	eepromw	0x4004,w2,w0	; }
	return			;}

	;; stack upon entry:
	;; SP-0x02=PC15..0 of return instruction in adrtrap()
	;; SP-0x04=PC22..16 of return instruction in adrtrap()
	;; SP-0x06=TBLPAG when instruction trap occurred
	;; SP-0x08=W3 when instruction trap occurred
	;; SP-0x0a=W2 when instruction trap occurred
	;; SP-0x0c=W1 when instruction trap occurred
	;; SP-0x0e=W0 when instruction trap occurred
	;; SP-0x10=PC15..0 of instruction resulting in trap (?)
	;; SP-0x12=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
rewrite:	
	mov	0x0060,w1	;void rewrite(uint16_t* w0/*d*/,uint16_t* w1,//s
	and	w1,w2,w0	;             uint16_t w2, uint16_t* w3) {//base
	cpseq	w0,w1		;
	bra	sconst		; if (w2 & 0x0060 != 0x0060) { // src not const.
	btst.c	w2,#14		;  // based on B and mode/reg bits, w0 gets src
	rcall	addrmod		;  *w0 = addrmod(w2, w2 & 0x4000 ? 1 : 0);
	fixwadr	w0		;  fixwadr(w0); // address "fixed" if in EEPROM
	btsc	w0,#0		;
	bra	seeprom		;  if ((*w0) & 1 == 0) // RAM address
	mov	[w0],w1		;   *w1 = **w0; // store contents in w1 for oper
	bra	srcdone		;  else // EEPROM address
seeprom:
	mov	#0x007f,w1	;
	mov	w1,0x0032	;   TBLPAG = 0x007f;
	bclr	w0,#0		;
	tblrdl	[w0],w1		;   *w1 = *((*w0) & 0xfffe);
	bra	srcdone		; } else
sconst:	
	and	w2,#0x1f,w1	;  *w1 = w2 & 0x1f; // constant encoded in instr
srcdone:
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	rrnc	w2,w2		;
	btst.c	w2,#7		;
	rcall	addrmod		; *w0 = addrmod(w2 >> 7, w2 & 0x4000 ? 1 : 0);
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		;
	rlnc	w2,w2		; // now handle a (never indirect) base register
	rlnc	w2,w2		; // specified (awkwardly) in opcode bits 16..13
	sl	w2,#1,w2	; *w3 = 2 * ((*w3 << 1) | (w2 >> 15)); // reg#
	rlc	w3,#2,w3	; w2 <<= 1;
	and	#0x01e,w3	; *w3 &= 0x01e; // w3 now the memory mapped base
	bclr	0x0042,#0	;
	btsc	w3,#1		;
	bset	0x0042,#0	;
	rrc	w2,#1,w2	; w2 = (w2 >> 1) | (*w3 << 14); // w2 unchanged
	btsc	w3,#4		;
	bra	w4w15br		;
	btsc	w3,#3		;
	bra	w4w15br		; if (*w3 & 0x018 == 0) // w0/w1/w2/w3 off stack
	sub	w3,#0x0e,w3	;
	mov	[w15+w3],w3	;  *w3 = sp[*w3 - 7]; // since w0 at SP-0x0c etc
	bra	rbaseok		; else
w4w15br:	
	mov	[w3],w3		;  *w3 = **w3; // won't touch r3 again
rbaseok:
	return			;} // rewrite()
	
	;; stack upon entry:
	;; SP-0x02=PC15..0 of return instruction in adrtrap()
	;; SP-0x04=PC22..16 of return instruction in adrtrap()
	;; SP-0x06=TBLPAG when instruction trap occurred
	;; SP-0x08=W3 when instruction trap occurred
	;; SP-0x0a=W2 when instruction trap occurred
	;; SP-0x0c=W1 when instruction trap occurred
	;; SP-0x0e=W0 when instruction trap occurred
	;; SP-0x10=PC15..0 of instruction resulting in trap (?)
	;; SP-0x12=SR7..0\IRL3\PC22..16 of instruction resulting in trap (?)
rewrmov:	
	sl	w2,#1,w1	; w3=00000000 1001?kkk, w2=kBkkkddd dkkkssss
	rlc	w3,#7,w1	; w1=01001?kk kk000000
	lsr	w2,#3,w0	;                       w0=000kBkkk ddddkkks
	swap.b	w0,w0		;                       w0=000kBkkk kkksdddd
	lsr	w0,#5,w0	;                       w0=00000000 kBkkkkkk
	and	w0,#0x03f,w0	;                       w0=00000000 00kkkkkk
	ior	w0,w1,w3	; w3=01001?kk kkkkkkkk
	
	btss	w3,#10		;         ^
	bra	
	
coo1cpy:	
	mov	#0xc001,w0	;void coo1cpy(uint16_t** ee0x000) {
	mov	wreg,EE|0x0000	; do { 
	mov	#EE|0x0000,w1	;  *ee0x000 = EE | ((uint16_t*) 0);   
	mov	[w1],w2		;
	cpseq	w2,w0		;  **ee0x000 = 0xc001;
	bra	coo1cpy		; } while (**ee0x000 != 0xc001);
	return			;} // coolcpy()
	
main:
	rcall	coo1cpy		;void main(void) {
	mov	#adrtrap,w0	; uint16_t w2, * ee_base, * flash_base;
	mov	#0x03fe,w2	; coo1cpy(&ee_base);
autocpy:
	mov	[w0+w2],[w1+w2]	; flash_base = 0x000100;
	dec2	w2		; for (w2 = 0x3fe; w2 >= 0; w2--)
	bra	N,autocpy	;  ee_base[w2] = flash_base[w2];

;;; now try switching to the alternate vector table and doing another copy!
	bset	0xINTCON2,#15	; INTCON2 |= (1 << ALTIVT);
	rcall	coo1cpy		; coo1cpy(&ee_base);
alldone:
	bra	alldone		;} // main()

	;; now perform the operation in the original opcode

	;; stash the status bits on the stack
