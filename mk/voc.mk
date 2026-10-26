# Settings shared by BID packages built with voc (Vishap Oberon): voc
# translates Oberon to C on the host, BID compiles the C for L4Re.
# Included before $(L4DIR)/mk/lib.mk or prog.mk.

VOC		?= $(VOC_ROOT)/install/bin/voc
VOC_PLATFORM	?= l4re

# pkg/voc-runtime and the Oberon libraries (mk/voc-lib.mk) install their
# headers and symbol files here, next to the libraries themselves, for
# later packages to translate and compile against.
VOC_EXPORT_DIR	= $(OBJ_BASE)/lib/$(subst -,/,$(SYSTEM))/voc

# Translate against this package's own symbol files first, then the
# installed libraries', ahead of the host install's.
VOC_TRANSLATE	= OBERON=".;$(VOC_EXPORT_DIR)" $(VOC)

# Oberon libraries this package imports, besides the runtime (VOC_LIBS, by
# package name), and the stamps their installs leave.
REQUIRES_LIBS	+= voc-runtime $(VOC_LIBS)
VOC_DEP_STAMPS	= $(VOC_EXPORT_DIR)/voc-runtime.stamp \
		  $(VOC_LIBS:%=$(VOC_EXPORT_DIR)/%.stamp)

# Recipe line: fail unless voc-runtime was built for this VOC_PLATFORM.
define voc_check_platform
	$(VERBOSE)built=$$(cat $(VOC_EXPORT_DIR)/platform); \
	  test "$$built" = "$(VOC_PLATFORM)" || { echo "voc-runtime is built for" \
	    "VOC_PLATFORM=$$built, not $(VOC_PLATFORM)" >&2; exit 1; }
endef

# The runtime C must agree with the Platform variant it is built with.
ifeq ($(VOC_PLATFORM),l4re)
DEFINES		+= -DVOC_L4RE
endif

# voc's generated C trips most of WARNINGS_FULL.
WARNINGS	= $(WARNINGS_MINIMAL)
