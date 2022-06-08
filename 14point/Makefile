test.elf : test.o
	$(HOME)/bin/xc16-ld test.o -o test.elf

test.o : test.s crt1_standard.s 14point.inc
	$(HOME)/bin/xc16-as -o test.o -p30F4013 -asml=test.lst crt1_standard.s test.s
