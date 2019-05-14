#
# Makefile for latlon2grid.c
#
#
VERSION = 0.1

CC	= gcc
CFLAGS	= -O2 -g -gstabs -Wall
LIBS	= -lc

SRC  = latlon2grid.c
OBJS = latlon2grid.o

HDRS	=

CFLAGS += -I/usr/local/include

SYSTYPE := $(shell uname -s)

CFLAGS += -DLINUX

# Set LOCK to yes for serial port locking support
LOCK = no
LIBS   =

ifeq ($(LOCK), yes)
  CFLAGS += -DLOCKDEV
  LIBS   += -llockdev
endif

all:	latlon2grid

help:
	@echo "  SYSTYPE = $(SYSTYPE)"
	@echo "  CFLAGS = $(CFLAGS)"
	@echo "  LIBS   = $(LIBS)"
	@echo ""
	@echo "  Pick one of the following targets:"
	@echo  "\tmake latlon2grid
	@echo  "\tmake help"
	@echo " "


latlon2grid:	$(SRC) $(HDRS) $(OBJS) Makefile
		$(CC) $(OBJS) -o latlon2grid $(LIBS)

# Clean up the object files for distribution
clean:
		@rm -f $(OBJS)
		@rm -f core *.asc
		@rm -f latlon2grid
