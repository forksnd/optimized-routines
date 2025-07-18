# Makefile fragment - requires GNU make
#
# Copyright (c) 2019-2025, Arm Limited.
# SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception

S := $(srcdir)/networking
B := build/networking

ifeq ($(ARCH),)
all-networking check-networking install-networking clean-networking:
	@echo "*** Please set ARCH in config.mk. ***"
	@exit 1
else

networking-lib-srcs := $(wildcard $(S)/*.[cS]) $(wildcard $(S)/$(ARCH)/*.[cS])
networking-test-srcs := $(wildcard $(S)/test/*.c)

networking-includes := $(patsubst $(S)/%,build/%,$(wildcard $(S)/include/*.h))

networking-libs := \
	build/lib/libnetworking.so \
	build/lib/libnetworking.a \

networking-tools := \
	build/bin/test/chksum

networking-lib-objs := $(patsubst $(S)/%,$(B)/%.o,$(basename $(networking-lib-srcs)))
networking-test-objs := $(patsubst $(S)/%,$(B)/%.o,$(basename $(networking-test-srcs)))

networking-objs := \
	$(networking-lib-objs) \
	$(networking-lib-objs:%.o=%.os) \
	$(networking-test-objs) \

networking-files := \
	$(networking-objs) \
	$(networking-libs) \
	$(networking-tools) \
	$(networking-includes) \

all-networking: $(networking-libs) $(networking-tools) $(networking-includes)

$(networking-objs): $(networking-includes)
$(networking-objs): CFLAGS_ALL += $(networking-cflags)

build/lib/libnetworking.so: $(networking-lib-objs:%.o=%.os)
	$(CC) $(CFLAGS_ALL) $(LDFLAGS) -shared -o $@ $^

build/lib/libnetworking.a: $(networking-lib-objs)
	rm -f $@
	$(AR) rc $@ $^
	$(RANLIB) $@

build/bin/test/%: $(B)/test/%.o build/lib/libnetworking.a
	$(CC) $(CFLAGS_ALL) $(LDFLAGS) $(TEST_BIN_FLAGS) -o $@ $^ $(LDLIBS)

build/include/%.h: $(S)/include/%.h
	cp $< $@

build/bin/%.sh: $(S)/test/%.sh
	cp $< $@

check-networking: $(networking-tools)
	$(EMULATOR) build/bin/test/chksum -i simple
	$(EMULATOR) build/bin/test/chksum -i scalar
	$(EMULATOR) build/bin/test/chksum -i simd || true # simd is not always available

install-networking: \
 $(networking-libs:build/lib/%=$(libdir)/%) \
 $(networking-includes:build/include/%=$(includedir)/%)

clean-networking:
	rm -f $(networking-files)
endif

.PHONY: all-networking check-networking install-networking clean-networking
