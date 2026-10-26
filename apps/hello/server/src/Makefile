PKGDIR		?= ../..
L4DIR		?= $(L4RE_SRCDIR)

TARGET		= oberon-hello

# voc translates Oberon to C on the host; BID compiles the C for L4Re.
VOC		?= $(VOC_ROOT)/install/bin/voc
VOC_RUNTIME	= $(VOC_ROOT)/src/runtime
VOC_LIBRARY	= $(VOC_ROOT)/src/library
VOC_PLATFORM	?= l4re

# The runtime C must agree with the Platform variant it is built with.
ifeq ($(VOC_PLATFORM),l4re)
DEFINES		+= -DVOC_L4RE
endif

# Runtime modules in import order; Platform must precede Heap.
VOC_MODS	= $(VOC_RUNTIME)/PlatformNative$(VOC_PLATFORM).Mod \
		  $(VOC_RUNTIME)/Platform$(VOC_PLATFORM).Mod \
		  $(VOC_RUNTIME)/Heap.Mod \
		  $(VOC_LIBRARY)/Out.Mod \
		  $(VOC_RUNTIME)/Modules.Mod
VOC_GEN_C	= PlatformNative.c Platform.c Heap.c Out.c Modules.c

SRC_C		= Hello.c $(VOC_GEN_C) SYSTEM.c
PRIVATE_INCDIR	= . $(VOC_RUNTIME)
DEL_ON_CLEAN	= Hello.c Hello.h $(VOC_GEN_C) $(VOC_GEN_C:.c=.h) *.sym \
		  voc-runtime.stamp voc-platform

# voc's generated C trips most of WARNINGS_FULL.
WARNINGS	= $(WARNINGS_MINIMAL)

vpath SYSTEM.c $(VOC_RUNTIME)

include $(L4DIR)/mk/prog.mk

# Every platform generates the same file names here, so record which one
# was last translated; it only changes when VOC_PLATFORM does.
voc-platform: FORCE
	$(VERBOSE)echo $(VOC_PLATFORM) > $@.tmp
	$(VERBOSE)cmp -s $@.tmp $@ && rm -f $@.tmp || mv $@.tmp $@

FORCE: ;

# Translate the runtime into this object dir so Hello is checked against
# these symbol files rather than the installed ones.
voc-runtime.stamp: $(VOC_MODS) voc-platform
	$(VERBOSE)$(VOC) -SFs -O2 $(VOC_MODS)
	$(VERBOSE)touch $@

$(VOC_GEN_C): voc-runtime.stamp ;

Hello.c: $(SRC_DIR)/Hello.Mod voc-runtime.stamp
	$(VERBOSE)$(VOC) -Sm $<
