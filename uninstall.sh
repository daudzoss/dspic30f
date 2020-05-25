#!/bin/sh
# $0          removes from default directory /usr/local/
# $0 $HOME    removes from home directory
if [ $# ]
then
    INSTALLDIR=$1
else
    INSTALLDIR=/usr/local
fi

for binfile in addr2line ar as c++filt gprof ld nm objcopy objdump ranlib \
			 readelf size strings strip
do
    rm -v $INSTALLDIR/bin/$binfile
    rm -v $INSTALLDIR/man/man1/$binfile.1
done
rm -v $INSTALLDIR/man/man1/bin2hex.1
rm -v $INSTALLDIR/man/man1/dlltool.1
rm -v $INSTALLDIR/man/man1/nlmconv.1
rm -v $INSTALLDIR/man/man1/windres.1
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/bin
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/man/man1
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/man

for incfile in ansidecl bfd bfdlink dis-asm symcat
do
    rm -v $INSTALLDIR/include/$incfile.h
done
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/include

for infotopic in as bfd binutils configure gprof ld standards
do
    for infofile in $INSTALLDIR/info/$infotopic.info*
    do
	rm -v $infofile
    done
done
rm -v $INSTALLDIR/info/dir
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/info

for libfile in libbfd.a libbfd.la libiberty.a libopcodes.a libopcodes.la
do
    rm -v $INSTALLDIR/lib/$libfile
done
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/lib

for lang in da de es fr id ja pt_BR ro sv tr zh_CN
do
    DIR=$INSTALLDIR/share/locale/$lang
    for util in bfd binutils gas ld opcodes
    do
	FILE=$DIR/LC_MESSAGES/$util.mo
	if [ -e $FILE ]
	then
	    rm -v $FILE
	fi
    done
    rmdir -v --ignore-fail-on-non-empty $DIR/LC_MESSAGES
    rmdir -v --ignore-fail-on-non-empty $DIR
done
rmdir -v --ignore-fail-on-non-empty $DIR
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/share/locale
rmdir -v --ignore-fail-on-non-empty $INSTALLDIR/share
