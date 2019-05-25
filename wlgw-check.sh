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
# DEBUG=1

# Used by rmslist.sh to set gateway distance from specified grid square
GWDIST=35
# Will refresh RMS list if true
b_refresh_gwlist=true

# Set to true for activating paclink-unix
# Set to false to test rig control, with no connect
# Set by -t command line arg
b_test_connect=true
b_crontab=false

scriptname="`basename $0`"
TMPDIR="$HOME/tmp"
GATEWAY_LOGFILE="$TMPDIR/gateway.log"
BINDIR="$HOME/bin"
LOCAL_BINDIR="/usr/local/bin"

RIGCTL="$LOCAL_BINDIR/rigctl"
WL2KAX25="$LOCAL_BINDIR/wl2kax25"

# Serial device that Kenwood PG-5G cable is plugged into
SERIAL_DEVICE="/dev/ttyUSB0"
# Choose which radio left (VFOA) or right (VFOB) is DATA Radio
DATBND="VFOA"

# Radio model number used by HamLib
# Radio Model Number 234 specifies a Kenwood D710 which nearly works for a
#  Kenwood TM-V71a
RADIO_MODEL_ID=234

DIGI_FREQ_LIST="$BINDIR/freqlist_digi.txt"
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

    if [ ! -e "$(pwd)/gridsq/latlon2grid" ] ; then
        pushd gridsq > /dev/null
        make
        popd > /dev/null
    fi
    cp -u gridsq/latlon2grid ~/bin
#    cp -u rmslist.sh ~/bin
}

# ===== function usage

function usage() {
   echo "Usage: $scriptname [-g <gridsquare>][-v][-h]" >&2
   echo " If no gps is found, gridsquare must be entered."
   echo "   -g <gridsquare> | --gridsquare"
   echo "   -d | --debug      display debug messages"
   echo "   -r | --no_refresh use existing RMS Gateway list"
   echo "   -t | --test       test rig ctrl with NO connect"
   echo "   -h | --help       display this message"
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
# Get lat/lon location from gps

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

    if [ ! -z "$DEBUG" ] ; then
        strarg="$1"
        freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID f)
        xcurr_freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID --vfo f $DATBND)
        echo "debug_check: $strarg: Current frequency: VFOA: $xcurr_freq, freq: $freq"
    fi
}

# ===== function set_vfo_freq
# Arg1: frequency to set

function set_vfo_freq() {

    vfo_freq="$1"
    ret_code=1
    to_secs=$SECONDS
    to_time=0
    b_found_error=false

    while [ $ret_code -gt 0 ] && [ $((SECONDS-to_secs)) -lt 5 ] ; do

        # This errors out
        # rigctl -r $SERIAL_DEVICE -m $RADIO_MODEL_ID --vfo F $gw_freq $DATBND

        set_freq_ret=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID F $gw_freq)
        returncode=$?
        if [ ! -z "$set_freq_ret" ] ; then
            ret_code=1
            vfomode_read=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID v)
            errorsetfreq=$set_freq_ret
            errorcode=$returncode
            to_time=$((SECONDS-to_secs))
            b_found_error=true

        else
            ret_code=0
        fi
     done

    if $b_found_error && [ $to_time -gt 3 ] ; then
        vfomode_read=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID v)
        echo "RIG CTRL ERROR[$errorcode]: set freq: $vfo_freq, TOut: $to_time, VFO mode=$vfomode_read, error:$errorsetfreq" | tee -a $GATEWAY_LOGFILE
    fi

    return $ret_code
}

# ===== function set_vfo_mode

function set_vfo_mode() {

    ret_code=1
    to_secs=$SECONDS
    to_time=0
    b_found_error=false

    while [ $ret_code -gt 0 ] && [ $((SECONDS-to_secs)) -lt 5 ] ; do

        vfomode=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID  V $DATBND)
        returncode=$?
        if [ ! -z "$vfomode" ] ; then
            ret_code=1
            vfomode_read=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID v)
            errorvfomode=$vfomode
            errorcode=$returncode
            to_time=$((SECONDS-to_secs))
            b_found_error=true

        else
            ret_code=0
        fi
    done

    if $b_found_error && [ $to_time -gt 3 ] ; then
        echo "RIG CTRL ERROR[$errorcode]: set vfo mode: TOut: $to_time, VFO mode=$vfomode_read, error:$errorvfomode" | tee -a $GATEWAY_LOGFILE
    fi

    return $ret_code
}

