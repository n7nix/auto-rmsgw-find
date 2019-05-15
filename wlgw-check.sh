#!/bin/bash
#
# Get a list of local RMS Gateways & test a connection
# This script was developed for a Kenwood TM-V71a
#
# Uncomment this statement for debug echos
DEBUG=1
b_dev=true
scriptname="`basename $0`"

# Serial device that PG-5G cable is plugged into
SERIAL_DEVICE="/dev/ttyUSB0"

# Radio model number used by HamLib
RADIO_MODEL_ID=234

DIGI_FREQ_LIST="freqlist_digi.txt"
TMPDIR="$HOME/tmp"
RMS_PROXIMITY_FILE_OUT="$TMPDIR/rmsgwprox.txt"

BAND_2M_LO_LIM=144000000
BAND_2M_HI_LIM=148000000
# 420 to 430 MHz is prohibited north of Line A
BAND_440_LO_LIM=430000000
BAND_440_HI_LIM=450000000

# Initialize grid square variable
# Will be set either from command line or gps
gridsquare=

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function dev_setup
# For development only copy required programs to local bin

function dev_setup() {
    cp -u latlon2grid ~/bin
    cp -u rmslist.sh ~/bin
}


# ===== function usage
function usage() {
   echo "Usage: $scriptname [-g <gridsquare>][-v][-h]" >&2
   echo "   -g <gridsquare> | --gridsquare"
   echo "   -v | --verbose   display verbose messages"
   echo "   -h | --help      display this message"
   echo
}


# ===== function in_path
# arg: program name
function in_path() {

    program_name="$1"
    retcode=0

    type -P $program_name  &>/dev/null
    if [ $? -ne 0 ] ; then
        echo "$scriptname: Program: $program_name not found in path ... exiting"
        exit 1
#    else
#       dbgecho "Program: $program_name found"
    fi
    return $retcode
}

# ===== function get_lat_lon_gpsdsentence
# Uses format: 48.484456667, -122.901871667

function get_lat_lon_gpsdsentence() {
    # Read data from gps device, gpsd sentences
    gpsdata=$(gpspipe -w -n 10 | grep -m 1 lat | jq '.lat, .lon')

#    dbgecho "gpsdata: $gpsdata"

    # Separate lat & lon
    lat=$(echo $gpsdata | cut -d' ' -f1)
    lon=$(echo $gpsdata | cut -d' ' -f2)

#    dbgecho "lat: $lat$latdir, lon: $lon$londir"
}

# ===== function get_lat_lon_nmeasentence
# Only for reference, not used
# uses format: 4829.0674,N,12254.1123,W

function get_lat_lon_nmeasentence() {
    # Read data from gps device, nmea sentences
    gpsdata=$(gpspipe -r -n 15 | grep -m 1 -i gngll)

    # Get geographic gps position status
    ll_valid=$(echo $gpsdata | cut -d',' -f7)
    dbgecho "Status: $ll_valid"
    if [ "$ll_valid" != "A" ] ; then
        echo "GPS data not valid"
        echo "gps data: $gpsdata"
        return 1
    fi

    dbgecho "gpsdata: $gpsdata"

    # Separate lat, lon & position direction
    lat=$(echo $gpsdata | cut -d',' -f2)
    latdir=$(echo $gpsdata | cut -d',' -f3)
    lon=$(echo $gpsdata | cut -d',' -f4)
    londir=$(echo $gpsdata | cut -d',' -f5)

    dbgecho "lat: $lat$latdir, lon: $lon$londir"

    return 0
}

# ===== get_location
function get_location() {

    # Check if program to get lat/lon info is installed.
    prog_name="gpspipe"
    type -P $prog_name &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "$scriptname: Installing gpsd-clients package"
        sudo apt-get install -y -q gpsd-clients
    fi

    # echo "nmea sentence"
    get_lat_lon_gpsdsentence
    if [ "$?" -ne 0 ] ; then
        exit 1
    fi
}

# ===== function get_chan

# Arg 1: memory channel number integer
# Return information programmed into memory channel
function get_chan() {

#    dbgecho "get_chan: arg: $1"
    chan_info=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID h $1)
    ret_code=$?
#    echo "Ret code=$ret_code"
}

# ===== function get_mem

# Return memory channel index that radio is using
function get_mem() {

    dbgecho "get_mem:"
    mem_chan=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID e)
    ret_code=$?
    echo "Ret code=$ret_code"
}


# ===== function get_freq

# Return frequency that radio is using
function get_freq() {

    dbgecho "get_freq:"
    freq=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID f)
    ret_code=$?
    echo "Ret code=$ret_code"
}

# ===== function check_radio
# arg1: radio memory index

