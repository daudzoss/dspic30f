test.elf : test.o
	$(HOME)/bin/xc16-ld -o test.elf test.o

test.o : test.s 14point.inc
	$(HOME)/bin/xc16-as -o test.o -p30F4013 -asml=test.lst test.s
