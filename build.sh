#!/bin/sh
# $0          grabs default package off the web, installs in default directory
# $0 -V       uses tarball in current directory, installs in default directory
# $0 -V $HOME uses tarball in current directory, installs in home directory
#
# Note: After v3_02, Microchip broke wget scripts by requiring a credential to
#       download the GPL source code(!)
#       As a workaround, save the gzip'ed tarball in the current directory and
#       use the -V flag as shown above.
fromdos -V || exit 1
msgfmt -V || exit 2
if [ $# ]
then
 wget $1 || echo "arg1 may be -V, or URL to an mplabalc30 tarball if not v3_02"
else
 wget http://ww1.microchip.com/downloads/en/DeviceDoc/mplabalc30v3_02.tar.gz
fi
tar xvzf *.t*gz || exit 3
for dosfile in $(find acme -print); do fromdos $dosfile 2> /dev/null; done
cd acme
./configure pic30-unknown-elf --prefix=$2 # or, change to pic30-unknown-coff
make # will fail for missing Makefile target
cp ../Makefile.new libiberty/testsuite/Makefile
make && make install # must run as root if installing under /usr/local
