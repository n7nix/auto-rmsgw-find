#!/bin/bash
#
#  mheard-mail.sh
#
#  Use mheard to create a list of local -10 winlink RMS Gateways
#  Prompt for a call sign from that list and call wl2kax25
#
# This script written at request of Ed Bloom, KD9FRQ June 3, 2020
DEBUG=

PORTNAME="udr1"
COLUMNS=5
scriptname="`basename $0`"

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function get_callsign
# Prompt for a call sign from mheard generated displayed list

function get_callsign() {

    # prompt for a call sign
    read -t 1 -n 10000 discard
    echo -n "Enter gateway call sign, followed by [enter]"
    # -p display PROMPT without a trailing new line
    # -e readline is used to obtain the line
    read -ep ": " CALLSIGN

    sizecallstr=${#CALLSIGN}

    # Vet call sign string size
    if (( sizecallstr > 6 )) || ((sizecallstr < 3 )) ; then
        echo "Invalid call sign: $CALLSIGN, length = $sizecallstr"
        return 1
    fi

    # Convert callsign to upper case
    CALLSIGN=$(echo "$CALLSIGN" | tr '[a-z]' '[A-Z]')

    # Need to verify CALLSIGN is actually in list before calling wl2kax25
    grep -qi "${CALLSIGN}-10"  <<< $heardlist
    retcode="$?"

#    echo "Verify call sign: $CALLSIGN $retcode"

    return $retcode
}

# ===== function usage

function usage() {
    echo "Usage: $scriptname [-d][-h]" >&2
    echo "   -d        set debug flag"
    echo "   -h        display this message"
    echo
}

# ===== main

while [[ $# -gt 0 ]] ; do
APP_ARG="$1"

case $APP_ARG in

   -d|--debug)
      DEBUG=1
      echo "Debug mode on"
   ;;
   -h|--help|-?)
      usage
      exit 0
   ;;
   *)
       echo "Unrecognized command line argument: $APP_ARG"
       usage
       exit 0
   ;;

esac

shift # past argument
done

# Get mheard list
heardlist=$(mheard | grep "$PORTNAME" | tr -s '[[:space:]] ')

# Count number of gateways
num_gateways=$(grep -c "\-10" <<< $heardlist)
echo "Found $num_gateways RMS Gateway call signs"
echo
if [ "$num_gateways" -eq 0 ] ; then
    exit 0
fi

printline=
linecnt=0
while IFS= read -r line ; do

    # echo "DEBUG: line: $line"
    # Check if this entry was an RMS Gateway
    portline=$( grep "\-10" <<< $line)
    if [ $? -eq 0 ] ; then
        portline=$(echo "$line" | cut -f1 -d '-')

        (( linecnt++ ))
        if [ $linecnt -eq 1 ] ; then
            printline="$portline"
        else
            printline="$(printf "%s\t%s" "$printline" "$portline")"
        fi
        # echo "line count: $linecnt, print: $printline, port: $portline"
    fi

    if [ "$linecnt" -ge "$COLUMNS" ] ; then
         printf "%s\n" "$printline"
         linecnt=0
         printline=
    fi

done <<< $heardlist

# Display last line if appropriate
if [ ! -z "$printline" ] ; then
     printf "%s\n" "$printline"
fi

# prompt for a callsign
while ! get_callsign ; do
    echo "Call sign not in list, try again"
done

echo "Using this call sign: $CALLSIGN"

# If debug turned ON, do not use radio
if [ -z "$DEBUG" ] ; then
    wl2kax25 -V -a $PORTNAME -c ${CALLSIGN}-10
    retcode="$?"
    if [ "$retcode" -eq 0 ] ; then
        echo "SUCCESSFUL connection to ${CALLSIGN}-10"
    else
        echo "FAILED connection to ${CALLSIGN}-10"
    fi
else
    echo
    echo "wl2kax25 NOT called because debug turned on"
fi
