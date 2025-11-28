# Root Makefile for Cupertino
# Delegates all commands to Packages/Makefile

.PHONY: help all build build-debug build-release install install-symlinks uninstall update test test-unit test-integration
.PHONY: clean distclean format lint archive bottle dev run-cli run-tui watch version b i u t c

# Default target
all:
	@$(MAKE) -C Packages all

# Help
help:
	@$(MAKE) -C Packages help

# Build targets
build:
	@$(MAKE) -C Packages build

build-debug:
	@$(MAKE) -C Packages build-debug

build-release:
	@$(MAKE) -C Packages build-release

# Install/Uninstall
install:
	@$(MAKE) -C Packages install

install-symlinks:
	@$(MAKE) -C Packages install-symlinks

uninstall:
	@$(MAKE) -C Packages uninstall

update:
	@$(MAKE) -C Packages update

# Testing
test:
	@$(MAKE) -C Packages test

test-unit:
	@$(MAKE) -C Packages test-unit

test-integration:
	@$(MAKE) -C Packages test-integration

# Cleaning
clean:
	@$(MAKE) -C Packages clean

distclean:
	@$(MAKE) -C Packages distclean

# Code quality
format:
	@$(MAKE) -C Packages format

lint:
	@$(MAKE) -C Packages lint

# Distribution
archive:
	@$(MAKE) -C Packages archive

bottle:
	@$(MAKE) -C Packages bottle

# Development
dev:
	@$(MAKE) -C Packages dev

run-cli:
	@$(MAKE) -C Packages run-cli ARGS="$(ARGS)"

run-tui:
	@$(MAKE) -C Packages run-tui ARGS="$(ARGS)"

watch:
	@$(MAKE) -C Packages watch

# Version
version:
	@$(MAKE) -C Packages version

# Shortcuts
b:
	@$(MAKE) -C Packages b

i:
	@$(MAKE) -C Packages i

u:
	@$(MAKE) -C Packages u

t:
	@$(MAKE) -C Packages t

c:
	@$(MAKE) -C Packages c
