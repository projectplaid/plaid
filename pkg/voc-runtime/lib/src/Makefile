PKGDIR		?= ../..
L4DIR		?= $(L4RE_SRCDIR)

TARGET		= libvoc-runtime.a
PC_FILENAME	= voc-runtime

include $(PKGDIR)/../../mk/voc.mk

VOC_RUNTIME	= $(VOC_ROOT)/src/runtime
VOC_LIBRARY	= $(VOC_ROOT)/src/library

# The l4re Platform is Plaid's, kept here; other variants are voc's own.
VOC_PLATFORM_DIR = $(if $(filter l4re,$(VOC_PLATFORM)),$(SRC_DIR),$(VOC_RUNTIME))

# Plaid's kernel interface (L4, L4Re), ahead of Platform so Platform can
# use it, then voc's runtime library (oberon.mk's runtime target), all in
# import order; Platform must precede Heap.
VOC_NAMES	= L4 L4Re PlatformNative Platform Heap Out Modules Reals \
		  Strings In VT100 Files Math MathL Texts Oberon
VOC_MODS	= $(SRC_DIR)/L4.Mod \
		  $(SRC_DIR)/L4Re.Mod \
		  $(VOC_PLATFORM_DIR)/PlatformNative$(VOC_PLATFORM).Mod \
		  $(VOC_PLATFORM_DIR)/Platform$(VOC_PLATFORM).Mod \
		  $(VOC_RUNTIME)/Heap.Mod \
		  $(VOC_LIBRARY)/Out.Mod \
		  $(VOC_RUNTIME)/Modules.Mod \
		  $(VOC_LIBRARY)/Reals.Mod \
		  $(VOC_LIBRARY)/Strings.Mod \
		  $(VOC_LIBRARY)/In.Mod \
		  $(VOC_RUNTIME)/VT100.Mod \
		  $(VOC_LIBRARY)/Files.Mod \
		  $(VOC_LIBRARY)/Math.Mod \
		  $(VOC_LIBRARY)/MathL.Mod \
		  $(VOC_RUNTIME)/Texts.Mod \
		  $(VOC_LIBRARY)/Oberon.Mod

SRC_C		= $(VOC_NAMES:%=%.c) SYSTEM.c
PRIVATE_INCDIR	= . $(VOC_RUNTIME)
REQUIRES_LIBS	= libm l4re_c l4re_c-util
DEL_ON_CLEAN	= $(foreach m,$(VOC_NAMES),$m.c $m.h $m.sym) \
		  voc-runtime.stamp voc-platform

vpath SYSTEM.c $(VOC_RUNTIME)

include $(L4DIR)/mk/lib.mk

# Every platform generates the same file names here, so record which one
# was last translated; it only changes when VOC_PLATFORM does.
voc-platform: FORCE
	$(VERBOSE)echo $(VOC_PLATFORM) > $@.tmp
	$(VERBOSE)cmp -s $@.tmp $@ && rm -f $@.tmp || mv $@.tmp $@

FORCE: ;

voc-runtime.stamp: $(VOC_MODS) voc-platform
	$(VERBOSE)$(VOC) -SFs -O2 $(VOC_MODS)
	$(VERBOSE)touch $@

$(VOC_NAMES:%=%.c): voc-runtime.stamp ;

# Install headers and symbol files for programs; see mk/voc-prog.mk. The
# platform file lets them check they were built for the same variant.
ifneq ($(SYSTEM),)
all:: $(VOC_EXPORT_DIR)/voc-runtime.stamp

$(VOC_EXPORT_DIR)/voc-runtime.stamp: voc-runtime.stamp $(VOC_RUNTIME)/SYSTEM.h
	$(VERBOSE)mkdir -p $(VOC_EXPORT_DIR)
	$(VERBOSE)cp $(VOC_NAMES:%=%.h) $(VOC_NAMES:%=%.sym) \
	  $(VOC_RUNTIME)/SYSTEM.h $(VOC_EXPORT_DIR)/
	$(VERBOSE)echo $(VOC_PLATFORM) > $(VOC_EXPORT_DIR)/platform
	$(VERBOSE)touch $@
endif
