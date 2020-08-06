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
bListOnly=false

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function get_mheard_list
# Get mheard list with -10 ssids

function get_mheard_list() {

    heardlist=$(mheard | grep "$PORTNAME" | tr -s '[[:space:]]')

    # If these two counts are not equal this script will NOT work
    chk_all_gateways=$(mheard | grep -c "$PORTNAME")
    verify_all_gateways=$(grep $PORTNAME <<< $heardlist | wc -l)

    if [ "$chk_all_gateways" -ne  "$verify_all_gateways" ] ; then
        echo "Version check: check all cnt: $chk_all_gateways, verify: $verify_all_gateways"
        bash_ver=$(bash --version | grep -m 1 -i version | cut -f4 -d' ')
        echo "This script needs a newer version of bash. Currently running: $bash_ver"
        exit 0
    fi

    # Count number of gateways
    # Assume that an SSID of 10 means it is an RMS Gateway
    num_gateways=$(grep -c "\-10" <<< $heardlist)
    echo "Found $num_gateways RMS Gateway call signs on port $PORTNAME"
    echo
    if [ "$num_gateways" -eq 0 ] ; then
        exit 0
    fi

    # Loop through list of RMS Gateways and format output to be $COLUMNS wide
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
}

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
    echo "Usage: $scriptname [-a <portname>][-d][-l][-h]" >&2
    echo "   -a <portname>   | --portname   Specify ax.25 port name ie. udr0 or udr1"
    echo "   -d        set debug flag"
    echo "   -l        list all heard RMS Gateways on a port"
    echo "   -h        display this message"
    echo
}

# ===== main

while [[ $# -gt 0 ]] ; do
APP_ARG="$1"

case $APP_ARG in
    -a|--portname)   # set ax25 port
        PORTNAME="$2"
        shift # past argument
        if [ "$PORTNAME" != "udr0" ] && [ "$PORTNAME" != "udr1" ] ; then
            echo "  Invalid port name: $PORTNAME"
            echo "  Must be either udr0 or udr1"
            exit 1
        fi
    ;;
   -l|--list)
        bListOnly=true
   ;;
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

get_mheard_list
if $bListOnly ; then
    exit
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
