#!/bin/sh
# Note: Microchip requires a credential to download the GPL source code(!)
#       As a workaround, save a gzip'ed tarball in the current directory such as
#       http://ww1.microchip.com/downloads/Secure/en/DeviceDoc/xc16-v1.50.src.zip

rm -rf v*.src/
unzip xc16-v*.src.zip
cd v*.src/
./src_build.sh