function check_radio() {

    in_path rigctl
    mem_chan=$1
#    get_mem

    chan_info=
    get_chan $mem_chan
    if [ $? -ne 0 ] ; then
        echo "Error could not get channel info from radio"
    fi
    #echo -e "Channel info\n$chan_info"

    # Get Alpha-Numeric name of channel in radio
    chan_name=$(grep -i "Name:" <<<"$chan_info" | cut -d ' ' -f4)
    # Remove surrounding quotes
    chan_name=${chan_name%\'}
    chan_name=${chan_name#\'}

    # Get Frequency in MHz of channel number
    # Collapse white space
    chan_freq=$(grep -i "Freq:" <<<"$chan_info" | head -n1 | tr -s '[[:space:]] ' | cut -d ' ' -f2)
}

# ==== main

# Temporary to put programs in local bin dir
dev_setup

# parse command line options
# if there are no args default to out put a message beacon
if [[ $# -eq 0 ]] ; then
   BEACON_TYPE="mesg_beacon"
fi

# if there are any args then parse them
while [[ $# -gt 0 ]] ; do
   key="$1"

   case $key in
      -g|--gridsquare)
	 gridsquare="$2"
         shift # past argumnet
	 ;;
      -v|--verbose)
         verbose=true
         ;;
      -h|--help)
         usage
	 exit 0
	 ;;
      *)
	echo "Unknown option: $key"
	usage
	exit 1
	;;
   esac
shift # past argument or value
done

# Was gridsquare set from command line?
if [ -z "$gridsquare" ] ; then
    # Determine Grid Square location from gps
    in_path "gpsd"
    get_location
    echo "We are here: lat: $lat$latdir, lon: $lon$londir"

    # Assume latlon2grid installed to ~/bin
    # Arguments need to be in decimal degrees ie:
    #  48.48447 -122.901885
    in_path "latlon2grid"
    gridsquare=$(latlon2grid $lat $lon)
fi
dbgecho "Using grid square: $gridsquare"

# For DEV do not refresh the rmslist output file
if ! $b_dev ; then
    echo
    echo "Refreshing RMS List"
    echo
    # Assume rmslist.sh installed to ~/bin
    # rmsglist arg1=distance in miles, arg2=grid square
    in_path "rmslist.sh"
    rmslist.sh 40 $gridsquare -
fi


# Assign some variables
get_mem
check_radio $mem_chan
get_freq
echo "Chan: $mem_chan, name: $chan_name, chan freq: $chan_freq, Frequency: $freq"

# Iterate each line of the RMS Proximity file

printf "\nRMS GW\t    Freq\tDist\tName\tIndex\n"
while read fileline ; do

    # collapse all spaces
    fileline=$(echo $fileline | tr -s '[[:space:]]')

    distance=$(cut -d' ' -f3 <<< $fileline)
    freq=$(cut -d' ' -f2 <<< $fileline)
    gw_name=$(cut -d' ' -f1 <<< $fileline)

    # Using a TM-V71a 2M/440 dual band radio
    if (( "$freq" >= 420000000 )) && (( "$freq" < 430000000 )) ; then
        echo "Warning: Frequency violates Line A"
    fi

    freq_name="Not Found"
    while read freqlist ; do
        listfreq=$(cut -d',' -f3 <<< $freqlist)

        # Get rid of decimal
        lstf1=${listfreq/./}
        # Pad with trailing spaces to 9 characters
        lstf1=$(printf "%-0.9s" "${lstf1}000000000")
        # Compare frequency in csv file to frequency from Winlink Proximity file
        if [ "$freq" == "$lstf1" ] ; then
            # Get Radio index from csv file
            radio_index=$(cut -d',' -f1 <<< $freqlist)
            # Get Alpha-numeric name from csv file
            freq_name=$(cut -d',' -f2 <<< $freqlist)

            # Verify with radio
            check_radio $radio_index
            # Get rid of decimal in frequency
            radfreq=${chan_freq/./}
            # Pad with trailing spaces to 9 characters
            radfreq=$(printf "%-0.9s" "${radfreq}000000000")
            if [ "$radfreq" == "$freq" ] ; then
                status_str="OK"
            else
                status_str="Err"
            fi

#            echo "$freq_name: $listfreq ($lstf1) ($freq) "
        fi

    done < $DIGI_FREQ_LIST

    # Qualify stations found
    if [ "$distance" != 0 ] && (
    ( (( "$freq" >= 144000000 )) && (( "$freq" < 148000000 )) ) ||
    ( (( "$freq" >= 420000000 )) && (( "$freq" < 450000000 )) ) ); then
        printf "%-10s  %s\t%2s\t%s\t%3s  %s\n"  "$gw_name" "$freq" "$distance" "$freq_name" "$radio_index" "$status_str"
    fi

done < $RMS_PROXIMITY_FILE_OUT
