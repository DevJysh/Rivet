# Rivet's build. You need the Goose compiler and a C compiler.
#
#   make GOOSE=/path/to/goose     build ./rivet
#   make test                     run the smoke tests and the GUI tests
#   sudo make install             install to /usr/local/bin (PREFIX=/usr for /usr/bin)
#
# Goose is https://github.com/aardappel/goose; build it with CMake first.

VERSION ?= 0.1.0
GOOSE  ?= goose
PREFIX ?= /usr/local
DESTDIR ?=

all: rivet

rivet: rivet.goose rivet.build rivet_sys.c
	$(GOOSE) build -o rivet rivet.goose

test: rivet
	sh tests/smoke.sh ./rivet
	python3 tests/gui_test.py ./rivet

install: rivet
	install -Dm755 -s rivet "$(DESTDIR)$(PREFIX)/bin/rivet"
	install -Dm755 gui/rivet-gui "$(DESTDIR)$(PREFIX)/bin/rivet-gui"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/rivet" "$(DESTDIR)$(PREFIX)/bin/rivet-gui"

clean:
	rm -f rivet
	rm -rf dist

# The release tarball: the stripped binaries, the GUI, the docs, and checksums.
dist: rivet
	rm -rf dist && mkdir -p dist/rivet-$(VERSION)
	install -m755 -s rivet dist/rivet-$(VERSION)/rivet
	install -m755 gui/rivet-gui dist/rivet-$(VERSION)/rivet-gui
	install -m644 README.md LICENSE dist/rivet-$(VERSION)/
	tar --owner=0 --group=0 --numeric-owner -C dist -czf dist/rivet-$(VERSION)-x86_64.tar.gz rivet-$(VERSION)
	cd dist && sha256sum rivet-$(VERSION)-x86_64.tar.gz > SHA256SUMS
	@cat dist/SHA256SUMS

.PHONY: all test install uninstall clean dist
