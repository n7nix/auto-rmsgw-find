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
DEBUG=

# Used by rmslist.sh to set gateway distance from specified grid square
GWDIST=35
# Radio model number used by HamLib
# List radio model id numbers: rigctl -l
# Radio Model Number 234 specifies a Kenwood D710 which nearly works for a
#  Kenwood TM-V71a
# Crontab entry
# 5  */6   *   *   *  /bin/bash /home/<user>/bin/wlgw-check.sh -g CN88nl

RADIO_MODEL_ID=234

# Will refresh RMS list if true
b_refresh_gwlist=true

# Default to paclink-unix config file
AX25PORTNAME=

# Set to true for activating paclink-unix
# Set to false to test rig control, with no connect
# Set by -t command line arg
b_test_connect=true

b_crontab=false
bhave_gps=true

scriptname="`basename $0`"
TMPDIR="$HOME/tmp"
GATEWAY_LOGFILE="$TMPDIR/gateway.log"
RMS_STATS_FILE="$TMPDIR/rmsgw_stats.log"
GATEWAY_REJECT_FILE="$TMPDIR/gateway_reject.txt"
AXPORTS_FILE="/etc/ax25/axports"
declare -A row

BINDIR="$HOME/bin"
LOCAL_BINDIR="/usr/local/bin"

RIGCTL="$LOCAL_BINDIR/rigctl"
WL2KAX25="$LOCAL_BINDIR/wl2kax25"

# Serial device that Kenwood PG-5G cable is plugged into
SERIAL_DEVICE="/dev/ttyUSB0"
# Choose which radio left (VFOA) or right (VFOB) is DATA Radio
DATBND="VFOA"

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

##
### Start compare here
##

# ===== function gw_log
# Write string to gateway log file

function gw_log() {
    log_entry="$1"
    echo "$(date): $log_entry" | tee -a $GATEWAY_LOGFILE
}

# ===== function ctrl_c trap handler

function ctrl_c() {
    echo
    gw_log "Exiting script from trapped CTRL-C"
    echo
    # Set radio back to original memory channel
    set_memchan_mode
    echo "Setting radio back to original memory channel $save_mem_chan"
    $RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $save_mem_chan

    exit
}

# trap ctrl-c and call function ctrl_c()
trap ctrl_c INT

# ===== function debug_check

function debug_check() {

    strarg="$1"

    if [ ! -z "$DEBUG" ] ; then
        freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID f)
        xcurr_freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID --vfo f $DATBND)
        echo "${FUNCNAME[0]}: $strarg: Current frequency: VFOA: $xcurr_freq, freq: $freq"
    else
        freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID f)
        echo "${FUNCNAME[0]}: $strarg: freq: $freq"
    fi
}

# ===== function set_vfo_freq
# Arg1: frequency to set

function set_vfo_freq() {

    vfo_freq="$1"
    dbgecho "set_vfo_freq: $vfo_freq"

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
        gw_log "RIG CTRL ERROR[$errorcode]: set freq: $vfo_freq, TOut: $to_time, VFO mode=$vfomode_read, error:$errorsetfreq"
    fi

    return $ret_code
}

# ===== function set_vfo_mode
# Getting this error with timeout set to 5
# RIG CTRL ERROR: MEM mode=VFOA, error:set_vfo: error = Feature not
# available: increasing timeout to 10


function set_vfo_mode() {

    dbgecho "Set_vfo_mode"

    ret_code=1
    to_secs=$SECONDS
    to_time=0
    b_found_error=false

    while [ $ret_code -gt 0 ] && [ $((SECONDS-to_secs )) -lt 10 ] ; do

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
        gw_log "RIG CTRL ERROR[$errorcode]: set vfo mode: TOut: $to_time, VFO mode=$vfomode_read, error:$errorvfomode"
    fi

    return $ret_code
}

# ===== function set_memchan_mode

function set_memchan_mode() {
    dbgecho "Set vfo mode to MEM"

    ret_code=1
    to_secs=$SECONDS
    to_time=0
    b_found_error=false

    while [ $ret_code -gt 0 ] && [ $((SECONDS-to_secs )) -lt 10 ] ; do

        memchanmode=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID  V MEM)
        returncode=$?
        if [ ! -z "$memchanmode" ] ; then
            ret_code=1
            memmode_read=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID v)
            errormemmode=$memchanmode
            errorcode=$returncode
            to_time=$((SECONDS-to_secs))
            b_found_error=true

        else
            ret_code=0
        fi
    done

    if $b_found_error && [ $to_time -gt 3 ] ; then
        gw_log "RIG CTRL ERROR[$errorcode]: set MEM mode: TOut: $to_time, MEM mode=$memmode_read, error:$errormemmode"
        gw_log "RIG CTRL ERROR: MEM mode=$memmode_read, error:$memchanmode"
    fi

    return $ret_code
}

# ===== function set_memchan_index

# Arg1: index of memory channel to set
function set_memchan_index() {

    mem_index=$1
    dbgecho "set_memchan_index: $mem_index"

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
        gw_log "RIG CTRL ERROR[$errorcode]: set memory index: $mem_index, TOut: $to_time, error:$err_mem_ret"
    fi
    dbgecho "set_memchan_index: $ret_code"

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
            # echo "debug2: find_mem_chan: Found: $set_freq $lstf1 $listfreq $radfreq $radio_index"
            if [ "$radfreq" == "$set_freq" ] ; then
                chan_status="OK"
                retcode=0
            else
                chan_status="n/a"
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

    retcode=0
#    dbgecho "get_chan: arg: $1"
    chan_info=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID  h $1)
    ret_code=$?
#    echo "Ret code=$ret_code"
    grep -i "error" <<< "$chan_info"
    if [ $? -eq 0 ] ; then
        retcode=1;
    fi
    return $ret_code
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

# ===== function check_radio_mem
# arg1: radio memory index

function check_radio_mem() {

    mem_chan=$1
#    get_mem

    chan_info=
    get_chan $mem_chan
    if [ $? -ne 0 ] ; then
        echo "${FUNCNAME[0]}: Error could not get channel info from radio"
    fi
    #echo -e "Channel info\n$chan_info"

    # Get Alpha-Numeric name of channel in radio
    chan_name=$(grep -i "Name:" <<<"$chan_info" | cut -d ' ' -f4)
    # Remove surrounding quotes
    chan_name=${chan_name%\'}
    chan_name=${chan_name#\'}

    dbgecho "${FUNCNAME[0]}: name: $chan_name, info: $chan_info"
    # Get Frequency in MHz of channel number
    # Collapse white space
    chan_freq=$(grep -i "Freq:" <<<"$chan_info" | head -n1 | tr -s '[[:space:]] ' | cut -d ' ' -f2)
}

# ===== function check_gateway
# arg1: gateway frequency
# arg2: gateway call sign
# Set 2M frequencies with VFO & 440 frequencies with memory index

function check_gateway() {
    gw_freq="$1"

    gw_call="$2"
    # Set 'failed' return code
    connect_status=1

#    debug_check "start"

    # Set frequency
    if (( gw_freq >= 144000000 )) && (( gw_freq < 148000000 )) ; then
        b_2MBand=true
        vfo_mode=$($RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID v)
        if [ "$vfo_mode" == "MEM" ] ; then
            echo "  Set VFO radio band to 2M"
            # Set memory channel index
            set_memchan_index 35

            if [ ! -z "$DEBUG" ] ; then
                debug_check "Change to 2M band"
            fi
            # Now set VFO mode
            set_vfo_mode
        fi

        # Set Gateway frequency
        set_vfo_freq $gw_freq

        # The following just sets freq_name & radio index for log file
        find_mem_chan $gw_freq
        if [ $? -ne 0 ] ; then
            debug_check "No index for $gw_freq"
        fi
    else
        # Set 440 frequencies with a memory index
        dbgecho "  Set VFO radio band to 440"
        set_memchan_mode
        find_mem_chan $gw_freq
        if [ $? -ne 0 ] ; then
            echo "Can not set frequency $gw_freq, not programmed in radio."
            echo "Radio programming needs to match $DIGI_FREQ_LIST file"
            return 1
        fi
        $RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $radio_index
        if [ ! -z "$DEBUG" ] ; then
            debug_check "440"
        fi
    fi

    # Verify frequency has been set
    read_freq=$($RIGCTL -r $SERIAL_DEVICE  -m $RADIO_MODEL_ID f)

    if [ "$read_freq" -ne "$gw_freq" ] ; then
        gw_log "Failed to set frequency: $gw_freq for Gateway: $gw_call, read freq: $read_freq"
        return $connect_status
    else
        dbgecho "Frequency $read_freq set OK"
    fi

    if $b_test_connect ; then
        # Connect with paclink-unix
        dbgecho "Waiting for wl2kax25 to return ..."
        if [ -z "$AX25PORTNAME" ] ; then
            $WL2KAX25 -c "$gw_call"
        else
            $WL2KAX25 -a $AX25PORTNAME -c "$gw_call"
        fi
        connect_status="$?"
    else
        # Set connect_status to fail
        connect_status=1
    fi
     return $connect_status
}

# ===== function make_array
# Make an associative array:
# Index: gatway name plus first six digits of frequency
# Data: count of number of times gateway has connnected.

function make_array() {

while read fileline ; do
    # collapse all spaces
    fileline=$(echo $fileline | tr -s '[[:space:]]')

    # File some variables from Winlink web service call
    wl_freq=$(cut -d' ' -f2 <<< $fileline)
    wl_freq=$(echo $wl_freq | cut -c-6)
    gw_name=$(cut -d' ' -f1 <<< $fileline)
    index="${gw_name}_${wl_freq}"
    dbgecho "Using index $index"
    row[$index]=0
done < $RMS_PROXIMITY_FILE_OUT

}

# ==== function get_gateway_list

function get_gateway_list() {
    # Verify that a working Internet connection exists
    # TARGET_URL="http://google.com"
    TARGET_URL="http://example.com"
    wget --quiet --spider $TARGET_URL
    if [ $? -ne 0 ] ; then
        echo "Internet connection down, RMS List not refreshed."
    else
        echo
        echo "Refreshing RMS List"
        echo
        # Does RMS Gateway proximitiy file exist?
        if [ -e $RMS_PROXIMITY_FILE_OUT ] ; then
            # Save recent RMS Gateway list
            cp $RMS_PROXIMITY_FILE_OUT $TMPDIR/rmsgwprox.bak
        fi
        # Assume rmslist.sh installed to ~/bin
        # rmsglist arg1=distance in miles, arg2=grid square, arg3=mute output
        # Create file in $HOME/tmp/rmsgwprox.txt

#        echo "DEBUG: rmslist: $BINDIR/rmslist.sh $GWDIST $gridsquare S"
        $BINDIR/rmslist.sh $GWDIST $gridsquare S
#        $BINDIR/rmslist.sh $GWDIST $gridsquare

        # Does RMS Gateway proximitiy file exist?
        if [ -e $RMS_PROXIMITY_FILE_OUT ] ; then
            diff $RMS_PROXIMITY_FILE_OUT $TMPDIR/rmsgwprox.bak > /dev/null 2>&1
            if [ "$?" -ne 0 ] ; then
                echo "RMS GW proximity file has changed"
                linecnt_new=$(wc -l $TMPDIR/rmsgwprox.txt | cut -d ' ' -f1)
                linecnt_old=$(wc -l $TMPDIR/rmsgwprox.bak | cut -d ' ' -f1)
                echo "New proximity file has $linecnt_new entries, old file has $linecnt_old"
            fi
        fi
    fi
}

# ==== function create_reject_file
# Create a reject file with users call sign in it.

function create_reject_file() {
   # Get users call sign
   linecnt=$(grep -vc '^#' $AXPORTS_FILE)
   if (( linecnt > 1 )) ; then
      dbgecho "axports: found $linecnt lines that are not comments"
   fi
   # Collapse all spaces on lines that do not begin with a comment
   getline=$(grep -v '^#' $AXPORTS_FILE | grep -v 'N0ONE' | tr -s '[[:space:]] ')
   dbgecho "axports: found line: $getline"

   CALLSIGN=$(echo $getline | cut -d ' ' -f2 | cut -d ' ' -f1)
   dbgecho "axports: found call sign: $CALLSIGN"
   # Test if callsign string is not null
  if [ -z "$CALLSIGN" ] ; then
      CALLSIGN="NONE"
  fi

   echo $CALLSIGN > "$GATEWAY_REJECT_FILE"
}

# ===== function usage

function usage() {
   echo "Usage: $scriptname [-a <ax25_port_name][-g <gridsquare>][-d][-r][-s][-t][-h]" >&2
   echo " If no gps is found, gridsquare must be entered."
   echo "   -a <portname>   | --portname   Specify ax.25 port name ie. udr0 or udr1"
   echo "   -g <gridsquare> | --gridsquare Specify a six character grid square"
   echo "   -d | --debug      display debug messages"
   echo "   -r | --no_refresh use existing RMS Gateway list"
   echo "   -s | --stats      display statistics"
   echo "   -t | --test       test rig ctrl with NO connect"
   echo "   -h | --help       display this message"
   echo
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

# Verify that the stats array file exists
if [ ! -e "$RMS_STATS_FILE" ] ; then
    echo "Initializing RMS Stats file"
    make_array
    # Update RMS Gateway count file
    declare -p row > "$RMS_STATS_FILE"
else
    echo "Using existing $RMS_STATS_FILE"
    source -- "$RMS_STATS_FILE" || exit
fi

# if there are any args then parse them
while [[ $# -gt 0 ]] ; do
   key="$1"

   case $key in
      -a|--portname)   # set ax25 port
        AX25PORTNAME="$2"
        shift # past argument
        echo "Should not have to use '-a' option"
        echo " Check paclink-unix config file, ax25port"
        ;;
      -g|--gridsquare)
	 gridsquare="$2"
         shift # past argument
         bhave_gps=false
	 ;;
      -d|--debug)
         DEBUG=1
         echo "Set debug flag"
         WL2KAX25="$LOCAL_BINDIR/wl2kax25 -V"
         ;;
      -r|--norefresh)
         b_refresh_gwlist=false
         echo "Use the existing RMS Gateway list"
         ;;
      -t|--test)
         b_test_connect=false
         echo "Set test rig control only flag"
         ;;
      -s|--stats)
         printf "     Gateway\t\tConnects\n"
         for i in "${!row[@]}" ; do
             printf "%16s\t%3s\n" "$i" "${row[$i]}"
         done
         echo "Number of gateways: in array: ${#row[@]}, in list $(wc -l $RMS_PROXIMITY_FILE_OUT)"
         exit 0
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

# Temporary to put programs in local bin dir
# dev_setup

if ! $b_crontab ; then
    # This script uses these programs
    # It also uses gpsd but only if it is installed
    PROGRAM_LIST="rigctl rmslist.sh"
    if $bhave_gps ; then
        PROGRAM_LIST="rigctl rmslist.sh latlon2grid"
    fi
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

if $bhave_gps ; then
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
    get_gateway_list
else
    # Get here if do not want to refresh gateway list ... unless it doesn't exit
    if [ ! -e $RMS_PROXIMITY_FILE_OUT ] ; then
        get_gateway_list
    fi
fi

# Can not proceed without the RMS Gateway proximity file
# Does RMS Gateway proximitiy file exist?
if [ ! -e $RMS_PROXIMITY_FILE_OUT ] ; then
    echo "No Gateway proxmity file found: $RMS_PROXIMITY_FILE_OUT, exiting"
    exit 1
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

# Verify reject file exists & if not create it
if [ ! -f "$GATEWAY_REJECT_FILE" ] ; then
    dbgecho "Creating_reject_file"
    create_reject_file
    dbgecho "Creating_reject_file: end"
fi

# Iterate each line of the RMS Proximity file

total_gw_count=0
gateway_count=0
connect_count=0
reject_count=0
start_sec=$SECONDS
gw_call_last=
gw_freq_last=

# if [ -z "$DEBUG" ] ; then
    echo | tee -a $GATEWAY_LOGFILE
    echo "Start: $(date "+%Y %m %d %T %Z"): grid: $gridsquare, debug: $DEBUG, GW list refresh: $b_refresh_gwlist, connect: $b_test_connect, cron: $b_crontab, port: $AX25PORTNAME" | tee -a $GATEWAY_LOGFILE

    # Table header is 2 lines
    printf  "\n\t\t\t\t\t\tChan\tConn\n" | tee -a $GATEWAY_LOGFILE
    printf "RMS GW\t    Freq\tDist\tName\tIndex\tStat\tStat\tTime  Conn\n" | tee -a $GATEWAY_LOGFILE
#fi

while read fileline ; do

    # collapse all spaces
    fileline=$(echo $fileline | tr -s '[[:space:]]')

    # File some variables from Winlink web service call
    baud_rate=$(cut -d' ' -f4 <<< $fileline)
    distance=$(cut -d' ' -f3 <<< $fileline)
    wl_freq=$(cut -d' ' -f2 <<< $fileline)
    gw_name=$(cut -d' ' -f1 <<< $fileline)

    # Filter out call signs from the gateway reject file
    grep $gw_name $GATEWAY_REJECT_FILE  >/dev/null 2>&1
    retcode="$?"

    dbgecho "DEBUG: Reject list test for $gw_name, retcode: $retcode"
    if [ "$retcode" -eq 0 ] ; then
        echo "Skipping call sign: $gw_name"
        reject_count=$((reject_count + 1))
        continue;
    fi

    # Filter out duplicate entries
    dbgecho "Connect to: $gw_name with radio using freq $wl_freq"
    if [ "$gw_name" = "$gw_call_last" ] && [ "$wl_freq" = "$gw_freq_last" ] ; then
        echo "Found duplicate: gateway: $gw_name, frequency: $wl_freq"
        continue;
    fi

    gw_call_last=$gw_name
    gw_freq_last=$wl_freq

    # Using a TM-V71a 2M/440 dual band radio
    if (( "$wl_freq" >= 420000000 )) && (( "$wl_freq" < 430000000 )) ; then
        echo "Warning: Frequency violates Line A"
    fi

    #setup index for statistics collection
    short_freq=$(echo $wl_freq | cut -c-6)
    index="${gw_name}_${short_freq}"
    dbgecho "Using index $index: value: ${row[$index]}"

    next_sec=$SECONDS
    freq_name="unknown"
    connect_status="n/a"
    total_gw_count=$((total_gw_count + 1))

    # Qualify RMS Gateways found by frequency
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
            row[$index]=$((row[$index] + 1))
            echo
            echo "Call to wl2kax25 connect OK"
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
    printf "%-10s  %s\t%2s\t%s\t%4s   %6s\t%4s\t %2d   %d\n"  "$gw_name" "$wl_freq" "$distance" "$freq_name" "$radio_index" "$chan_status" "$connect_status" $((SECONDS-next_sec)) ${row[$index]}  | tee -a $GATEWAY_LOGFILE

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

# Update RMS Gateway count file
declare -p row > "$RMS_STATS_FILE"
echo "Number of gateways: in array: ${#row[@]}, in list $(wc -l $RMS_PROXIMITY_FILE_OUT)"

# Get elapsed time in seconds
et=$((SECONDS-start_sec))
echo
echo "Finish: $(date "+%Y %m %d %T %Z"): Elapsed time: $(((et % 3600)/60)) min, $((et % 60)) secs,  Found $gateway_count RMS Gateways, connected: $connect_count, rejected: $reject_count"  | tee -a $GATEWAY_LOGFILE
echo
# Set radio back to original memory channel
set_memchan_mode
echo "Setting radio back to original memory channel $save_mem_chan"
$RIGCTL -r $SERIAL_DEVICE -m $RADIO_MODEL_ID E $save_mem_chan
