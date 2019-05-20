## auto-rmsgw-find
Automatically find and test  a Winlink RMS Gateway

#### Requirements

This script is used with the following programs to locate and connect to a Winlink RMS Gateway

* [paclink-unix](https://github.com/nwdigitalradio/paclink-unix)
* [rmslist.sh](https://github.com/nwdigitalradio/n7nix/blob/master/bin/rmslist.sh)
* rigctl (HamLib)
* gpsd
* [latlon2grid](https://github.com/n7nix/auto-rmsgw-find/tree/master/gridsq)

#### wlgw-check.sh

Interrogate Winlink Web services to find registered Winlink RMS Gateways within some distance of a grid square location.
If a gps is found the grid square location is determined from Lat & Lon co-ordinates.

Calls paclink-unix wl2kax25 for connection evaluation.

