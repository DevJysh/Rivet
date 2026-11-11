# Rivet's build. You need the Goose compiler and a C compiler.
#
#   make GOOSE=/path/to/goose     build ./rivet
#   make test                     run the smoke tests and the GUI tests
#   sudo make install             install to /usr/local/bin (PREFIX=/usr for /usr/bin)
#
# Goose is https://github.com/aardappel/goose; build it with CMake first.

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
	install -Dm755 rivet "$(DESTDIR)$(PREFIX)/bin/rivet"
	install -Dm755 gui/rivet-gui "$(DESTDIR)$(PREFIX)/bin/rivet-gui"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/rivet" "$(DESTDIR)$(PREFIX)/bin/rivet-gui"

clean:
	rm -f rivet

.PHONY: all test install uninstall clean
