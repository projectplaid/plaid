# Rules for a BID program written in Oberon, linked against pkg/voc-runtime.
# Set before including this in place of $(L4DIR)/mk/prog.mk:
#   VOC_MAIN     the main module; $(VOC_MAIN).Mod is in the source dir
#   VOC_MODULES  the program's other modules, in import order

include $(dir $(lastword $(MAKEFILE_LIST)))voc.mk

VOC_APP_MODS	= $(VOC_MODULES) $(VOC_MAIN)

SRC_C		+= $(VOC_APP_MODS:%=%.c)
REQUIRES_LIBS	+= voc-runtime
PRIVATE_INCDIR	+= . $(VOC_EXPORT_DIR)
DEL_ON_CLEAN	+= $(foreach m,$(VOC_APP_MODS),$m.c $m.h $m.sym) voc-prog.stamp

include $(L4DIR)/mk/prog.mk

# OBERON puts the runtime's symbol files ahead of the host install's, so the
# program is checked against the runtime it links with.
VOC_APP		= OBERON=$(VOC_EXPORT_DIR) $(VOC)

voc-prog.stamp: $(VOC_APP_MODS:%=$(SRC_DIR)/%.Mod) \
                $(VOC_EXPORT_DIR)/voc-runtime.stamp
	$(VERBOSE)built=$$(cat $(VOC_EXPORT_DIR)/platform); \
	  test "$$built" = "$(VOC_PLATFORM)" || { echo "voc-runtime is built for" \
	    "VOC_PLATFORM=$$built, not $(VOC_PLATFORM)" >&2; exit 1; }
	$(if $(VOC_MODULES),$(VERBOSE)$(VOC_APP) -Ss $(VOC_MODULES:%=$(SRC_DIR)/%.Mod))
	$(VERBOSE)$(VOC_APP) -Sm $(SRC_DIR)/$(VOC_MAIN).Mod
	$(VERBOSE)touch $@

$(VOC_APP_MODS:%=%.c): voc-prog.stamp ;