# ===== function set_memchan_mode

function set_memchan_mode() {
    dbgecho "Set vfo mode to MEM"
    memchanmode=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID  V MEM)
    if [ ! -z "$memchanmode" ] ; then
        vfomode_read=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID v)
        echo "RIG CTRL ERROR: MEM mode=$vfomode_read, error:$memchanmode" | tee -a $GATEWAY_LOGFILE
        # DEBUG temporary
        exit 1
    fi
}

# ===== function set_memchan_index

# Arg1: index of memory channel to set
function set_memchan_index() {

    mem_index=$1
    ret_code=1
    to_secs=$SECONDS
    to_time=0
    b_found_error=false

    while [ $ret_code -gt 0 ] && [ $((SECONDS-to_secs)) -lt 5 ] ; do

        set_mem_ret=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $mem_index)
        returncode=$?
        # if any string returned then usually an error
        if [ ! -z "$set_mem_ret" ] ; then
            grep -i "error = Feature"  <<< "$set_mem_ret" > /dev/null 2>&1
            if [ $? -eq 0 ] ; then
                ret_code=1
                errorcode=$returncode
                err_mem_ret=$set_mem_ret
                to_time=$((SECONDS-to_secs))
                b_found_error=true
            fi
        else
            ret_code=0
        fi
    done

    if $b_found_error  && [ $to_time -gt 3 ] ; then
        echo "RIG CTRL ERROR[$errorcode]: set memory index: $mem_index, TOut: $to_time, error:$err_mem_ret"  | tee -a $GATEWAY_LOGFILE
    fi

    return $ret_code
}

# ===== function get_ext_data_band
#
# Could return any of the following: (see tmd710.c)
#   TMD710_EXT_DATA_BAND_A 0
#   TMD710_EXT_DATA_BAND_B 1
#   TMD710_EXT_DATA_BAND_TXA_RXB 2
#   TMD710_EXT_DATA_BAND_TXB_RXA 3

function get_ext_data_band() {
    ret_code=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID  l EXTDATABAND)
    return $ret_code
}

# ===== function find_mem_chan
# Sets 'radio_index', memory channel index number for a given frequency
# Arg1: frequency in Hz

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
#
# Return memory channel index that radio is using
# Need to set vfo to DATBND usually VFOA or VFOB

function get_mem() {

    mem_chan=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID e)
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
#
# Arg 1: memory channel number integer
# Return information programmed into memory channel

function get_chan() {

#    dbgecho "get_chan: arg: $1"
    chan_info=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID  h $1)
    ret_code=$?
#    echo "Ret code=$ret_code"
}

# ===== function get_vfo_freq
#
# Return frequency that radio is using on the DATA BAND

function get_vfo_freq() {

    freq=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID --vfo f $DATBND)
    ret_code=$?
    if [ $ret_code -ne 0 ] ; then
        echo "get_vfo_freq: ERROR: ret code=$ret_code, ret string: $freq"
    fi
}

# ===== function check_radio_band

function check_radio_band() {

vfo_mode=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID v)
if ["$vfo_mode" -ne "MEM" ] ; then
    $RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID V MEM
fi
curr_freq=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID f)

b_2MBand=false
if (( "$curr_freq" >= 144000000 )) && (( "$curr_freq" < 148000000 )) ; then
    b_2MBand=true
fi

# Set frequency to 440125000
$RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E 131

$RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID F 440125000

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
# arg1: radio memory index
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
        vfo_mode=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID v)
        if [ "$vfo_mode" == "MEM" ] ; then
            echo "  Set VFO radio band to 2M"
            # Set memory channel index
            set_memchan_index 35

            debug_check "Change to 2M band"
            # Now set VFO mode
            set_vfo_mode
        fi

        # Set Gateway frequency
        set_vfo_freq $gw_freq

        # The following just sets freq_name & radio index for log file
        find_mem_chan $gw_freq
    else
        # Set 440 frequencies with a memory index
        set_memchan_mode
        find_mem_chan $gw_freq
        if [ $? -ne 0 ] ; then
            echo "Can not set frequency $gw_freq, not in frequency list."
            return 1
        fi
        $RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $radio_index
        debug_check "440"
    fi

    # Verify frequency has been set
    read_freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID f)

    if [ "$read_freq" -ne "$gw_freq" ] ; then
        echo "Failed to set frequency: $gw_freq for Gateway: $gw_call, read freq: $read_freq" | tee -a $GATEWAY_LOGFILE
        return $connect_status
    else
        dbgecho "Frequency $read_freq set OK"
    fi

    if $b_test_connect ; then
        # Connect with paclink-unix
        dbgecho "Waiting for wl2kax25 to return ..."
        $WL2KAX25 -c "$gw_call"
        connect_status="$?"
    else
        connect_status=0
    fi
     return $connect_status
}

#
# ==== main
#

# Determine if script is running from a cron job
#PID test
# Get parent pid of parent
PPPID=$(ps h -o ppid= $PPID)
# get name of the command
P_COMMAND=$(ps h -o %c $PPPID)

dbgecho "PID test: cmd: $P_COMMAND"
# Test name against cron
if [ "$P_COMMAND" == "cron" ]; then
    b_crontab=true
fi

# Temporary to put programs in local bin dir
# dev_setup

if ! $b_crontab ; then
    # This script uses these programs
    # It also uses gpsd but only if it is installed
    PROGRAM_LIST="rigctl latlon2grid rmslist.sh"
    b_exitnow=false
    for progname in $PROGRAM_LIST ; do
        in_path "$progname"
        retcode=$?
#       dbgecho "Checking prog: $progname: $retcode"
        if [ "$retcode" -ne 0 ] ; then
            b_exitnow=true
        fi
    done

    if $b_exitnow ; then
        exit 1
    fi
fi

# if there are any args then parse them
while [[ $# -gt 0 ]] ; do
   key="$1"

   case $key in
      -g|--gridsquare)
	 gridsquare="$2"
         shift # past argumnet
	 ;;
      -d|--debug)
         DEBUG=1
         echo "Set debug flag"
         ;;
      -r|--norefresh)
         b_refresh_gwlist=false
         echo "Use the existing RMS Gateway list"
         ;;
      -t|--test)
         b_test_connect=false
         echo "Set test rig control only flag"
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

# Determine if gpsd is installed
prog_name="gpsd"
type -P $prog_name  >/dev/null 2>&1
if [ "$?"  -ne 0 ]; then
    # gpsd not installed
    # Was gridsquare set from command line?
    if [ -z "$gridsquare" ] ; then
        # No gpsd & not specified on command line
        # Prompt for gridsquare

        read -t 1 -n 10000 discard
        echo -n "Enter grid square eg; CN88nl, followed by [enter]"
        # -p display PROMPT without a trailing new line
        # -e readline is used to obtain the line
        read -ep ": " gridsquare
    fi
else
    dbgecho "Found $prog_name"
    # Was gridsquare set from command line?
    if [ -z "$gridsquare" ] ; then
        # Determine Grid Square location from gps
        get_location
        echo "We are here: lat: $lat$latdir, lon: $lon$londir"

        # Assume latlon2grid installed to ~/bin
        # Arguments need to be in decimal degrees ie:
        #  48.48447 -122.901885
        gridsquare=$($BINDIR/latlon2grid $lat $lon)
    fi
fi

# Should qualify gridsqare AANNAA
sizegridsqstr=${#gridsquare}

if (( sizegridsqstr != 6 )) ; then
    echo
    echo "INVALID grid square: $gridsquare, length = $sizegridsqstr"
    exit 1
fi

dbgecho "Using grid square: $gridsquare"

# For DEV do not refresh the rmslist output file
if $b_refresh_gwlist ; then
    echo
    echo "Refreshing RMS List"
    echo
    # Save recent RMS Gateway list
    cp $TMPDIR/rmsgwprot.txt $TMPDIR/rmsgwprot.bak
    # Assume rmslist.sh installed to ~/bin
    # rmsglist arg1=distance in miles, arg2=grid square, arg3=mute output
    # Create file in $HOME/tmp/rmsgwprox.txt

    $BINDIR/rmslist.sh $GWDIST $gridsquare S

    diff $TMPDIR/rmsgwprox.txt $TMPDIR/rmsgwprox.bak > /dev/null 2>&1
    if [ "$?" -ne 0 ] ; then
        echo "RMS GW proximity file has changed"
        linecnt_new=$(wc -l $TMPDIR/rmsgwprox.txt | cut -d ' ' -f1)
        linecnt_old=$(wc -l $TMPDIR/rmsgwprox.bak | cut -d ' ' -f1)
        echo "New proximity file has $linecnt_new entries, old file has $linecnt_old"
    fi
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
# Returns which frequency VFOx is set to

datbnd_freq=$($RIGCTL  -r $SERIAL_DEVICE -m $RADIO_MODEL_ID  --vfo f $DATBND)

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

total_gw_count=0
gateway_count=0
connect_count=0
start_sec=$SECONDS

echo | tee -a $GATEWAY_LOGFILE
echo "Start: $(date "+%Y %m %d %T %Z"): grid: $gridsquare, debug: $DEBUG, GW list refresh: $b_refresh_gwlist, connect: $b_test_connect, cron: $b_crontab" | tee -a $GATEWAY_LOGFILE

# Table header is 2 lines
printf  "\n\t\t\t\t\t\tChan\tConn\n" | tee -a $GATEWAY_LOGFILE
printf "RMS GW\t    Freq\tDist\tName\tIndex\tStat\tStat\tTime\n" | tee -a $GATEWAY_LOGFILE

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

    next_sec=$SECONDS
    freq_name="unknown"
    connect_status="n/a"
    total_gw_count=$((total_gw_count + 1))
# Set frequency
# Confirm frequency is set

    # Qualify stations found
    if [ "$distance" != 0 ] && (
    ( (( "$wl_freq" >= 144000000 )) && (( "$wl_freq" < 148000000 )) ) ||
    ( (( "$wl_freq" >= 420000000 )) && (( "$wl_freq" < 450000000 )) ) ); then

        chan_status="OK"
        gateway_count=$((gateway_count + 1))

        # Try to connect with RMS Gateway
        check_gateway $wl_freq "$gw_name"
        if [ "$?" -eq 0 ] ; then
            connect_count=$((connect_count + 1))
            connect_status="OK"
        else
            connect_status="to"
            echo
            echo "Call to wl2kax25 timed out"
            echo
        fi
    else
#        dbgecho "Changing channel status to 'Unqaul' for freq: $wl_freq & gateway $gw_name"
        find_mem_chan $wl_freq
        chan_status="Unqual"
    fi

    # Variables set from csv programming file
    # freq_name, radio_index
    printf "%-10s  %s\t%2s\t%s\t%4s   %6s\t%4s\t  %d\n"  "$gw_name" "$wl_freq" "$distance" "$freq_name" "$radio_index" "$chan_status" "$connect_status" $((SECONDS-next_sec)) | tee -a $GATEWAY_LOGFILE

    # Debug only: quit or pause after some attempts
    if [ $((gateway_count % 5)) -eq 0 ] && [ $total_gw_count -gt 5 ] ; then
        echo "  Pause for a bit, gateway count: $gateway_count, modulo 5 $(( gateway_count % 5 ))"
        sleep 2
    fi

    if (( $total_gw_count > 50 )) ; then
        echo "DEBUG: exit"
        break;
    else
        dbgecho "gateway_count: $total_gw_count"
    fi

done < $RMS_PROXIMITY_FILE_OUT

# Get elapsed time in seconds
et=$((SECONDS-start_sec))
echo
echo "Finish: $(date "+%Y %m %d %T %Z"): Elapsed time: $(((et % 3600)/60)) min, $((et % 60)) secs,  Found $gateway_count RMS Gateways, connected: $connect_count"  | tee -a $GATEWAY_LOGFILE
echo
# Set radio back to original memory channel
set_memchan_mode
echo "Setting radio back to original memory channel $save_mem_chan"
$RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $save_mem_chan
