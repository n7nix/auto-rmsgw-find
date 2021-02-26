#!/bin/bash
#
# Create a file for a connection report
# that will be uploaded to a BBS

scriptname="`basename $0`"

TMPDIR="$HOME/tmp"
REPORTFILE="$TMPDIR/connect.report"
LOGFILE="$TMPDIR/gateway.log"

prog_name="show_log.sh"
type -P $prog_name &>/dev/null
if [ $? -ne 0 ] ; then
    echo "$scriptname: $(tput setaf 1) Required program: $prog_name not found$(tput sgr0)"
    exit 1
fi

if [[ ! -s "$LOGFILE" ]] ; then
    echo "$scriptname: $(tput setaf 1) Required log file: $LOGFILE not found$(tput sgr0)"
    exit 1
fi

echo "Building weekly report"
show_log.sh -p week > $REPORTFILE

echo >> $REPORTFILE

echo "Building monthly report"
show_log.sh -p month >> $REPORTFILE

echo "Report file is $(cat $REPORTFILE | wc -l) lines."