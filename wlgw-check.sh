#!/bin/bash
#
# Get a list of local RMS Gateways & test a connection
# This script was developed for a Kenwood TM-V71a
#
# Needs these file:
#  - csv programming file for radio
#  - generated RMS Gateway list from Winlink Web Services
#
# Uncomment this statement for debug echos
DEBUG=1
b_dev=true
scriptname="`basename $0`"
TMPDIR="$HOME/tmp"
GATEWAY_LOGFILE="$TMPDIR/gateway.log"

# Serial device that PG-5G cable is plugged into
SERIAL_DEVICE="/dev/ttyUSB0"
# Choose which radio left (VFOA) or right (VFOB) is DATA Radio
DATBND="VFOA"

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
        echo "$scriptname: Program: $program_name not found in path ... will exit"
        retcode=1
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

# ===== function debug_check
function debug_check() {

    strarg="$1"
    freq=$(rigctl -r /dev/ttyUSB0  -m234 f)
    xcurr_freq=$(rigctl -r /dev/ttyUSB0  -m234 --vfo f $DATBND)
    echo "debug_check: $strarg: Current frequency: VFOA: $xcurr_freq, freq: $freq"
}

# ===== function set_vfo_mode
function set_vfo_mode() {
#    dbgecho "Set vfo mode to $DATBND"
    rigctl -r /dev/ttyUSB0  -m234  V $DATBND
}

# ===== function set_memchan_mode
function set_memchan_mode() {
    dbgecho "Set vfo mode to MEM"
    rigctl -r /dev/ttyUSB0  -m234  V MEM
}

# ===== function get_ext_data_band

# Could return any of the following: (see tmd710.c)
#   TMD710_EXT_DATA_BAND_A 0
#   TMD710_EXT_DATA_BAND_B 1
#   TMD710_EXT_DATA_BAND_TXA_RXB 2
#   TMD710_EXT_DATA_BAND_TXB_RXA 3

function get_ext_data_band() {
    ret_code=$(rigctl -r /dev/ttyUSB0  -m234  l EXTDATABAND)
    return $ret_code
}

# ===== function find_mem_chan
# Sets 'radio_index'  memory channel index number for a given frequency
# Arg1: frequency

function find_mem_chan() {

    set_freq="$1"
    freq_name="unknown"
    retcode=1

    while read freqlist ; do
        chan_status="Err"
        # Get frequency  from csv programming file
        listfreq=$(cut -d',' -f3 <<< $freqlist)

        # Get rid of decimal
        lstf1=${listfreq/./}
        # Pad with trailing spaces to 9 characters
        lstf1=$(printf "%-0.9s" "${lstf1}000000000")
        # Compare frequency in csv file to frequency requested
        if [ "$set_freq" == "$lstf1" ] ; then
            # Get Radio index from csv file
            radio_index=$(cut -d',' -f1 <<< $freqlist)
            # Get Alpha-numeric name from csv file
            freq_name=$(cut -d',' -f2 <<< $freqlist)

            # Verify with radio
            check_radio_mem $radio_index
            # Get rid of decimal in frequency
            radfreq=${chan_freq/./}
            # Pad with trailing spaces to 9 characters
            radfreq=$(printf "%-0.9s" "${radfreq}000000000")
            # Compare frequency from radio memory channel to required set frequency
            if [ "$radfreq" == "$set_freq" ] ; then
                chan_status="OK"
                retcode=0
            else
                chan_status="Err"
                radio_index="   "
            fi

#            echo "$freq_name: $listfreq ($lstf1) ($wl_freq) "
            # break on match of csv file & required set frequency
            break;
        fi

    done < $DIGI_FREQ_LIST
    return $retcode
}

# ===== function get_mem

# Return memory channel index that radio is using
# Need to set vfo to DATBND usually VFOA or VFOB

function get_mem() {

    mem_chan=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID e)
    grep -i "error" <<< $mem_chan > /dev/null 2>&1
    retcode=$?
    if [ $retcode -eq 0 ] ; then
        echo "In VFO mode"
    else
        echo "In Mem channel mode"
    fi
    return $ret_code
}

