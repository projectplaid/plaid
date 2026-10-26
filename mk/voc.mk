# Settings shared by BID packages built with voc (Vishap Oberon): voc
# translates Oberon to C on the host, BID compiles the C for L4Re.
# Included before $(L4DIR)/mk/lib.mk or prog.mk.

VOC		?= $(VOC_ROOT)/install/bin/voc
VOC_PLATFORM	?= l4re

# pkg/voc-runtime installs its headers and symbol files here, next to the
# library itself, for programs to translate and compile against.
VOC_EXPORT_DIR	= $(OBJ_BASE)/lib/$(subst -,/,$(SYSTEM))/voc

# The runtime C must agree with the Platform variant it is built with.
ifeq ($(VOC_PLATFORM),l4re)
DEFINES		+= -DVOC_L4RE
endif

# voc's generated C trips most of WARNINGS_FULL.
WARNINGS	= $(WARNINGS_MINIMAL)
