# Rules for a BID program written in Oberon, linked against pkg/voc-runtime.
# Set before including this in place of $(L4DIR)/mk/prog.mk:
#   VOC_MAIN     the main module; $(VOC_MAIN).Mod is in the source dir
#   VOC_MODULES  the program's other modules, in import order
#   VOC_LIBS     Oberon library packages it imports (mk/voc-lib.mk)

include $(dir $(lastword $(MAKEFILE_LIST)))voc.mk

VOC_APP_MODS	= $(VOC_MODULES) $(VOC_MAIN)

SRC_C		+= $(VOC_APP_MODS:%=%.c)
PRIVATE_INCDIR	+= . $(VOC_EXPORT_DIR)
DEL_ON_CLEAN	+= $(foreach m,$(VOC_APP_MODS),$m.c $m.h $m.sym) voc-prog.stamp

include $(L4DIR)/mk/prog.mk

voc-prog.stamp: $(VOC_APP_MODS:%=$(SRC_DIR)/%.Mod) $(VOC_DEP_STAMPS)
	$(voc_check_platform)
	$(if $(VOC_MODULES),$(VERBOSE)$(VOC_TRANSLATE) -SFs $(VOC_MODULES:%=$(SRC_DIR)/%.Mod))
	$(VERBOSE)$(VOC_TRANSLATE) -Sm $(SRC_DIR)/$(VOC_MAIN).Mod
	$(VERBOSE)touch $@

$(VOC_APP_MODS:%=%.c): voc-prog.stamp ;
