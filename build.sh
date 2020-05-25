#!/bin/sh
fromdos -V || exit 1
msgfmt -V || exit 2
if $#
then
 wget $1 || echo "only arg should be URL to an mplabalc30 tarball, if not v3_31"
else
 wget http://ww1.microchip.com/downloads/en/DeviceDoc/mplabalc30v3_31.tgz || exit 3
fi
tar xvzf *.t*gz || exit 4
for dosfile in $(find acme -print); do fromdos $dosfile 2> /dev/null; done
cd acme
./configure pic30-unknown-elf # change to pic30-unknown-coff if old-style format
make # will fail for missing Makefile target
echo "all:" > ./libiberty/testsuite/Makefile
echo >& ./libiberty/testsuite/Makefile
echo "install:" > ./libiberty/testsuite/Makefile
echo >& ./libiberty/testsuite/Makefile
make
sudo make install
