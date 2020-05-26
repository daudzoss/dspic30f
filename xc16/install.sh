#!/bin/sh
# $0            installs in default directory (/usr/local/bin)
# $0 $HOME      installs in home directory (~/bin)
ORIG=v*.src/install/bin
if [ $# -gt 0 ]
then
    DEST=$1/bin
else
    DEST=/usr/local/bin
fi

if [ -e $DEST ]
then
    echo $DEST exists, installing
else
    mkdir $DEST
fi
cp -v $ORIG/c30_device.info $DEST
cp -v $ORIG/bin/elf-* $DEST


