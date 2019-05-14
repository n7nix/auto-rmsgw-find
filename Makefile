#
# Makefile for kw_ctrl.c
#
#
VERSION = 0.1

CC	= gcc
CFLAGS	= -O2 -g -gstabs -Wall
LIBS	= -lc

SRC  = kw_ctrl.c
OBJS = kw_ctrl.o

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

all:	kw_ctrl

help:
	@echo "  SYSTYPE = $(SYSTYPE)"
	@echo "  CFLAGS = $(CFLAGS)"
	@echo "  LIBS   = $(LIBS)"
	@echo ""
	@echo "  Pick one of the following targets:"
	@echo  "\tmake kw_ctrl
	@echo  "\tmake help"
	@echo " "


kw_ctrl:	$(SRC) $(HDRS) $(OBJS) Makefile
		$(CC) $(OBJS) -o kw_ctrl $(LIBS)

# Clean up the object files for distribution
clean:
		@rm -f $(OBJS)
		@rm -f core *.asc
		@rm -f kw_ctrl
