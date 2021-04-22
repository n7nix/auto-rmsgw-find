#!/bin/bash
#
# Show today's or yesterdays log file generated by wlgw-check.sh

# Uncomment this statement for debug echos
# DEBUG=1
scriptname="`basename $0`"

TMPDIR="$HOME/tmp"
LOGFILE="$TMPDIR/gateway.log"

OUTFILE_0="$TMPDIR/test.log"
OUTFILE_1="$TMPDIR/test1.log"
OUTFILE_FINAL="$TMPDIR/test2.log"


function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function check for an integer

function is_num() {
    local chk=${1#[+-]};
    [ "$chk" ] && [ -z "${chk//[0-9]}" ]
}

# ===== function refresh_remote_log
# get remote gateway log file so can run on workstation
# Current workstation hostname = beeble

function refresh_remote_log() {
    hostname="$(hostname)"
    if [ "$hostname" = "beeble" ] ; then

        rsync --quiet -av -e ssh gunn@10.0.42.85:tmp/gateway.log $TMPDIR
	if [ $? -ne 0 ] ; then
	    echo "Refresh of gateway log file FAILED"
	    exit 1
	else
            dbgecho "Successfully refreshed RMS Gateway log file"
	fi
    fi
}

# ===== function aggregate_log

function aggregate_log() {

    # sed -i 's/[^[:print:]]//' $OUTFILE_0

    # Get rid of any embedded null characters
    sed -i 's/\x0//g' $OUTFILE_0
    # Get rid of any error or header lines
    sed -i '/RIG CTRL\|Failed to\|Finish:\|Start:\|^RMS GW\|^[[:space:]]\|^$/d' $OUTFILE_0 | tr -s '[[:space:]]'

    # Filter Gateways that were able to connect
    while IFS= read -r line ; do
        connect=$(echo $line | cut -f7 -d' ')
        if [ "$connect" == "OK" ] ; then
	    # Output line to temporary file
            echo "$line"
        fi
    done <<< $(awk 'NF{NF-=2};1' < $OUTFILE_0) > $OUTFILE_1

    if [ -f "$OUTFILE_FINAL" ] ; then
        rm "$OUTFILE_FINAL"
    fi

    # Print header
    printf " Call Sign\tFrequency  Alpha\tDist\t Cnt\n"

    # Create final output file
    while IFS= read -r line ; do
        # Get connection count,
	#  -need search on both call sign & frequency
        callsign=$(echo $line | cut -f1 -d' ')
        frequency=$(echo $line | cut -f2 -d' ')

        conn_cnt=$(cat $OUTFILE_1 | expand -t1 | tr -s '[[:space:]]' | grep --binary-file=text -c -i "$callsign $frequency")

        printf "%10s \t%s  %3s\t%2d\t%4d\n" $(echo $line | cut -f1 -d' ') $(echo $line | cut -f2 -d ' ') $(echo $line | cut -f4 -d' ') $(echo $line | cut -f3 -d' ') "$conn_cnt" >> $OUTFILE_FINAL
    done <<< $(sort -r -k3,3 -n $OUTFILE_1 | uniq | awk 'NF{NF-=3};1')

    # Sort on column 5 numeric, reverse order then column 4 numeric
    sort  -k5rn -k4,4n $OUTFILE_FINAL | tee -a connection.log
    # Print trailer
    echo "Connected to $(cat $OUTFILE_FINAL | wc -l) gateways."
}

# ===== function get_logfile
# grab a chunk of log file between a pair of dates
# arg 1 = start date
# arg 2 = end date

function get_logfile() {
    start_date="$1"
    end_date="$2"

    # Get line number of required dates first entry
    start_line_numb=$(grep --binary-files=text -n "$start_date" $LOGFILE | head -n 1 | cut -d':' -f1)
    start_line_numb=$((start_line_numb-1))
    # Get line number of todays date first entry
    end_line_numb=$(grep --binary-files=text -n "$end_date" $LOGFILE | head -n 1 | cut -d':' -f1)

    # number of lines starting at yesterdays first log entry
    numb_lines=$((total_lines - start_line_numb))
    # number of lines until start of todays date
    count_lines=$((end_line_numb - start_line_numb - 1))

    if [ "$3" != "q" ] ; then
        echo "Using date: $start_date, starting: $start_line_numb, ending: $end_line_numb, num lines: $count_lines"
    fi
    tail -n $numb_lines $LOGFILE | head -n $count_lines
}

# ===== Display program help info

function usage () {
	(
	echo "Usage: $scriptname [-p <day|week|month|year|thisyear>][-v][-h]"
	echo "   no args           display today's log file"
        echo "   -p <day|week|month|year|thisyear> aggregation period"
        echo "   -v                turn on verbose display"
	echo "   -y                display yesterday's log file"
        echo "   -h                display this message."
        echo
	) 1>&2
	exit 1
}

#
# ===== Main ===============================


# Get today's date
date_now=$(date "+%Y %m %d")

start_yest=$(date --date="yesterday" "+%Y %m %d")
#start_month=$(date --date="$(date +'%Y-%m-01')" "+%Y %m %d")
start_month=$(date --date="30 day ago" "+%Y %m %d")
#start_week=$(date -d "last week + last monday" "+%Y %m %d")
start_week=$(date -d "7 day ago" "+%Y %m %d")
start_year=$(date --date="$(date +%Y-01-01)" "+%Y %m %d")

# if hostname is beeble then assume running on workstation & not
# machine collecting data
# Refresh gateway log file from collection machine

refresh_remote_log

# Find total lines in log file
total_lines=$(wc -l $LOGFILE | cut -d' ' -f1)

# parse any command line options
while [[ $# -gt 0 ]] ; do

    key="$1"
    case $key in
        -d)
            # Set debug flag
             DEBUG=1
	     dbgecho "DEBUG flag set, ARGS on command line: $#"
        ;;
        -p)

            dbgecho "DEBUG: Date check: $start_yest,  $start_week,  $start_month"
	    dbgecho

	    # aggregate period in number of days
            agg_period=

	    case "$2" in
	        year)
		    echo "Aggregation period: year"
		    start_date=$(date -d "last year" "+%Y %m %d")
		;;
		thisyear)
		    echo "Aggregation period: year-to-date"
		    start_date=$(date --date=$(date +'%Y-01-01') "+%Y %m %d")
		;;
	        all)
                    start_date=$(head $LOGFILE  | grep -i "Start" | cut -f2 -d':' | sed 's/^[[:blank:]]*//' | rev | cut -f2- -d' ' | rev)
		    echo "DEBUG: all start: $start_date"
		;;
                day)
		    echo "Aggregation period: yesterday"
                    start_date=$start_yest
                ;;
                week)
		    echo "Aggregation period: last week"
                    start_date=$start_week
	        ;;
                month)
		    echo "Aggregation period: last month"
                    start_date=$start_month
                ;;
	        *)
		    echo "Unknown period, should be one of day, week, month, year, thisyear"
		    echo " Default to day"
                    start_date=$start_yest
                ;;
            esac

            get_logfile "$start_date" "$date_now" q > $OUTFILE_0

	    # Get grid square
	    grid_square=$(grep --binary-file=text -i "grid: " $LOGFILE | tail -n 1 | cut -d',' -f1  | cut -d':' -f6)
	    # Remove preceeding white space
            grid_square="$(sed -e 's/^[[:space:]]*//' <<<"$grid_square")"


	    echo "Aggregated log file from $start_date to $date_now for grid square: $grid_square"
	    echo
	    aggregate_log
	    exit 0
        ;;
	-y)
	    # Show yesterday's log
            # Get yesterdays date
            start_date=$(date --date="yesterday" "+%Y %m %d")
            get_logfile "$start_date" "$date_now"
	    exit 0
	;;
        -v)
            echo "Turning on verbose"
            bverbose=true
        ;;
        -h)
            usage
            exit 0
        ;;
        *)
            echo "Undefined argument: $key"
            usage
            exit 1
        ;;
    esac
    shift # past argument or value
done

# Show todays log
start_date=$date_now

start_line_numb=$(grep --binary-files=text -n "$start_date" $LOGFILE | head -n 1 | cut -d':' -f1)
start_line_numb=$((start_line_numb-1))
numb_lines=$((total_lines - start_line_numb))

echo "Using date: $start_date, starting at line number: $start_line_numb, numb_lines: $numb_lines"
tail -n $numb_lines $LOGFILE

