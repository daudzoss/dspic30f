#!/bin/sh
#wget http://ww1.microchip.com/downloads/en/DeviceDoc/mplabalc30v2_05.tgz
tar xvzf mplabalc30v2_05.tgz
for dosfile in $(find acme -print); do fromdos $dosfile 2> /dev/null; done
cd acme
./configure pic30-unknown-elf
make # will fail for missing Makefile
echo "all:" > ./libiberty/testsuite/Makefile
make
