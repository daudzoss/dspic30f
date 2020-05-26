#!/bin/sh
# $0          grabs default package off the web, installs in default directory
# $0 $HOME    grabs default package off the web, installs in home directory
# $0 $HOME -V uses tarball in current directory, installs in home directory
#
# Note: After v3_02, Microchip broke wget scripts by requiring a credential to
#       download the GPL source code(!)
#       As a workaround, save the gzip'ed tarball in the current directory and
#       use the -V flag as shown above.
fromdos -V || exit 1
msgfmt -V || exit 2
if [ $# -gt 1 ]
then
 wget $2 || echo "arg2 may be -V, or URL to an mplabalc30 tarball if not v3_02"
else
 rm mplabalc30v*.t*gz
 wget http://ww1.microchip.com/downloads/en/DeviceDoc/mplabalc30v3_02.tar.gz
fi

rm -rf acme/ c30_resource/
tar xvzf *.t*gz || exit 3
for dosfile in $(find acme -print); do fromdos $dosfile 2> /dev/null; done
for dosfile in $(find c30_resource -print);do fromdos $dosfile 2> /dev/null;done

cd acme
if [ x$(uname -p | awk '/64$/ { print 1 }')x -eq x1x ] # amd64, arm64, x86_64, etc.
then
    for badfile in $(grep -lr 0xC0007FFF *)
    do
	mv -v $badfile $badfile.bad
	sed 's/0xC0007FFF/0xFFFFFFFFC0007FFFull/' $badfile.bad > $badfile
    done
else
    echo 'not a 64-bit architecture; no patches to constants required'
fi

./configure pic30-unknown-elf --prefix=$1 # or, change to pic30-unknown-coff
make # will fail for missing Makefile target
cp ../Makefile.new libiberty/testsuite/Makefile
make
if [ $# -gt 0 ]
then
    mkdir $1/bin
    cp ../c30_resource/src/c30/c30_device.info $1/bin
else
    cp ../c30_resource/src/c30/c30_device.info /usr/local/bin
fi

