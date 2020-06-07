;;; e2ontrap.s
;;;
;;; intercepts misaligned memory accesseses to map the EEPROM into main memory
;;; space, using the AddressError Trap Vector to run routines that manipulate
;;; it behind the scenes
;;;
;;; it might also be feasible to map any access to the last 1/2/4KiB of a 32KiB
;;; data memory segment so that it refers automatically to EEPROM (for dsPIC30
;;; the area between 0x2800 and the PSV window at 0x8000 is always unmapped)
;;;
;;; can't utilize PUSH.S shadow registers to speed entry/exit since not readable
;;;
;;; FIXME: much unnecessary pushing can be solved with better register roles:
;;;                   current                       suggested
;;; w0=wreg           address of output operand     opcode
;;; w1                input operand (or address of) input operand (or address of)
;;; w2                opcode                        address of output operand
;;; w3                base operand (and scratch)    base operand (and scratch)
	.org	0x000000
	goto	main

	.org	0x000008
	.pword	adrtrap

	.org	0x000088
	.pword	0x7ffc00

	.org	0x000100

;;; adrtrap
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
.ifdef B0REQUIRED1
	.equ	EE,0x0001
.else
	.equ	EE,0x0000
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
	lsr	w3,#4,w0	;
op0x10:
	mov.b	#0x01,w1	;
	cpseq.b	w0,w1		;
	bra	op0x40		;  if (w3 & 0x00f0 == SUBR_BR) { //SUBR or SUBBR
	btsc	w3,#3		;
	bra	op0x18		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBR.B	w3,w1,w1	;      __asm__("SUBR.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	SUBR	w3,w1,w1	;      __asm__("SUBR W3,W1,W1");
	bra	op0x1X		;   } else {
op0x18:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov	w0,[w15++]	;
	mov.b	[w15-15],w0	;
	mov.b	wreg,0x0042	;
	mov	[--w15],w0	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //B
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBBR.B	w3,w1,w1	;     __asm__("SUBBR.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	SUBBR	w3,w1,w1	;     __asm__("SUBBR W3,W1,W1");
op0x1X:
	exch	w3,w0		;
	mov.b	0x0042,wreg	;   }
	mov.b	w0,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w3,w0		;
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x40:
;	lsr	w3,#4,w0	;
	mov.b	#0x04,w1	;
	cpseq.b	w0,w1		;
	bra	op0x50		;  } else if (w3 & 0x00f0 == ADDADDC) {
	btsc	w3,#3		;
	bra	op0x48		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	ADD.B	w3,w1,w1	;     __asm__("ADD.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	ADD	w3,w1,w1	;     __asm__("ADD W3,W1,W1");
	bra	op0x4X		;   } else {
op0x48:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov	w0,[w15++]	;
	mov.b	[w15-15],w0	;
	mov.b	wreg,0x0042	;
	mov	[--w15],w0	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //C
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	ADDC.B	w3,w1,w1	;     __asm__("ADDC.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	ADDC	w3,w1,w1	;     __asm__("ADDC W3,W1,W1");
op0x4X:
	exch	w0,w3		;
	mov.b	0x0042,wreg	;   }
	mov.b	w0,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x50:
;	lsr	w3,#4,w0	;
	mov.b	#0x05,w1	;
	cpseq.b	w0,w1		;
	bra	op0x60		;  } else if (w3 & 0x00f0 == SUBSUBB) {
	btsc	w3,#3		;
	bra	op0x58		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUB.B	w3,w1,w1	;     __asm__("SUB.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	SUB	w3,w1,w1	;     __asm__("SUB W3,W1,W1");
	bra	op0x5X		;   } else {
op0x58:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	mov	w0,[w15++]	;
	mov.b	[w15-15],w0	;
	mov.b	wreg,0x0042	;
	mov	[--w15],w0	;    SR = (SR & 0xff00) | (sp[-7] & 0x00ff); //B
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	SUBB.B	w3,w1,w1	;     __asm__("SUBB.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	SUBB	w3,w1,w1	;     __asm__("SUBB W3,W1,W1");
op0x5X:
	exch	w0,w3		;
	mov.b	0x0042,wreg	;   }
	mov.b	w0,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x60:
;	lsr	w3,#4,w0	;
	mov.b	#0x06,w1	;
	cpseq.b	w0,w1		;
	bra	op0x70		;  } else if (w3 & 0x00f0 == ANDXOR) {
	btsc	w3,#3		;
	bra	op0x68		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	AND.B	w3,w1,w1	;     __asm__("AND.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	AND	w3,w1,w1	;     __asm__("AND W3,W1,W1");
	bra	op0x6X		;   } else {
op0x68:
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	XOR.B	w3,w1,w1	;     __asm__("XOR.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	XOR	w3,w1,w1	;     __asm__("XOR W3,W1,W1");
op0x6X:
	exch	w0,w3		;
	mov.b	0x0042,wreg	;   }
	mov.b	w0,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0x70:
;	lsr	w3,#4,w0	;
	mov.b	#0x07,w1	;
	cpseq.b	w0,w1		;
	bra	op0x90		;  } else if (w3 & 0x00f0 == IORMOV) {
	btsc	w3,#3		;
	bra	op0x78		;   if (w3 & 0x0008 == 0) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	IOR.B	w3,w1,w1	;     __asm__("IOR.B W3,W1,W1");
	btss	w2,#14		;    else
.endif
	IOR	w3,w1,w1	;     __asm__("IOR W3,W1,W1");
	exch	w0,w3		;
	mov.b	0x0042,wreg	;
	mov.b	w0,[w15-13]	;    sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	bra	op0x7X		;   } else {
op0x78:
	rcall	rewrm78		;    rewrm78(&w0, &w1, w2, &w3);
;;; FIXME: rewrm78() must handle pre/post like rewrite() but offsets instead of
;;; constants, w1 an address (not value), w3 clear if not offset indirect access
.ifndef	B0REQUIRED1
	btsc	w2,#14		;    if (w2 & (1 << 14)) // Byte access
	MOV.B	[w1+w3],w1	;     __asm__("MOV.B [W1+W3],W1");
	btss	w2,#14		;    else
.endif
	MOV	[w1+w3],w1	;     __asm__("MOV [W1+W3],W1");
op0x7X:
	rcall	writebk		;   }
	bra	advanpc		;   writebk(&w0, w1);

op0x90:
;	lsr	w3,#4,w0	;
	mov.b	#0x09,w1	;
	cpseq.b	w0,w1		;
	bra	op0xa0		;  } else if (w3 & 0x00f0 == MOVSOFF) {
	rcall	rewrmov		;   rewrmov(&w0, &w1, w2, &w3); // no pre/posts
.ifndef	B0REQUIRED1
	btsc	w2,#14		;   if (w2 & (1 << 14)) // Byte access
	MOV.B	[w1],w1		;    __asm__("MOV.B [W1],W1");
	btss	w2,#14		;   else
.endif
	MOV	[w1],w1		;    __asm__("MOV [W1],W1");
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;

op0xa0:
;	lsr	w3,#4,w0	;
	mov.b	#0x0a,w1	;
	cpseq.b	w0,w1		;
	bra	op0xb0		;  } else if (w3 & 0x00f0 = BTSTCLR) {
	and	#0x000f,w3	;
	bra	w3		;   switch (w3 & 0x000f) {
	bra	dobset		;   case 0x0: goto dobset;
	bra	dobclr		;   case 0x1: goto dobclr;
	bra	dobtg		;   case 0x2: goto dobtg;
	bra	dobtst3		;   case 0x3: goto dobtst3;
	bra	dobtsts		;   case 0x4: goto dobtsts;
	bra	dobtst5		;   case 0x5: goto dobtst5;
	bra	dobtss		;   case 0x6: goto dobtss;
	bra	dobtsc		;   case 0x7: goto dobtsc;
	bra	advanpc		;
	bra	advanpc		;
	bra	advanpc		;
	bra	advanpc		;
	bra	advanpc		;
	bra	dobsw		;   case 0xd: goto dobsw;
	bra	advanpc		;
	bra	advanpc		;   }

op0xb0:
;	lsr	w3,#4,w0	;
	mov	#0x0b,w1	;
	cpseq.b	w0,w1		;
	bra	op0xc0		;  } else if (w3 & 0x00f0 == MUL_TBL) {
	and	w3,#0x0e,w0	;
	mov	#0x08,w1	;
	cpseq.b	w0,w1		;
	bra	op0xba		;   if (w3 & 0x000e == MULSUSU)
	rrc	w3,#1,w3	;
	rrc	w2,#13,w3	;
	and	#0xc0,w3	;
	bra	w3		;    switch (((w3 & 1) << 1) | (w2 >> 15)) {
	rcall	rewrmul		;    case 0: rewritm(&w0, &w1, &w2, &w3);
	MUL.UU  W3,W1,W2	;            __asm__("MUL.UU W3,W1,W2");
	rcall	writebm		;            writebm(&w0, w2, w3);
	bra	advanpc		;            break;
	rcall	rewrmul		;    case 1: rewritm(&w0, &w1, &w2, &w3);
	MUL.US	W3,W1,W2	;            __asm__("MUL.US W3,W1,W2");
	rcall	writebm		;            writebm(&w0, w2, w3);
	bra	advanpc		;            break;
	rcall	rewrmul		;    case 2: rewritm(&w0, &w1, &w2, &w3);
	MUL.SU	W3,W1,W2	;            __asm__("MUL.SU W3,W1,W2");
	rcall	writebm		;            writebm(&w0, w2, w3);
	bra	advanpc		;            break;
	rcall	rewrmul		;    case 3: rewritm(&w0, &w1, &w2, &w3);
	MUL.SS	W3,W1,W2	;            __asm__("MUL.SS W3,W1,W2");
	rcall	writebm		;            writebm(&w0, w2, w3);
	bra	advanpc		;            break;
op0xba:
	and	w3,#0x0e,w0	;
	mov	#0x0a,w1	;
	cpseq.b	w0,w1		;
	bra	op0xbe		;   else if (w3 & 0x000e == TBLRWHL) {
	rrc	w3,#1,w3	;
	rrc	w2,#13,w2	;
	and	#0xe0,w2	;    w2 = ((w3 & 1) << 3) | ((w2 >> 13) & 0x06);
	rcall	rewr???		;    rewr???(&w0, &w1, w2, &w3);
	bra	w3		;    switch ((((w3 & 1) << 2) | (w2 >> 14))/2) {
	TBLRDL.W [W1],W1	;    case 0: __asm__("TBLRDL.W W1,[W0]");
	bra	tbldone		;            writebk(&w0, w1); break;
	TBLRDL.B [W1],W1	;    case 1: __asm__("TBLRDL.B W1,[W0]");
	bra	tbldone		;            writebk(&w0, w1); break;
	TBLRDH.W [W1],W1	;    case 2: __asm__("TBLRDH.W W1,[W0]");
	bra	tbldone		;            writebk(&w0, w1); break;
	TBLRDH.B [W1],W1	;    case 3: __asm__("TBLRDH.B W1,[W0]");
	bra	tbldone		;            writebk(&w0, w1); break;
	TBLWTL.W W1,[W0]	;    case 4: __asm__("TBLWT.W W1,[W0]");
	bra	advanpc		;            break;
	TBLWTL.B W1,[W0]	;    case 5: __asm__("TBLWT.B W1,[W0]");
	bra	advanpc		;            break;
	TBLWTH.W W1,[W0]	;    case 6: __asm__("TBLWT.W W1,[W0]");
	bra	advanpc		;            break;
	TBLWTH.B W1,[W0]	;    case 7: __asm__("TBLWT.B W1,[W0]");
	bra	advanpc		;            break;
tbldone:
	rcall	writebk		;    }
	bra	advanpc		;
op0xbe:
	mov	#0xbe,w1	;
	cpseq.b	w3,w1		;
	bra	op0xc0		;   } else if (w3 & 0x000f == MOVD) {
	rcall 	rewrm78		;    rewrm78(&w0, &w1, w2, &w3); // ok to reuse?
	MOV.D	[W1],W2		;    __asm__("MOV.D [W1],W2");
	rcall	writebd		;    writebd(&w0, w2, w3);
	bra	advanpc		;   }

op0xc0:
;	lsr	w3,#4,w0	;
	mov	#0x0c,w1	;
	cpseq.b	w0,w1		;
	bra	op0xd0		;  } else if (w3 & 0x00f0 == FF1) {
	and	w3,#0xf,w0	;
	mov	#0x0f,w1	;
	cpseq.b	w0,w1		;
	bra	advanpc		;   if (w3 & 0x000f == FF1L_1R) {
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3); // ok to reuse?
	btsc	w2,#15		;    if (w2 & (1 << 15))
	FF1L	W1,W1		;     __asm__("FF1L W1,W1");
	btss	w2,#15		;    else
	FF1R	W1,W1		;     __asm__("FF1R W1,W1");
	rcall	writebk		;    writebk(&w0, w1);
	exch	w0,w3		;
	mov.b	0x0042,wreg	;
	mov.b	w0,[w15-13]	;    sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	bra	advanpc		;

op0xd0:
;	lsr	w3,#4,w0	;
	mov	#0x0d,w1	;
	cpseq.b	w0,w1		;
	bra	op0xe0		;  } else if (w3 & 0xf0 == RSLRNCB) {
	mov	#0x0f,w1	;
	and	w1,w3,w0	;
	cpsne.b	w0,w1		;
	bra	op0xdf		;   if (w3 & 0x000f == BCL) {
	mov	w3,[w15++]	;
	rcall	rewrite		;    rewrite(&w0, &w1, w2, w3); // no base reg.
	mov	[--w15],w3	;
	sl	w3,#3,w3	;
	lsr	w2,#13,w2	;
	ior	w2,w0,w2	;
	and	w2,#0x1e	;
	bra	w2		;    switch (((w3 & 0x03) << 2) | (w2 >> 14)) {
	SL	w1,w1		;    case 0x0: __asm__("SL W1,W1");
	bra	writebs		;              break;
	SL.B	w1,w1		;    case 0x1: __asm__("SL.B W1,W1");
	nop			;              break;
	bra	advanpc		;    case 0x2:
	nop			;
	bra	advanpc		;    case 0x3: goto advanpc;//non-canonical bits
	bra	writebs		;
	LSR	w1,w1		;    case 0x4: __asm__("LSR W1,W1");
	bra	writebs		;              break;
	LSR.B	w1,w1		;    case 0x5: __asm__("LSR.B W1,W1");
	bra	writebs		;              break;
	ASR	w1,w1		;    case 0x6: __asm__("ASR W1,W1");
	bra	writebs		;              break;
	ASR.B	w1,w1		;    case 0x7: __asm__("ASR.B W1,W1");
	bra	writebs		;              break;
	RLNC	w1,w1		;    case 0x8: __asm__("RLNC W1,W1");
	bra	writebs		;              break;
	RLNC.B	w1,w1		;    case 0x9: __asm__("RLNC.B W1,W1");
	bra	writebs		;              break;
	RLC	w1,w1		;    case 0xa: __asm__("RLC W1,W1");
	bra	writebs		;              break;
	RLC.B	w1,w1		;    case 0xb: __asm__("RLC.B W1,W1");
	bra	writebs		;              break;
	RRNC	w1,w1		;    case 0xc: __asm__("RRNC W1,W1");
	bra	writebs		;              break;
	RRNC.B	w1,w1		;    case 0xd: __asm__("RRNC.B W1,W1");
	bra	writebs		;              break;
	RRC	w1,w1		;    case 0xe: __asm__("RRC W1,W1");
	bra	writebs		;              break;
	RRC.B	w1,w1		;    case 0xf: __asm__("RRC.B W1,W1");
	bra	writebs		;              break;
writebs:
	exch	w0,w3		;
	mov.b	0x0042,wreg	;    }
	mov.b	w0,[w15-13]	;    sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	rcall	writebk		;    writebk(&w0, w1);
	bra	advanpc		;   } else {
op0xdf:	
	rcall	rewrite		;    rewrite(&w0, &w1, w2, &w3);
	FBCL	W1,W1		;    __asm__("FBCL W1,W1");
	rcall	writebk		;    writebk(&w0, w1);
	bra	advanpc		;   }
op0xe0:
	sl	w3,#1,w3	;  } else {
	and	w3,#0x17,w3	;   // N B N N N
	btsc	w2,#14		;   //  \ \ \ \ \_w2 bit 15 (which opcode in box
	ior	w3,#0x04,w3	;   //   \ \ \ \_w3 bit 0     shown in Table 6-2)
	rlc	w2,#1,w0	;   //    \ \ \_w3 bit 1
	rlc	w3,#1,w3	;   //     \ \_w2 bit 14 (Byte mode flag)
	sl	w3,#1,w3	;   //      \_w3 bit 3
	mov	w3,[w15++]	;   uint16_t temp = (w3&0x0b)|((w2&0x4000)?4:0);
	rcall	rewrite		;   rewrite(&w0, &w1, w2, &w3); // need W3+B bit
	mov	[--w15],w2	;
	bra	w2		;   switch (w2 = (temp<<1) | (w2&(1<<15)?1:0)) {
	CP0	W1		;   case 0x00: __asm__("CP0 W1"); // 0000 00
	bra	writebs		;	       goto writebs;
	nop			;   case 0x01: goto advanpc;//non-canonical bits
	bra	advanpc		;
	CP	W3,W1		;   case 0x02: __asm__("CP W3,W1"); // 0001 00
	bra	writebs		;	       goto writebs;
	CPB	W3,W1		;   case 0x03: __asm__("CPB W3,W1"); // 0001 10
	bra	writebs		;	       break;
	RLNC	W1,W1		;   case 0x04: __asm__("RLNC W1,W1"); // 0010 00
	bra	writebc		;	       break;
	RLC	W1,W1		;   case 0x05: __asm__("RLC W1,W1"); // 0010 10
	bra	writebc		;	       break;
	RRNC	W1,W1		;   case 0x06: __asm__("RRNC W1,W1"); // 0011 00
	bra	writebc		;	       break;
	RRC	W1,W1		;   case 0x07: __asm__("RRC W1,W1"); // 0011 10
	bra	writebc		;	       break;
	CP0.B	W1		;   case 0x08: __asm__("CP0.B W1"); // 0000 01
	bra	writebs		;	       goto writebs;
	nop			;   case 0x09: goto advanpc;//non-canonical bits
	bra	advanpc		;
	CP.B	W3,W1		;   case 0x0a: __asm__("CP.B W3,W1"); // 0001 01
	bra	writebs		;	       goto writebs;
	CPB.B	W3,W1		;   case 0x0b: __asm__("CPB.B W3,W1");// 0001 11
	bra	writebs		;	       goto writebs;
	RLNC.B	W1,W1		;   case 0x0c: __asm__("RLNC.B W1,W1");//0010 01
	bra	writebc		;	       break;
	RLC.B	W1,W1		;   case 0x0d: __asm__("RLC.B W1,W1");// 0010 11
	bra	writebc		;	       break;
	RRNC.B	W1,W1		;   case 0x0e: __asm__("RRNC.B W1,W1");//0011 01
	bra	writebc		;	       break;
	RRC.B	W1,W1		;   case 0x0f: __asm__("RRC.B W1,W1");// 0011 11
	bra	writebc		;	       break;
	INC	W1,W1		;   case 0x10: __asm__("INC W1,W1"); // 1000 00
	bra	writebc		;	       break;
	INC2	W1,W1		;   case 0x11: __asm__("INC2 W1,W1"); // 1000 10
	bra	writebc		;	       break;
	DEC	W1,W1		;   case 0x12: __asm__("DEC W1,W1"); // 1001 00
	bra	writebc		;	       break;
	DEC2	W1,W1		;   case 0x13: __asm__("DEC2 W1,W1"); // 1001 10
	bra	writebc		;	       break;
	NEG	W1,W1		;   case 0x14: __asm__("NEG W1,W1"); // 1010 00
	bra	writebc		;	       break;
	COM	W1,W1		;   case 0x15: __asm__("COM W1,W1"); // 1010 10
	bra	writebc		;	       break;
	CLR	W1		;   case 0x16: __asm__("CLR W1"); // 1011 00
	bra	writebc		;	       break;
	SETM	W1		;   case 0x17: __asm__("SETM W1"); // 1011 10
	bra	writebc		;	       break;
	INC.B	W1,W1		;   case 0x18: __asm__("INC.B W1,W1");// 1000 01
	bra	writebc		;	       break;
	INC2.B	W1,W1		;   case 0x19: __asm__("INC2.B W1,W1");//1000 11
	bra	writebc		;	       break;
	DEC.B	W1,W1		;   case 0x1a: __asm__("DEC.B W1,W1");// 1001 01
	bra	writebc		;	       break;
	DEC2.B	W1,W1		;   case 0x1b: __asm__("DEC2.B W1,W1");//1001 11
	bra	writebc		;	       break;
	NEG.B	W1,W1		;   case 0x1c: __asm__("NEG.B W1,W1");// 1010 01
	bra	writebc		;	       break;
	COM.B	W1,W1		;   case 0x1d: __asm__("COM.B W1,W1");// 1010 11
	bra	writebc		;	       break;
	CLR.B	W1		;   case 0x1e: __asm__("CLR.B W1");// 1011 01
	bra	writebc		;	       break;
	SETM.B	W1		;   case 0x1f: __asm__("SETM.B W1");// 1011 11
;	nop			;
writebc:
	exch	w0,w3		;
	mov.b	0x0042,wreg	;   }
	mov.b	w0,[w15-13]	;   sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	rcall	writebk		;   writebk(&w0, w1);
	bra	advanpc		;  }

	;; advance the stacked PC by one instruction (e.g. if not a branch/skip)
advanpc:
	rcall	nextins		;  advanpc: nextins();
.if SD_CACHE_WRITEBACK
.endif
	mov	#0x0032,w1	;  w1 = &TBLPAG;
	mov	[--w15],[w1]	;  *w1 = *--w15; // TBLPAG restored
	;; clear the fault bit before returning to prevent a bounceback
adrdone:
	mov.d	[--w15],w2	; }
	mov.d	[--w15],w0	; w3 = *--sp, w2 = *--sp;
	bclr	0x0080,#3	; w1 = *--sp, w0 = *--sp;
	retfie			; return INTCON1 &= ~(1 << ADDRERR);
	;; actual exit is above; code below is reached with a goto from switch
dobset:
	rcall	rewrbop		; dobset: rewrbop(&w0, &w1, &w2, &w3);
	mov	w1,w0		; w0 = w1;
	mov	#0x0001,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	IOR	w3,[w1],w1	; __asm__("IOR W3,[W1],W1");
	rcall	writebk		; writebk(&w0);
	bra	advanpc		; goto advanpc;
dobclr:
	rcall	rewrbop		; dobclr: rewrbop(&w0, &w1, &w2, &w3);
	mov	w1,w0		; w0 = w1;
	mov	#0xfffe,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	AND	w3,[w1],w1	; __asm__("AND W3,[W1],W1");
	rcall	writebk		; writebk(&w0);
	bra	advanpc		; goto advanpc;
dobtg:
	rcall	rewrbop		; dobtg: rewrbop(&w0, &w1, &w2, &w3);
	mov	w1,w0		; w0 = w1;
	mov	#0x0001,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	XOR	w3,[w0],w1	; __asm__("XOR W3,[W1],W1");
	rcall	writebk		; writebk(&w0);
	bra	advanpc		; goto advanpc;
dobtst3:
	rcall	rewrbop		; dobtst3: rewrbop(&w0, &w1, &w2, &w3);
	btsc	w2,#15		; if (w2 & (1<<15))
	BTST.Z	[w1],w2		;  __asm__("BTST.Z [W1],W2");
	btss	w2,#15		; else
	BTST.C	[w1],w2		;  __asm__("BTST.C [W1],W2");
	exch	w0,w3		;
	mov.b	0x0042,wreg	; // w0=w1=address, w2=Z|00000000000|bitnum
	mov.b	w0,[w15-13]	; sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	bra	advanpc		; goto advanpc;
dobtsts:
	rcall	rewrbop		; dobtst3: rewrbop(&w0, &w1, &w2, &w3);
	btsc	w2,#15		; if (w2 & (1<<15))
	BTST.Z	[w1],w2		;  __asm__("BTST.Z [W1],W2");
	btss	w2,#15		; else
	BTST.C	[w1],w2		;  __asm__("BTST.C [W1],W2");
	exch	w0,w3		;
	mov.b	0x0042,wreg	; // w0=w1=address, w2=Z|00000000000|bitnum
	mov.b	w0,[w15-13]	; sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	mov	w1,w0		; w0 = w1;
	mov	#0x0001,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	IOR	w3,[w1],w1	; __asm__("IOR W3,[W1],W1");
	rcall	writebk		; writebk(&w0);
	bra	advanpc		; goto advanpc;
dobtst5:
	rcall	rewrbop		; dobtst5: rewrbop(&w0, &w1, &w2, &w3);
	sl	w2,#1,w3	;
	and	#0x01e,w3	; w3 = (w2 & 0x000f) /*bit#*/ << 1;
	btsc	w3,#4		; //copied from rewrite():
	bra	b4w15br		;
	btsc	w3,#3		;
	bra	b4w15br		; if (*w3 & 0x018 == 0) // w0/w1/w2/w3 off stack
	sub	w3,#0x0e,w3	;
	mov	[w15+w3],w3	;  *w3 = sp[*w3 - 7]; // since w0 at SP-0x0c etc
	bra	bbaseok		; else
b4w15br:
	mov	[w3],w3		;  *w3 = **w3; // won't touch r3 again
bbaseok:
	btsc	w2,#15		; if (w2 & (1<<15))
	BTST.Z	[w1],w3		;  __asm__("BTST.Z [W1],W2");
	btss	w2,#15		; else
	BTST.C	[w1],w3		;  __asm__("BTST.C [W1],W2");
	exch	w0,w3		;
	mov.b	0x0042,wreg	; // w0=w1=address, w2=Z|00000000000|bitnum
	mov.b	w0,[w15-13]	; sp[-7] = (sp[-7] & 0xff00) | (SR & 0x00ff);
	exch	w0,w3		;
	bra	advanpc		; goto advanpc;
dobtss:
	rcall	rewrbop		; dobtss: rewrbop(&w0, &w1, &w2, &w3);
	mov	#0x0042,w0	;
	mov	#0x0001,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	and	w3,[w1],w1	; w1 = w3 & *w1;
	btss	[w0],#1		; if (w1) // AND result was nonzero
	rcall	nextins		;  nextins(); // so we skip an instruction
	bra	advanpc		; goto advanpc; // then a subsequent nextins()
dobtsc:
	rcall	rewrbop		; dobtsc: rewrbop(&w0, &w1, &w2, &w3);
	mov	#0x0042,w0	;
	mov	#0x0001,w3	; // w0=w1=address, w2=bitnum
	rlnc	w3,w2,w3	; w3 = 1 << w2;
	and	w3,[w1],w1	; w1 = w3 & *w1;
	btsc	[w0],#1		; if (!w1) // AND result was zero
	rcall	nextins		;  nextins(); // so we skip an instruction
	bra	advanpc		; goto advanpc; // then a subsequent nextins()
dobsw:
	rcall	rewrbop		; dobtsc: rewrbop(&w0, &w1, &w2, &w3);
	mov	w1,w0		; w0 = w1;
	mov	[w1],w1		; w1 = *w1;
	btsc	w2,#15		; if (w2 & (1<<15))
	BSW.Z	w1,w2		;  __asm__("BTST.Z W1,W2");
	btss	w2,#15		; else
	BSW.Z	w1,w2		;  __asm__("BTST.C W1,W2");
	rcall	writebk		; writebk(&w0);
	bra	advanpc		; goto advanpc;
				;} // adrtrap()

.macro	fixwadr	w
.ifdef B0REQUIRED1
	btss	\w,#0		;inline void fixwadr(uint16_t* *w) {
	bra	2f		;// access EEPROM mapped into a RAM word
.else
	btsc	\w,#0		;
	bra	1f		;
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
.endif
	sl	\w,#4,\w	;
	bset	0x0042,#0	;
	asr	\w,#4,\w	;  (*w) |= 0xf001; // fool it, get it? ;-)
.if EEPROM_SIZE < 4096
	bset	\w,#11		;  if (EEPROM_SIZE < 0x1000) (*w) |= 0x0800;
.endif
.if EEPROM_SIZE < 2048
	bset	\w,#10		;  if (EEPROM_SIZE < 0x0800) (*w) |= 0x0400;
.endif
	bset	\w,#0		; } } // fixwadr()
2:
.endm

.macro	relolow	addr,fullchk
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
.macro	addrnum rnum,dest
	sl	\rnum,#1,\dest	;inline uint16_t addrnum(uint4_t rnum) {
	and	#0x01e,\dest	; return relolow((rnum << 1) & 0x001e);
	relolow	\dest,0		;} // addrnum()
.endm

;;; direct()
;;; indir()
;;; postdec()
;;; postinc()
;;; predec()
;;; preinc()
;;;
;;; are called by addrmod() to extract the effective address of an instruction
;;; using W2, returned in R0
;;; C bit will be set by addrmod() if a byte instruction is being attempted
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
direct:
	addrnum	w2,w0		;uint16_t direct(uint16_t w2){return addrnum(w2)
	return			;} // direct()
indir:
	addrnum	w2,w0		;uint16_t indir(uint16_t w2) {
	mov	[w0],w0		; uint16_t* w0 = addrnum(w2);
	relolow	w0,1		; return relolow(*w0);
	return			;} // indir()
postdec:
	addrnum	w2,w0		;uint16_t postdec(uint16_t w2, uint1_t B) {
	mov	[w0],[w15++]	; uint16_t* w0 = addrnum(w2);
.ifndef B0REQUIRED1
	btsc	0x0042,#0	; uint16_t temp = *w0;
	dec	[w0]		; if (B)
	btss	0x0042,#0	;  *(w0 = (uint8_t*) w0)++;
.endif
	dec2	[w0]		; else
	mov	[--w15],w0	;  *(w0 = (uint16_t*) w0)++;
	relolow	w0,1		; return relolow(temp);
	return			;} // postdec()
postinc:
	addrnum	w2,w0		;uint16_t postinc(uint16_t w2, uint1_t B) {
	mov	[w0],[w15++]	; uint16_t* w0 = addrnum(w2);
.ifndef B0REQUIRED1
	btsc	0x0042,#0	; uint16_t temp =*w0;
	inc	[w0]		; if (B)
	btss	0x0042,#0	;  *(w0 = (uint8_t*) w0)++;
.endif
	inc2	[w0]		; else
	mov	[--w15],w0	;  *(w0 = (uint16_t*) w0)++;
	relolow	w0,1		; return relolow(temp);
	return			;} // postinc()
predec:
	addrnum	w2,w0		;uint16_t predec(uint16_t w2, uint1_t B) {
.ifndef B0REQUIRED1
	btsc	0x0042,#0	; uint16_t* w0 = addrnum(w2);
	dec	[w0],[w0]	; if (B)
	btss	0x0042,#0	;  --*((uint8_t*) w0);
.endif
	dec2	[w0],[w0]	; else
	mov	[w0],w0		;  --*((uint16_t*) w0);
	relolow	w0,1		; return relolow(*w0);
	return			;} // predec()
preinc:
	addrnum	w2,w0		;uint16_t preinc(uint16_t w2, uint1_t B) {
.ifndef B0REQUIRED1
	btsc	0x0042,#0	; uint16_t* w0 = addrnum(w2);
	inc	[w0],[w0]	; if (B)
	btss	0x0042,#0	;  ++*((uint8_t*) w0);
.endif
	inc2	[w0],[w0]	; else
	mov	[w0],w0		;  ++*((uint16_t*) w0);
	relolow	w0,1		; return relolow(*w0);
	return			;} // preinc()

;;; addrmod()
;;;
;;; may be called with C bit set to indicate Byte mode instruction if supported
;;;
;;; based on the 3-bit addressing mode (always preceding the 4-bit register num)
;;; will return in w0 the effective address to obtain the data with the affected
;;; indirect register already changed (either W4 to W14 directly, or the W0 to
;;; W3 values on the stack changed)
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
	bra	direct		;  case 0: return direct(w2);
	bra	indir		;  case 1: return indir(w2);
	bra	postdec		;  case 2: return postdec(w2, B);
	bra	postinc		;  case 3: return postinc(w2, B);
	bra	predec		;  case 4: return predec(w2, B);
	bra	preinc		;  case 5: return preinc(w2, B);
	bra	indir		; }        return indir(w2, B); // reg+off "mov"
	bra	indir		;} // addrmod()

