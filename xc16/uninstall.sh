#!/bin/sh
# $0          removes from default directory /usr/local/bin/
# $0 $HOME    removes from home directory ~/bin
if [ $# -gt 0 ]
then
    INSTALLDIR=$1/bin
else
    INSTALLDIR=/usr/local/bin
fi
rm -v $INSTALLDIR/../c30_device.info
for binfile in elf-ar elf-as elf-bin2hex elf-objdump elf-strip
do
    rm -v $INSTALLDIR/$binfile
done
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR
