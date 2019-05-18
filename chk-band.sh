#!/bin/bash
#
# Switch bands
#
# Uncomment this statement for debug echos
DEBUG=1
b_dev=true
scriptname="`basename $0`"

# Serial device that PG-5G cable is plugged into
SERIAL_DEVICE="/dev/ttyUSB0"
# Choose which radio left (VFOA) or right (VFOB) is DATA Radio
DATBND="VFOA"

# Radio model number used by HamLib
RADIO_MODEL_ID=234

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

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

# ===== function debug_check
function debug_check() {

    strarg="$1"
    freq=$(rigctl -r $SERIAL_DEVICE  -m234 f)
    xcurr_freq=$(rigctl -r /dev/ttyUSB0  -m234 --vfo f $DATBND)
    echo "debug_check: $strarg: Current frequency: VFOA: $xcurr_freq, freq: $freq"
}

# ===== function switch_bands
# Arg1: 2=2M band, 4=440 band

function switch_bands() {

    switb="$1"
    memchan=131
    echo "Switching bands to: $switb"

    if [ "$switb" -eq 2 ] ; then
        memchan=35
    fi

    vfo_mode=$(rigctl -r /dev/ttyUSB0 -m234 v)
    if [ "$vfo_mode" != "MEM" ] ; then
        set_memchan_mode
    fi


    echo "Set VFO radio band to $switb, with mem chan: $memchan"
    # Fix this
    rigctl -r /dev/ttyUSB0 -m234 E $memchan
    # Verify frequency has been set
    read_freq=$(rigctl -r $SERIAL_DEVICE  -m234 f)
    echo "Memchan verify: $memchan: freq: $read_freq"

    debug_check "$memchan "
#    set_vfo_mode
}


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

# ===== main

b_2MBand=true
s_band=2
set_freq=145090000

curr_freq=$(rigctl -r $SERIAL_DEVICE -m234 f)

if (( "$curr_freq" >= 144000000 )) && (( "$curr_freq" < 148000000 )) ; then
    b_2MBand=true
    s_band=4
    set_freq=440950000
fi

get_mem
set_memchan_mode
debug_check "Main 1"

switch_bands $s_band
get_mem

# Set new frequency
set_vfo_mode
vfo_mode=$(rigctl -r /dev/ttyUSB0 -m234 v)
echo "Setting frequency in $vfo_mode"
rigctl -r /dev/ttyUSB0 -m234 F $set_freq

# Verify frequency has been set
read_freq=$(rigctl -r $SERIAL_DEVICE  -m234 f)
echo "Read frequency: $read_freq, Set frequency $set_freq"

if [ "$read_freq" -ne "$set_freq" ] ; then
    echo "Failed to set frequency: $set_freq"
    debug_check "Fail "
else
    dbgecho "Frequency $read_freq set OK"
fi
