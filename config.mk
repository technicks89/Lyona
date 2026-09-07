VERSION = 2026.08.0-beta.1

PREFIX ?= /usr/local
MANPREFIX ?= ${PREFIX}/share/man
XSESSIONSDIR ?= /usr/share/xsessions
PKG_CONFIG ?= pkg-config

XINERAMALIBS  = -lXinerama
XINERAMAFLAGS = -DXINERAMA

PKG_MODULES = x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res fontconfig freetype2
INCS = $(shell ${PKG_CONFIG} --cflags ${PKG_MODULES})
LIBS = $(shell ${PKG_CONFIG} --libs ${PKG_MODULES}) ${KVMLIB}

OPTIMISATIONS ?= -O2
NATIVE_OPTIMISATIONS ?= -O3 -march=native -mtune=native -flto=auto

CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -D_FORTIFY_SOURCE=2 \
	-DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-deprecated-declarations \
	-Wformat -Wformat-security -fstack-protector-strong -fPIE
LDFLAGS += -pie -Wl,-z,relro,-z,now
LDLIBS += ${LIBS}

CC ?= cc
