#!/bin/bash
#
#  mheard-mail.sh
#
#  Use mheard to create a list of local -10 winlink RMS Gateways
#  Prompt for a call sign from that list and call wl2kax25
#
# This script written at request of  Ed Bloom, KD9FRQ June 3, 2020

PORTNAME="udr0"

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function get_callsign

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


# ===== main

# Get mheard list
heardlist=$(mheard | grep "$PORTNAME" | tr -s '[[:space:]] ')

echo "Found $(grep -c "\-10" <<< $heardlist) RMS Gateway call signs"
echo
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

    if [ "$linecnt" -ge 5 ] ; then
         printf "%s\n" "$printline"
         linecnt=0
         printline=
    fi

done <<< $heardlist

# Display last line if appropriate
if [ ! -z $printline ] ; then
     printf "%s\n" "$printline"
fi

# prompt for a callsign
while ! get_callsign ; do
    echo "Call sign not in list, try again"
done

echo "Using this call sign: $CALLSIGN"

wl2kax25 -V -a $PORTNAME -c ${CALLSIGN}-10
retcode="$?"
if [ "$retcode" -eq 0 ] ; then
    echo "SUCCESSFUL connection to ${CALLSIGN}-10"
else
    echo "FAILED connection to ${CALLSIGN}-10"
fi
