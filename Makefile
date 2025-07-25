# Makefile - requires GNU make
#
# Copyright (c) 2018-2025, Arm Limited.
# SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception

srcdir = .
prefix = /usr
bindir = $(prefix)/bin
libdir = $(prefix)/lib
includedir = $(prefix)/include

# Configure these in config.mk, do not make changes in this file.
SUBS = math string networking fp
HOST_CC ?= cc
HOST_CFLAGS = -std=c99 -O2
HOST_LDFLAGS =
HOST_LDLIBS =
EMULATOR =
CPPFLAGS =
CFLAGS = -std=c99 -O2
CFLAGS_SHARED = -fPIC
CFLAGS_ALL = -Ibuild/include $(CPPFLAGS) $(CFLAGS)
LDFLAGS =
LDLIBS =
AR = $(CROSS_COMPILE)ar
RANLIB = $(CROSS_COMPILE)ranlib
INSTALL = install
FP_SUBDIR = none
TEST_BIN_FLAGS = -static

# Detect OS.
# Assume Unix environment: Linux, Darwin, or Msys.
OS := $(shell uname -s)
OS := $(patsubst MSYS%,Msys,$(OS))
OS := $(patsubst MINGW64%,Mingw64,$(OS))

# Following math dependencies can be adjusted in config file
# if necessary, e.g. for Msys.
libm-libs = -lm
libc-libs = -lc
mpfr-libs = -lmpfr
gmp-libs = -lgmp
mpc-libs = -lmpc

all:

-include config.mk

$(foreach sub,$(SUBS),$(eval include $(srcdir)/$(sub)/Dir.mk))

# Required targets of subproject foo:
#   all-foo
#   check-foo
#   clean-foo
#   install-foo
# Required make variables of subproject foo:
#   foo-files: Built files (all in build/).
# Make variables used by subproject foo:
#   foo-...: Variables defined in foo/Dir.mk or by config.mk.

all: $(SUBS:%=all-%)

ALL_FILES = $(foreach sub,$(SUBS),$($(sub)-files))
DIRS = $(sort $(patsubst %/,%,$(dir $(ALL_FILES))))
$(ALL_FILES): | $(DIRS)
$(DIRS):
	mkdir -p $@

$(filter %.os,$(ALL_FILES)): CFLAGS_ALL += $(CFLAGS_SHARED)

build/%.o: $(srcdir)/%.S
	$(CC) $(CFLAGS_ALL) -c -o $@ $<

build/%.o: $(srcdir)/%.c
	$(CC) $(CFLAGS_ALL) -c -o $@ $<

build/%.os: $(srcdir)/%.S
	$(CC) $(CFLAGS_ALL) -c -o $@ $<

build/%.os: $(srcdir)/%.c
	$(CC) $(CFLAGS_ALL) -c -o $@ $<

clean: $(SUBS:%=clean-%)
	rm -rf build

distclean: clean
	rm -f config.mk

INSTALL_DIRS = $(bindir) $(libdir) $(includedir)

$(INSTALL_DIRS):
	mkdir -p $@

$(bindir)/%: build/bin/% | $$(@D)
	$(INSTALL) $< $@

$(libdir)/%.so: build/lib/%.so | $$(@D)
	$(INSTALL) $< $@

$(libdir)/%: build/lib/% | $$(@D)
	$(INSTALL) -m 644 $< $@

$(includedir)/%: build/include/% | $$(@D)
	$(INSTALL) -m 644 $< $@

install: $(SUBS:%=install-%)

check: $(SUBS:%=check-%)

.PHONY: all clean distclean install check
