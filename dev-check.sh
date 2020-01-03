#!/bin/bash
# dev-check.sh
# Verify USB serial device exists on a system

SERIAL_DEVICE="/dev/ttyUSB0"

# Count number of USB serial devices enumerated
devcnt=$(ls /dev/ttyUSB* | grep -c "ttyUSB")
echo "Found $devcnt USB serial device(s) on this system."

# Get ttyUSB device string
devstring=$(ls -l /dev/serial/by-id)

# Display USB serial device name
# trims everything from the front of string until a '/', greedily.
devname=$(echo ${devstring##*/})
cfgname=$(echo ${SERIAL_DEVICE##*/})

comp="matches"
if [ "$devname" != "$cfgname" ] ; then
    comp="does NOT match"
fi

echo "Device: $devname, config: $cfgname: $comp"