# ===== function get_chan

# Arg 1: memory channel number integer
# Return information programmed into memory channel
function get_chan() {

#    dbgecho "get_chan: arg: $1"
    chan_info=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID  h $1)
    ret_code=$?
#    echo "Ret code=$ret_code"
}

# ===== function get_vfo_freq

# Return frequency that radio is using on the DATA BAND
function get_vfo_freq() {

    freq=$(rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID --vfo f $DATBND)
    ret_code=$?
    dbgecho "get_vfo_freq: Ret code=$ret_code"
}

# ===== function check_radio_band
function check_radio_band() {

vfo_mode=$(rigctl -r /dev/ttyUSB0 -m234 v)
if ["$vfo_mode" -ne "MEM" ] ; then
    rigctl -r /dev/ttyUSB0 -m234 V MEM
fi
curr_freq=$(rigctl -r /dev/ttyUSB0 -m234 f)

b_2MBand=false
if (( "$curr_freq" >= 144000000 )) && (( "$curr_freq" < 148000000 )) ; then
    b_2MBand=true
fi

# Set frequency to 440125000
rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E 131

rigctl -r /dev/ttyUSB0 -m234 F 440125000

}
# ===== function check_radio_mem
# arg1: radio memory index

function check_radio_mem() {

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

#===== function check_gateway
# arg1: readio memory index
# Set 2M frequencies with VFO & 440 frequencies with memory index

function check_gateway() {
    gw_freq="$1"
    gw_call="$2"
    # Set 'failed' return code
    connect_status=1

    dbgecho "Connect to: $gw_call with radio using freq $gw_freq"
    debug_check "start"

    if (( gw_freq >= 144000000 )) && (( gw_freq < 148000000 )) ; then
        b_2MBand=true
        vfo_mode=$(rigctl -r /dev/ttyUSB0 -m234 v)
        if [ "$vfo_mode" == "MEM" ] ; then
            echo "Set VFO radio band to 2M"
            # Fix this
            rigctl -r /dev/ttyUSB0 -m234 E 35
            debug_check "2M"
        fi
        set_vfo_mode
# This errors out
#       rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID --vfo F $gw_freq $DATBND
        rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID F $gw_freq
    else
        # Set 440 frequencies with a memory index
        set_memchan_mode
        find_mem_chan $gw_freq
        if [ $? -ne 0 ] ; then
            echo "Can not set frequency $gw_freq, not in frequency list."
            return 1
        fi
        rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $radio_index
        debug_check "440"
    fi

    # Verify frequency has been set
    read_freq=$(rigctl -r $SERIAL_DEVICE  -m234 f)

    if [ "$read_freq" -ne "$gw_freq" ] ; then
        echo "Failed to set frequency: $gw_freq for Gateway: $gw_call"
        return $connect_status
    else
        dbgecho "Frequency $read_freq set OK"
    fi

    if [ 1 -eq 1 ] ; then
    # Connect with paclink-unix
     wl2kax25 -c "$gw_call"
     connect_status="$?"
    else
        connect_status=0
    fi
     return $connect_status
}

# ==== main

# Temporary to put programs in local bin dir
dev_setup

# This script uses these programs
PROGRAM_LIST="rigctl gpsd latlon2grid rmslist.sh"
b_exitnow=false
for progname in $PROGRAM_LIST ; do
    in_path "$progname"
    retcode=$?
#    dbgecho "Checking prog: $progname: $retcode"
    if [ "$retcode" -ne 0 ] ; then
        b_exitnow=true
    fi
done

if $b_exitnow ; then
    exit 1
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
    get_location
    echo "We are here: lat: $lat$latdir, lon: $lon$londir"

    # Assume latlon2grid installed to ~/bin
    # Arguments need to be in decimal degrees ie:
    #  48.48447 -122.901885
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
    rmslist.sh 40 $gridsquare -
fi

# Get which Radio is designated digital
data_band=get_ext_data_band

dbgecho "Data is on band $((data_band))"

if (( data_band < 2 )) ; then
    # Convert ascii character to decimal value
    dec_char=$(printf "%d" "'A")
    dec_char=$((dec_char + $((data_band)) ))
    # Convert decimal value back to ascii character
    setbnd=$(printf \\$(printf '%03o' "$dec_char" ))
##    printf "Decimal %d, Character %c\n" "$dec_char" "$setbnd"

    # Make DATA BAND variable either VFOA or VFOB
    DATBND=$(printf "VFO%c" $setbnd)
    echo "Using $DATBND as data radio"

else
    echo "Data channel is $data_band, needs to be either 0 or 1"
    exit 1
fi

# Save some state so radio is in same condition as it started

# Set radio to the DATA radio
# So this command will set which radio in the TM-V71 is default radio
rigctl  -r /dev/ttyUSB0 -m234  --vfo f $DATBND

# Assign some variables

set_memchan_mode
get_mem
save_mem_chan="$mem_chan"
check_radio_mem $mem_chan
# Save current memory channel so can restore on exit
get_vfo_freq
echo "Current Chan: $save_mem_chan, name: $chan_name, chan freq: $chan_freq, Frequency: $freq"

# Make sure radio is in VFO mode
set_vfo_mode

# Iterate each line of the RMS Proximity file

gateway_count=0
connect_count=0

echo "Start: $(date "+%Y %m %d %T %Z"):" | tee -a $GATEWAY_LOGFILE
printf "\nRMS GW\t    Freq\tDist\tName\tIndex  ChanStat  ConnStat Time\n" | tee -a $GATEWAY_LOGFILE

while read fileline ; do

    # collapse all spaces
    fileline=$(echo $fileline | tr -s '[[:space:]]')

    # File some variables from Winlink web service call
    distance=$(cut -d' ' -f3 <<< $fileline)
    wl_freq=$(cut -d' ' -f2 <<< $fileline)
    gw_name=$(cut -d' ' -f1 <<< $fileline)

    # Using a TM-V71a 2M/440 dual band radio
    if (( "$wl_freq" >= 420000000 )) && (( "$wl_freq" < 430000000 )) ; then
        echo "Warning: Frequency violates Line A"
    fi

    freq_name="unknown"
    connect_status="n/a"


# Set frequency
# Confirm frequency is set

    # Qualify stations found
    if [ "$distance" != 0 ] && (
    ( (( "$wl_freq" >= 144000000 )) && (( "$wl_freq" < 148000000 )) ) ||
    ( (( "$wl_freq" >= 420000000 )) && (( "$wl_freq" < 450000000 )) ) ); then
        start_sec=$SECONDS
        chan_status="OK"
        gateway_count=$((gateway_count + 1))

        # Try to connect with RMS Gateway
        check_gateway $wl_freq "$gw_name"
        if [ "$?" -eq 0 ] ; then
            connect_count=$((connect_count + 1))
            connect_status="OK"
        else
            connect_status="TO"
            echo
            echo "Call to wl2kax25 timed out"
            echo
        fi
    else
#        dbgecho "Changing channel status to 'Unqaul' for freq: $wl_freq & gateway $gw_name"
        chan_status="Unqual"
    fi

    printf "%-10s  %s\t%2s\t%s\t%4s   %6s\t%4s\t%d\n"  "$gw_name" "$wl_freq" "$distance" "$freq_name" "$radio_index" "$chan_status" "$connect_status" $((SECONDS-start_sec)) | tee -a $GATEWAY_LOGFILE

    # Debug only: quit or pause after some attempts
    echo "Modulo 5 $((gateway_count/5))"
    if [ 1 -eq 0 ] ; then
        if (( gateway_count > 5 )) ; then
            echo "Sleeping for 5 min"
            sleep 5m
        fi
    fi
done < $RMS_PROXIMITY_FILE_OUT

echo
echo "Finish: echo "$(date "+%Y %m %d %T %Z"): Found $gateway_count RMS Gateways, connected: $connect_count"  | tee -a $GATEWAY_LOGFILE
echo
# Set radio back to previous memory channel
set_memchan_mode
echo "Setting radio back to original memory channel $save_mem_chan"
rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $save_mem_chan
