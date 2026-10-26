# Build plaid's BID packages against the L4Re build in $(L4RE_OBJDIR), in
# dependency order: libraries first, then the programs that link them.
# Variables such as VOC_PLATFORM=... pass through to every package.

O	?= $(L4RE_OBJDIR)

PKGS	= pkg/voc-runtime \
	  apps/hello \
	  apps/l4-echo

all clean:
	@for p in $(PKGS); do $(MAKE) -C $$p O=$(O) $@ || exit; done

.PHONY: all clean
