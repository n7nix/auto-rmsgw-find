## auto-rmsgw-find

### Installation tip
* Either use git to clone repo __or__ use wget to download a tarball of the files.

##### To get a copy of the repository using git:

```
git clone https://github.com/n7nix/auto-rmsgw-find
```
##### Use wget to create a zipped tarball:
```
# To get a tar zipped file, rmsgw.tgz
wget -O auto-rmsgw-find.tgz https://github.com/n7nix/auto-rmsgw-find/tarball/master

# To create a directory with source files from the zipped tarball
wget -O - https://github.com/n7nix/auto-rmsgw-find/tarball/master | tar -xz
```

### mheard-mail.sh

Manually specify an RMS Gateway call sign from list provided by
_mheard_

**Usage:** mheard-mail.sh [-d][-h]
```
   -d        set debug flag
   -h        display this message
```

The _mheard-mail.sh_ script is not directly related to the
_auto-rmsgw-find_ scripts but provides an easy way to identify
nearby RMS Gateways captured by the _mheard_ utility and connect to
that gateway . It prompts for a gateway call sign and execs wl2kax25

###### Depends on
* mheard - an ax25 tools utility
* paclink-unix
* bash version 4.3-7 and above

##### To run from desktop icon

* Get rid of annoying dialog box that prompts for what to do with an
executable
* File manager > Edit > Preferences > General
  * Check _Don't ask options on launch executable file_
* Copy script to be executed from icon, _mheard-mail.sh_ to local bin
directory
```
cp mheard-mail.sh ~/bin
```

###### Example Desktop icon file

* Put this file in your _Desktop_ directory
  * This is an example only, make your own Icon

```
[Desktop Entry]
Name=mheard-mail
Exec=sh -c '/home/pi/bin/mheard-mail.sh; $SHELL'
Comment=Click to connect
Icon=/usr/share/desktop-base/debian-logos/logo-64.png
Terminal=true
Type=Application
Categories=HamRadio
Keywords=Ham Radio;AX.25
X-KeepTerminal=true
```


### wlgw-check.sh

Automatically find and attempt to connect to a Winlink RMS Gateway

**Usage:** ```wlgw-check.sh [-a <ax25_port_name>][-g <gridsquare>][-d][-r][-s][-t][-h]```
```
 If no gps is found, gridsquare must be entered.
   -a <portname>   | --portname   Specify ax.25 port name ie. udr0 or udr1"
   -g <gridsquare> | --gridsquare Specify a six character grid square"
   -d | --debug      display debug messages
   -r | --no_refresh use existing RMS Gateway list
   -s | --stats      display statistics
   -t | --test       test rig ctrl with NO connect
   -h | --help       display this message
```

* **NOTE:** If you are setting the ax25 port name with __-a__ option you probably should be setting the default port name in the paclink-unix config file
_/usr/local/etc/wl2k.conf_, ax25port=
* **NOTE:** This script uses rig control for a Kenwood TM-V71a **ONLY**

This script interrogates Winlink Web Services to find registered Winlink RMS Gateways within some distance of a grid square location.

If a gps is found the grid square location is determined from Lat &
Lon co-ordinates otherwise grid square must be specified on command
line, ie.

```
wlgw-check.sh -g CN88nl
```
_wlgw-check.sh_ uses paclink-unix _wl2kax25_ for connection evaluation.


#### Requirements

This script is used with the following programs to locate and connect to a Winlink RMS Gateway

* [paclink-unix](https://github.com/nwdigitalradio/paclink-unix)
* [rmslist.sh](https://github.com/nwdigitalradio/n7nix/blob/master/bin/rmslist.sh)
* [rigctl](https://www.mankier.com/1/rigctl) (HamLib)
* [gpsd](http://www.catb.org/gpsd/)
* [latlon2grid](https://github.com/n7nix/auto-rmsgw-find/tree/master/gridsq)

#### Install
* Requires these files to be in local bin directory
```
rmslist.sh
freqlist_digit.txt
latlon2grid
```
#### Show Gateway Connection Log

```
$ show_log.sh
Using date: 2019 05 28, starting at line number: 1205, numb_lines: 71
Start: 2019 05 28 00:05:03 PDT: grid: CN88nl, debug: , GW list refresh: true, connect: true, cron: true

						Chan	Conn
RMS GW	    Freq	Dist	Name	Index	Stat	Stat	Time  Conn
KF7FIT-10   223780000	 0	NET-21	       Unqual	 n/a	  0   0
N7NIX-10    144910000	 0	NET-16	  35   Unqual	 n/a	  0   0
K7KCA-10    440125000	 3	NET-45	 135       OK	  OK	 34   10
KE7KML-10   223780000	 3	NET-21	       Unqual	 n/a	  0   0
AF4PM-10    145690000	 4	NET-14	  33       OK	  OK	 31   11
AF5TR-10    145690000	11	NET-14	  33       OK	  to	 21   0
AE7LW-10    145050000	16	NET113	          n/a	  to	 21   0
AE7LW-10    440950000	16	NET-46	 136       OK	  to	 22   0
KD7X-10     145630000	16	NET-13	  32       OK	  to	 22   0
KI7ULA-10   145050000	16	NET113	          n/a	  OK	 21   7
WA7GJZ-10   145630000	19	NET-13	  32       OK	  to	 22   0
WA7GJZ-10   145630000	19	NET-13	  32       OK	  to	 21   0
NG2G-10     144990000	26	NET-11	  30       OK	  to	 21   0
W7ECG-10    144930000	28	NET-17	  36       OK	  to	 22   0
VE7VIC-10   145690000	31	NET-14	  33       OK	  OK	 89   5
KC7OAS-10   144950000	33	NET-12	  31       OK	  to	 22   0
KG7WFV-10   145630000	35	NET-13	  32       OK	  to	 21   0
W7BPD-10    145630000	35	NET-13	  32       OK	  to	 21   0
Finish: 2019 05 28 00:12:04 PDT: Elapsed time: 7 min, 1 secs,  Found 15 RMS Gateways, connected: 4
```

#### Show Gateway Connection Stats

```
$ ./wlgw-check.sh -s
Using existing /home/gunn/tmp/rmsgw_stats.log
     Gateway		Connects
KF7FIT-10_223780	  0
 W7BPD-10_145630	  0
  KD7X-10_145630	  0
KI7ULA-10_145050	  7
 W7ECG-10_144930	  0
WA7GJZ-10_145630	  0
 AF5TR-10_145690	  0
 AF4PM-10_145690	 13
VE7VIC-10_145690	  6
KG7WFV-10_145630	  0
 K7KCA-10_440125	 11
 AE7LW-10_440950	  0
KE7KML-10_223780	  0
KC7OAS-10_144950	  0
 N7NIX-10_144910	  0
  NG2G-10_144990	  0
 AE7LW-10_145050	  0
Number of gateways: in array: 17, in list 18 /home/gunn/tmp/rmsgwprox.txt
```

#### crontab

* To collect data on a regular basis running the wlgw-check.sh script 4 times a day.

```
5  */6   *   *   *  /bin/bash /home/gunn/bin/wlgw-check.sh -g CN88nl
```
