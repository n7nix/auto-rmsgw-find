#!/bin/bash
#
# gps_gridsquare.sh
#

# ===== function dbgecho
function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function is_gps_sentence
# Check if gpsd is returning sentences
# Returns gps sentence count, should be 3
function is_gps_sentence() {
    dbgecho "is_gps_sentence"
    retval=$(gpspipe -r -n 3 -x 2 | grep -ic "class")
    return $retval
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

# ===== main

# Initialize grid square variable
# Will be set either from command line or gps
gridsquare=

# Verify gpsd is running
journalctl --no-pager -u gpsd | tail -n 1 | grep -i error
retcode="$?"
if [ "$retcode" -eq 0 ] ; then
    echo "gpsd daemon is not running without errors."
    exit 1
fi

# Verify gpsd is returning sentences
is_gps_sentence
result=$?
dbgecho "Verify gpsd is returning sentences ret: $result"

if (( result > 0 )) ; then
    gps_running=true

    # echo "nmea sentence"
    get_lat_lon_gpsdsentence
    if [ "$?" -ne 0 ] ; then
        echo "Error getting gpsd sentence"
        exit 1
    fi
fi

echo "We are here: lat: $lat$latdir, lon: $lon$londir"

BINDIR="./"
if [ ! -e "$(pwd)/latlon2grid" ] ; then
    BINDIR="$HOME/bin"
fi

# Assume latlon2grid installed to ~/bin
# Arguments need to be in decimal degrees ie:
#  48.48447 -122.901885
gridsquare=$($BINDIR/latlon2grid $lat $lon)

# Should qualify gridsqare AANNAA
sizegridsqstr=${#gridsquare}

if (( sizegridsqstr != 6 )) ; then
    echo
    echo "INVALID grid square: $gridsquare, length = $sizegridsqstr"
    exit 1
fi

echo "grid square: $gridsquare"