.macro	eepromw	code,scratch,adreg
	mov	\code,\scratch	;inline void eepromw(int code, uint16_t adreg) {
	mov	\scratch,0x0760	; NVMCON = code; // per DS70138C EXAMPLE 6-3,4
	mov	0x007f,\scratch	;
	mov	\adreg,0x0762	; NVMADR = adreg;
	mov	\scratch,0x0764	; NVMADRU = 0x007f;
	mov	\scratch,0x0032	; TBLPAG = 0x007f; // need for write (not erase)
	disi	#5		;
	mov	#0x0055,\scratch;
	mov	\scratch,0x0766	; NVMKEY = 0x0055;
	mov	#0x00aa,\scratch;
	mov	\scratch,0x0766	; NVMKEY = 0x00aa;
	bset	0x0760,#15	; NVMCON |= (1 << WR);// initiate erase/write op
	nop			;
	nop			;
	btsc	0x0760,#15	; do {} while (NVMCON & (1 << WR));
	bra	.-2		;} // eepromw()
.endm

;;; writebk()
;;;
;;; completes a rewritten instruction operation by writing the value in W1 to
;;;  the address in W0, which may a register (0x0000 to 0x001e) or EEPROM mapped
;;;  into unused RAM space
;;; FIXME: needs to handle byte mode if supported, possibly via C flag set
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
	return			;} // writebk()

