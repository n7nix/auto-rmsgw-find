#!/bin/bash
#
# gps_gridsquare.sh
#
# Uncomment this statement for debug echos
#DEBUG=1

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

    dbgecho "lat: $lat$latdir, lon: $lon$londir"
}

# ===== function get_latlon
function get_latlon() {

    # Verify gpsd is running
    journalctl --no-pager -u gpsd | tail -n 1 | grep -i error
    retcode="$?"
    if [ "$retcode" -eq 0 ] ; then
        echo "gpsd daemon is not running without errors."
        return 1
    fi

    # Verify gpsd is returning sentences
    is_gps_sentence
    result=$?
    dbgecho "Verify gpsd is returning sentences ret: $result"

    if (( result > 0 )) ; then
        gps_running=true

        get_lat_lon_gpsdsentence
        if [ "$?" -ne 0 ] ; then
            echo "Error getting gpsd sentence"
            return 1
        fi
    fi
    return 0
}

# ===== main

# Initialize grid square variable
# Will be set either from command line or gps
gridsquare=

get_latlon
if [ "$?" -eq 0 ] ; then
    echo "gps lat/lon is OK!, lat: $lat$latdir, lon: $lon$londir"
else
    echo "failed to get lat lon from gps."
    exit
fi

BINDIR="./"
if [ ! -e "$(pwd)/latlon2grid" ] ; then
    BINDIR="$HOME/bin"
    if [ ! -e "$BINDIR/latlon2grid" ] ; then
        echo "Can NOT locate latlon2grid program."
        exit
    fi
fi

# lat/lon arguments to latlon2grid need to be in decimal degrees ie:
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
