# Rules for a BID library written in Oberon. Set before including this in
# place of $(L4DIR)/mk/lib.mk:
#   TARGET       the archive, lib$(VOC_LIB).a
#   VOC_LIB      the library's package name, as other packages' VOC_LIBS
#   VOC_MODULES  its modules, in import order; their .Mod are in the source dir
#   VOC_LIBS     other Oberon library packages it imports

include $(dir $(lastword $(MAKEFILE_LIST)))voc.mk

PC_FILENAME	?= $(VOC_LIB)
SRC_C		+= $(VOC_MODULES:%=%.c)
PRIVATE_INCDIR	+= . $(VOC_EXPORT_DIR)
DEL_ON_CLEAN	+= $(foreach m,$(VOC_MODULES),$m.c $m.h $m.sym) voc-lib.stamp

include $(L4DIR)/mk/lib.mk

voc-lib.stamp: $(VOC_MODULES:%=$(SRC_DIR)/%.Mod) $(VOC_DEP_STAMPS)
	$(voc_check_platform)
	$(VERBOSE)$(VOC_TRANSLATE) -SFs $(VOC_MODULES:%=$(SRC_DIR)/%.Mod)
	$(VERBOSE)touch $@

$(VOC_MODULES:%=%.c): voc-lib.stamp ;

# Install headers and symbol files for the packages that import this one.
ifneq ($(SYSTEM),)
all:: $(VOC_EXPORT_DIR)/$(VOC_LIB).stamp

$(VOC_EXPORT_DIR)/$(VOC_LIB).stamp: voc-lib.stamp
	$(VERBOSE)mkdir -p $(VOC_EXPORT_DIR)
	$(VERBOSE)cp $(VOC_MODULES:%=%.h) $(VOC_MODULES:%=%.sym) $(VOC_EXPORT_DIR)/
	$(VERBOSE)touch $@
endif