;;; rewrite()
;;; handles ALU instructions of the form OPCODE Rbase,#lit,[Rdest] or
;;;                                      OPCODE Rbase,[Rsrc],[Rdest]
;;; by returning the contents of Rbase in W3 (clobbering the operation's nature)
;;;              the original opcode fields in W2 (unclobbered)
;;;              the result of accessing #lit or [Rsrc] in W1,
;;;              the effective address to write back to the destinationin W0
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
	bra	srcdone		;  else { // EEPROM address
seeprom:
	mov	#0x007f,w1	;
	mov	w1,0x0032	;   TBLPAG = 0x007f;
	bclr	w0,#0		;   *w1 = *((*w0) & 0xfffe);
	tblrdl	[w0],w1		;  }
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
	rlnc	w2,w2		; // specified (awkwardly) in opcode bits 18..15
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

;;; rewrite()
;;; handles MOV instructions of the form MOV [Rsrc],[Rdest] or
;;;                                      MOV [Rsrc+Slit10],[Rdest+Slit10]
;;; by returning the signed literal in W3 (or 0 if it isn't present)
;;;              the original opcode fields in W2 (unclobbered)
;;;              the result of accessing [Rsrc] or [Rsrc+Slit10] in W1,
;;;              the effective address to write back to the destination in W0
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
	sl	w2,#1,w1	; // w3=00000000 1001?kkk, w2=kBkkkddd dkkkssss
	rlc	w3,#7,w1	; // w1=01001?kk kk000000
	lsr	w2,#3,w0	; //                       w0=000kBkkk ddddkkks
	swap.b	w0,w0		; //                       w0=000kBkkk kkksdddd
	lsr	w0,#5,w0	; //                       w0=00000000 kBkkkkkk
	and	#0x003f,w0	; //                       w0=00000000 00kkkkkk
	ior	w0,w1,w3	;extern extract_slit10();//w3=01001?kk kkkkkkkk
	btsc	w3,#10		;void rewrmov(u16* w0,u16* w1,u16 w2,u16* w3) {
	bra	mov2off		; if ((*w3=extract_slit10(w2,*w3))&0x0400 == 0){
	sl	w3,#6,w3	;  // MOV{.B} [Ws+Slit10],Wnd
	asr	w3,#5,w3	;  *w3 = (int16_t)((int10_t)w3);//sign-extend w3
	btsc	w2,#14		;  if (w2 & (1<<12) == 0) // Byte mode halfrange
	asr	w3,#1,w3	;   *w3 <<= 1;// but Word range is -1024 to 1022
	sl	w2,#1,w1	;
	and	#0x01e,w1	;  *w1 = (w2 << 1) & 0x001e;
	relolow	w1,0		;
	mov	[w1],w1		;
	add	w3,w1,w1	;
	relolow	w1,1		;  *w1 = relolow(*relolow(*w1)+w3); // src addr
	fixwadr	w1		;  fixwadr(w1); // address "fixed" if in EEPROM
	btsc	w1,#0		;
	bra	mseprom		;  if ((*w1) & 1 == 0) // RAM address
	mov	[w1],w1		;   *w1 = **w1; // store contents in w1 for oper
	bra	msdone		;  else { // EEPROM address
mseprom:
	mov	#0x007f,w3	;
	mov	w3,0x0032	;   TBLPAG = 0x007f;
	bclr	w1,#0		;
	tblrdl	[w1],w1		;   *w1 = *((*w1) & 0xfffe);
msdone:
	lsr	w2,#6,w0	;  }
	and	w0,#0x01e,w0	;
	relolow	w0,0		;  *w0 = relolow((w2 >> 6) & 0x001e);// dst addr
	bra	mreturn		; } else {
mov2off:
	sl	w3,#6,w3	;  // MOV{.B} Wns,[Wd+Slit10]
	asr	w3,#5,w3	;  *w3 = (int16_t)((int10_t)w3);//sign-extend w3
.ifndef	B0REQUIRED1
	btsc	w2,#14		;  if (w2 & (1<<12) == 0) // Byte mode halfrange
	asr	w3,#1,w3	;
.endif
	lsr	w2,#6,w0	;   *w3 <<= 1;// but Word range is -1024 to 1022
	and	#0x01e,w0	;  *w0 = (w2 >> 6) & 0x001e;
	relolow	w0,0		;
	mov	[w0],w0		;
	add	w3,w0,w0	;
	relolow	w0,1		;  *w0 = relolow(*relolow(*w0)+w3); // dst addr
	sl	w2,#1,w1	;
	and	w1,#0x01e,w1	;
	relolow	w1,0		;  *w1 = relolow((w2 << 1) & 0x001e);// src addr
mreturn:
	return			; } } // rewrmov()

;;; rewrbop()
;;;
;;; (unlike the above, the value returned in W1 is an address, not a value!)
;;;
;;;
rewrbop:
	btst.c	w2,#10		;void rewrbop(uint16_t* w0, uint16_t* w1,
	and	w3,#0xc0,w0	;             uint16_t* w2, uint16_t* w3) {
	bra	nz,bytemod	; uint1_t b = w2 & 0x0400 ? 1 : 0; // Bmode flag
	lsr	w0,#1,w0	; if (*w3 & 0x00c0) b = 0; // only bset/bclr/btg
bytemod:
	rcall	addrmod		; *w0 = addrmod(w2, c);
	fixwadr	w0		; fixwadr(w0); // address "fixed" if in EEPROM
	btsc	w0,#0		;
	bra	beeprom		; if ((*w0) & 1 == 0) // RAM address
	mov	[w0],w1		;  *w1 = **w0; // store contents in w1 for oper
	bra	bsdone		; else { // EEPROM address
beeprom:
	mov	#0x007f,w1	;
	mov	w1,0x0032	;  TBLPAG = 0x007f;
	bclr	w0,#0		;  *w1 = *((*w0) & 0xfffe);
	tblrdl	[w0],w1		; }
bsdone:
	mov	#0x0005,w0	;
	and	w3,w0,w3	;
	cpseq	w0,w3		;
	bra	bZin11		; if ((*w3 == 5/*btss*/) || (*w3 == 11/*bsw*/)){
	sl	w2,#1,w2	;  uint1_t c = (*w2) & 0x8000 ? 1 : 0;
	mov.b	#11,w2		;  // Zwww w000 in H byte -> 000w wwwZ in L byte
	bsw.c	w2,w2		;  *w2 = ((*w2) && 0x0xf000) >> 11) | c;
	rlnc	w2,#1,w2	; } else // sign bit contains Z flag, low nybble
bZin11:
	rrnc	w2,#12,w2	;  *w2 = ((*w2) & 0x0800) | ((*w2) >> 12);//bbbb
	return			;} // rewrbop()

;;; nextins()
;;; advances the Program Counter stored on the stack at the time of the trap
;;; by 2 words (to the next 24-bit instruction)
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
nextins:
	sub	w15,#0x00c,w1	;void nextins(void) {
	inc2	[w1],[w1]	;
	bra	nc,nextinc	;
	sub	w15,#0x012,w1	;
	inc	[w1],[w1]	;  *((uint32_t*) &sp[-6]) += 2; // PC += 2
nextinc:
	return			;} // nextins()

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
