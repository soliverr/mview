#! /bin/bash

./build.sh

package=`cat ./configure.ac | sed -ne 's/^AC_INIT(\([^,]*\)\s*,.*/\1/gp'`

#
#
# Set up to emulate system installation process
#

echo
echo Test installation ...
echo

destdir=inst

rm -rf $destdir 2>&-

./configure --with-spooldir=/var/log/oracle/oradba

make install DESTDIR=$destdir || exit 1

