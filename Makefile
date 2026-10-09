# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

.SILENT:

include config.mk

OWNER ?= $(or $(SUDO_USER),$(USER))
USER_HOME ?= $(shell getent passwd "${OWNER}" 2>/dev/null | cut -d: -f6)
XDG_CONFIG_HOME ?= ${USER_HOME}/.config
XDG_DATA_HOME ?= ${USER_HOME}/.local/share
XDG_STATE_HOME ?= ${USER_HOME}/.local/state
DATA_DIR  := ${XDG_DATA_HOME}/lyona
CFG_DIR   := ${XDG_CONFIG_HOME}
# Shared data (cursor and GTK themes, the GRUB theme, licenses). For the system
# prefixes /usr and /usr/local it is /usr/share, as install.sh and every image
# install use: an update by a release before 2026.10.0-beta.6 runs install-system
# with no DATADIR, so this default must agree with them (#280 VM). Any other
# PREFIX keeps its data inside it, PREFIX/share.
DATADIR   ?= $(if $(filter /usr /usr/local,${PREFIX}),/usr/share,${PREFIX}/share)
SYSTEMDUSERDIR ?= ${PREFIX}/lib/systemd/user
# UPDATE-001 install provenance. The ISO build passes both through the
# environment (archiso/airootfs/root/lyona-postinstall.sh); an existing-system
# install falls back to the local checkout's own HEAD, and finally to
# "unknown" when git is unavailable -- an ISO-provisioned target has no .git.
LYONA_COMMIT ?= $(shell git -C . rev-parse HEAD 2>/dev/null || printf unknown)
LYONA_SOURCE ?= $(if $(wildcard .git),checkout,tarball)
CAPITAINE_DARK_THEME = Capitaine-Cursors
CAPITAINE_LIGHT_THEME = Capitaine-Cursors-White
CAPITAINE_LICENSE_DIR = ${DATADIR}/licenses/lyona/capitaine-cursors
GRUB_THEME_NAME = CyberRe
GRUB_THEME_LICENSE_DIR = ${DATADIR}/licenses/lyona/grub-themes
run_managed_test = if [ -n "$${DWM_TEST_WORKSPACE:-}" ] && [ -n "$${DWM_TEST_RUNNER_TOKEN:-}" ] && [ "$${TMPDIR:-}" = "$${DWM_TEST_WORKSPACE}" ] && [ -f "$${DWM_TEST_WORKSPACE}/.runner" ] && [ ! -L "$${DWM_TEST_WORKSPACE}/.runner" ] && [ "$$(cat "$${DWM_TEST_WORKSPACE}/.runner" 2>/dev/null)" = "$${DWM_TEST_RUNNER_TOKEN}" ]; then $(1); else scripts/run-tests $(1); fi

SRC = drw.c dwm.c util.c tomlparser.c config.c
OBJ = ${SRC:.c=.o}

INSTALL_COMMANDS = \
	scripts/active-audio \
	scripts/dwm-accessibility-settings \
	scripts/check-deps.sh \
	scripts/disable-powersaving \
	scripts/dwm-controlcenter \
	scripts/dwm-default-apps \
	scripts/dwm-diagnostics \
	scripts/dwm-display-profile \
	scripts/dwm-display-setup \
	scripts/dwm-keybinds \
	scripts/dwm-lock \
	scripts/dwm-lock-watch \
	scripts/dwm-panel-settings \
	scripts/dwm-quickshell-launcher \
	scripts/dwm-quickshell-controls \
	scripts/dwm-quickshell-controlcenter \
	scripts/dwm-settings-power \
	scripts/dwm-quickshell-network \
	scripts/dwm-quickshell-pointer \
	scripts/dwm-quickshell-state \
	scripts/dwm-quickshell-version-check \
	scripts/dwm-status \
	scripts/dwm-system-health \
	scripts/dwm-system-management \
	scripts/dwm-polkit \
	scripts/dwm-cursor-reload \
	scripts/dwm-xkbset \
	scripts/dwm-settings-picom \
	scripts/lyona-gtk-theme \
	scripts/lyona-release \
	scripts/dwm-screenshot \
	scripts/dwm-session-launch \
	scripts/dwm-settings \
	scripts/dwm-settings-display \
	scripts/dwm-settings-display-profiles \
	scripts/dwm-settings-input \
	scripts/dwm-settings-appearance \
	scripts/dwm-settings-font \
	scripts/dwm-settings-wallpaper \
	scripts/dwm-settings-theme \
	scripts/dwm-settings-toolkit \
	scripts/dwm-settings-provider \
	scripts/dwm-terminal \
	scripts/dwm-xdg-autostart \
	scripts/dwm-flatpak-setup \
	scripts/install-gearlever \
	scripts/lyona-appimage \
	scripts/install-herdr \
	scripts/install-mybash \
	scripts/install-topgrade \
	scripts/lyona-cachyos \
	scripts/lyona-console-theme \
	scripts/lyona-grub-theme \
	scripts/lyona-plymouth-theme \
	scripts/lyona-shell \
	scripts/lyona-update \
	scripts/lyona-update-indicator \
	scripts/lyona-update-terminal \
	scripts/lyona-version \
	scripts/lyona-weather \
	scripts/nvidia-gpu \
	scripts/nvidia-suspend-test.sh \
	scripts/nvidia-temp \
	scripts/pkg-scan.py \
	scripts/protonrestart \
	scripts/theme-apply.sh \
	scripts/webapp-create \
	scripts/webapp-launch \
	scripts/xdg-enable-autostart.sh \
	scripts/xscreensaver-setup.sh
INSTALL_COMMAND_NAMES = $(notdir ${INSTALL_COMMANDS})
# Shell code the commands source, not commands: installed to PREFIX/lib/lyona,
# beside PREFIX/bin, where a command finds it relative to itself (a checkout
# keeps it beside the scripts). Sync Sprint 12 S12-13 step 1.
INSTALL_LIBS = \
	scripts/dwm-aur.sh \
	scripts/dwm-desktop-entry.sh \
	scripts/dwm-packages.sh \
	scripts/dwm-paths.sh \
	scripts/dwm-preview.sh \
	scripts/dwm-preview-core.sh \
	scripts/dwm-proc.sh \
	scripts/dwm-quickshell-lifecycle.sh \
	scripts/dwm-simple-watch.sh \
	scripts/dwm-theme-resolve.sh \
	scripts/dwm-utils.sh \
	scripts/dwm-trust.sh \
	scripts/dwm-watchdog.sh \
	scripts/dwm-xdg.sh \
	scripts/dwm-xsettings-config.sh \
	scripts/lyona-install-verify.sh
INSTALL_LIB_NAMES = $(notdir ${INSTALL_LIBS})
# Installed by an earlier S12-13 step and no longer: the developer tool
# dev-sync-install.sh runs from a checkout, and lyona-update now sources
# lyona-install-verify.sh.
RETIRED_LIB_NAMES = dev-sync-install.sh
# Commands installed before and no longer, removed from PREFIX/bin on install:
# power-management.sh changed /etc/tlp.conf and sysctl as root, outside the
# Settings model's preview and recovery (#282); Settings > Power is the way.
RETIRED_COMMAND_NAMES = power-management.sh
# The session scripts dwm runs at login and logout, not commands: executable,
# in LIB_DIR, where dwm finds them from its own location (S12-13 step 3). Before,
# only a per-user copy existed, so an account that never ran install-user had
# no session startup at all.
INSTALL_SESSION_SCRIPTS = scripts/autostart.sh scripts/autostop.sh
INSTALL_SESSION_SCRIPT_NAMES = $(notdir ${INSTALL_SESSION_SCRIPTS})
LIB_DIR = ${PREFIX}/lib/lyona
# The Python package behind dwm-system-management (Sync Sprint 12 S12-16):
# installed to PREFIX/lib/lyona/python, where the command finds it.
PYTHON_PACKAGE = lyona_system_management
INSTALL_PYTHON = $(sort $(wildcard scripts/${PYTHON_PACKAGE}/*.py))
PYTHON_LIB_DIR = ${LIB_DIR}/python
# The shipped default TOMLs, read-only, which dwm and the theme helpers fall
# back to. In PREFIX/share/lyona, found from the executable like LIB_DIR (not
# DATADIR, which install.sh sets only at install time). S12-13 step 2.
INSTALL_DEFAULTS = config/hotkeys.toml config/themes.toml config/window-rules.toml
INSTALL_DEFAULT_NAMES = $(notdir ${INSTALL_DEFAULTS})
SHARE_DIR = ${PREFIX}/share/lyona
PRIVILEGED_HELPERS = scripts/dwm-settings-display-root scripts/dwm-system-health-root \
	scripts/lyona-update-root
PRIVILEGED_HELPER_DIR = ${PREFIX}/libexec/lyona
POLKIT_ACTIONS = config/polkit/com.lyona.settings-display.policy \
	config/polkit/com.lyona.system-health.policy \
	config/polkit/com.lyona.update.policy
# polkit does not search PREFIX-relative paths; this is a fixed system path
# regardless of PREFIX.
POLKIT_ACTIONS_DIR = /usr/share/polkit-1/actions

RELEASE_NAME = lyona-${VERSION}
RELEASE_ARCHIVE = release/${RELEASE_NAME}.tar.gz
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || printf '0')

# dwm-window-thumb captures window previews for the overview (Sync Sprint 9
# S9-01). It is a separate program, not part of the window manager, and needs
# only libX11.
THUMB = dwm-window-thumb
THUMB_LIBS = $(shell ${PKG_CONFIG} --libs x11)

# lyona-toml, the scripts' one reader of the TOML files, built on dwm's own
# parser (Sync Sprint 12 S12-14, D-20). Installed in LIB_DIR, off PATH.
TOML_TOOL = lyona-toml
# dwm-xwatch tells the state bridge which X properties changed (Sync Sprint 16
# R16-40): one watcher for every window. Installed beside lyona-toml.
XWATCH = dwm-xwatch
XWATCH_LIBS = $(shell ${PKG_CONFIG} --libs x11)

all: dwm ${THUMB} ${TOML_TOOL} ${XWATCH}

.c.o:
	${CC} ${CPPFLAGS} ${CFLAGS} -c $<

${OBJ}: config.h config.mk Makefile
drw.o: drw.h util.h
dwm.o: drw.h util.h rtconfig.h
config.o: rtconfig.h tomlparser.h util.h
util.o: util.h
tomlparser.o: tomlparser.h

config.h:
	cp config.def.h $@

dwm: check-build-deps ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS} ${LDLIBS}

${THUMB}: check-build-deps ${THUMB}.c config.mk Makefile
	${CC} ${CPPFLAGS} ${CFLAGS} -o $@ ${THUMB}.c ${LDFLAGS} ${THUMB_LIBS}

${XWATCH}: check-build-deps ${XWATCH}.c config.mk Makefile
	${CC} ${CPPFLAGS} ${CFLAGS} -o $@ ${XWATCH}.c ${LDFLAGS} ${XWATCH_LIBS}

${TOML_TOOL}: ${TOML_TOOL}.c tomlparser.o util.o tomlparser.h util.h config.mk Makefile
	${CC} ${CPPFLAGS} ${CFLAGS} -o $@ ${TOML_TOOL}.c tomlparser.o util.o ${LDFLAGS}

check-build-deps:
	@command -v "${PKG_CONFIG}" >/dev/null 2>&1 || { \
		echo "Missing required command: ${PKG_CONFIG}" >&2; \
		exit 1; \
	}
	@missing="$$(for module in ${PKG_MODULES}; do \
		"${PKG_CONFIG}" --exists "$$module" || printf '%s ' "$$module"; \
	done)"; \
	if [ -n "$$missing" ]; then \
		echo "Missing required pkg-config modules: $$missing" >&2; \
		echo "Run ./install.sh or install the matching development packages." >&2; \
		exit 1; \
	fi

clean:
	rm -f dwm ${THUMB} ${TOML_TOOL} ${XWATCH} ${OBJ} *.orig *.rej

native:
	$(MAKE) clean
	$(MAKE) OPTIMISATIONS="${NATIVE_OPTIMISATIONS}" all

install:
	if [ -z "${DESTDIR}" ] && [ "$$(id -u)" -eq 0 ] && \
		{ [ -z "${OWNER}" ] || [ "${OWNER}" = root ]; }; then \
		echo "Refusing to install user files as root. Run install-user as the target user." >&2; \
		exit 1; \
	fi
	if [ "$$(id -u)" -eq 0 ] && [ -n "${OWNER}" ] && [ "${OWNER}" != root ]; then \
		test -n "${USER_HOME}" || { echo "USER_HOME could not be determined." >&2; exit 1; }; \
		command -v runuser >/dev/null 2>&1 || { \
			echo "runuser is required to build user-owned sources without root privileges." >&2; \
			exit 1; \
		}; \
		runuser -u "${OWNER}" -- env HOME="${USER_HOME}" $(MAKE) all; \
	else \
		$(MAKE) all; \
	fi
	$(MAKE) install-system
	if [ -z "${DESTDIR}" ]; then \
		if [ "$$(id -u)" -eq 0 ]; then \
			target_user="${OWNER}"; \
			if [ -z "$$target_user" ] || [ "$$target_user" = root ]; then \
				echo "Refusing to install user files as root. Run install-user as the target user." >&2; \
				exit 1; \
			fi; \
			command -v runuser >/dev/null 2>&1 || { \
				echo "runuser is required to install user files without root privileges." >&2; \
				exit 1; \
			}; \
			target_uid="$$(id -u "$$target_user")"; \
			runuser -u "$$target_user" -- env -u DBUS_SESSION_BUS_ADDRESS \
				HOME="${USER_HOME}" XDG_RUNTIME_DIR="/run/user/$$target_uid" \
				$(MAKE) install-user \
				USER_HOME="${USER_HOME}" OWNER="$$target_user" \
				XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
				XDG_DATA_HOME="${XDG_DATA_HOME}" \
				XDG_STATE_HOME="${XDG_STATE_HOME}"; \
		else \
			$(MAKE) install-user; \
		fi; \
	else \
		echo "==> DESTDIR set; skipping user configuration."; \
	fi

install-system:
	@test -x dwm || { echo "dwm is not built. Run make before install-system." >&2; exit 1; }
	@test -x ${THUMB} || { echo "${THUMB} is not built. Run make before install-system." >&2; exit 1; }
	@test ! ${THUMB}.c -nt ${THUMB} || { echo "${THUMB} is stale. Run make before install-system." >&2; exit 1; }
	@test -x ${XWATCH} || { echo "${XWATCH} is not built. Run make before install-system." >&2; exit 1; }
	@test ! ${XWATCH}.c -nt ${XWATCH} || { echo "${XWATCH} is stale. Run make before install-system." >&2; exit 1; }
	@test -x ${TOML_TOOL} || { echo "${TOML_TOOL} is not built. Run make before install-system." >&2; exit 1; }
	@for input in ${TOML_TOOL}.c tomlparser.c tomlparser.h tomlparser.o util.c util.h util.o config.h config.mk Makefile; do \
		test ! "$$input" -nt ${TOML_TOOL} || { echo "${TOML_TOOL} is stale. Run make before install-system." >&2; exit 1; }; \
	done
	@for input in ${SRC} ${OBJ} drw.h util.h tomlparser.h rtconfig.h config.h config.mk Makefile; do \
		test -e "$$input" || { echo "dwm build input is missing: $$input. Run make before install-system." >&2; exit 1; }; \
		test ! "$$input" -nt dwm || { echo "dwm is stale. Run make before install-system." >&2; exit 1; }; \
	done
	$(MAKE) remove-legacy-shared-data
	$(MAKE) install-gtk-themes
	$(MAKE) install-cursors
	$(MAKE) install-grub-theme
	@echo ""
	@echo "==> Installing system files..."
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	install -Dm755 ${THUMB} ${DESTDIR}${PREFIX}/bin/${THUMB}
	sed "s/VERSION/${VERSION}/g" dwm.1 | install -Dm644 /dev/stdin ${DESTDIR}${MANPREFIX}/man1/dwm.1
	sed "s|@PREFIX@|${PREFIX}|g" dwm.desktop | \
		install -Dm644 /dev/stdin ${DESTDIR}${XSESSIONSDIR}/dwm.desktop
	@# The AppImage handler (#260): hidden from the launcher, used by MIME type.
	sed "s|@PREFIX@|${PREFIX}|g" lyona-appimage.desktop | \
		install -Dm644 /dev/stdin ${DESTDIR}${DATADIR}/applications/lyona-appimage.desktop
	@echo "==> Installing scripts to PATH..."
	for f in ${INSTALL_COMMANDS}; do \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename "$$f"); \
	done
	@echo "==> Installing shared shell code..."
	for f in ${INSTALL_LIBS}; do \
		install -Dm644 "$$f" ${DESTDIR}${LIB_DIR}/$$(basename "$$f"); \
	done
	@echo "==> Installing the system-management package..."
	@# The directory is lyona's: replaced whole, so a module removed in a later
	@# release does not linger.
	rm -rf ${DESTDIR}${PYTHON_LIB_DIR}/${PYTHON_PACKAGE}
	for f in ${INSTALL_PYTHON}; do \
		install -Dm644 "$$f" ${DESTDIR}${PYTHON_LIB_DIR}/${PYTHON_PACKAGE}/$$(basename "$$f"); \
	done
	@echo "==> Installing the TOML reader..."
	install -Dm755 ${TOML_TOOL} ${DESTDIR}${LIB_DIR}/${TOML_TOOL}
	install -Dm755 ${XWATCH} ${DESTDIR}${LIB_DIR}/${XWATCH}
	@echo "==> Installing session scripts..."
	for f in ${INSTALL_SESSION_SCRIPTS}; do \
		install -Dm755 "$$f" ${DESTDIR}${LIB_DIR}/$$(basename "$$f"); \
	done
	@echo "==> Installing shipped default config..."
	for f in ${INSTALL_DEFAULTS}; do \
		install -Dm644 "$$f" ${DESTDIR}${SHARE_DIR}/config/$$(basename "$$f"); \
	done
	@# lyona's lean Picom default, which dwm-settings-picom puts ahead of
	@# /etc/xdg (#244).
	install -Dm644 config/picom/picom.conf ${DESTDIR}${SHARE_DIR}/xdg/picom/picom.conf
	@# From before S12-13, these were installed as commands.
	for name in ${INSTALL_LIB_NAMES} ${RETIRED_LIB_NAMES}; do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$name; \
	done
	for name in ${RETIRED_LIB_NAMES}; do \
		rm -f ${DESTDIR}${LIB_DIR}/$$name; \
	done
	for name in ${RETIRED_COMMAND_NAMES}; do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$name; \
	done
	@echo "==> Installing privileged helpers..."
	for f in ${PRIVILEGED_HELPERS}; do \
		sed -e "s|@PREFIX@|${PREFIX}|g" -e "s|@MANPREFIX@|${MANPREFIX}|g" \
			-e "s|@DATADIR@|${DATADIR}|g" -e "s|@XSESSIONSDIR@|${XSESSIONSDIR}|g" \
			"$$f" | \
			install -Dm755 /dev/stdin ${DESTDIR}${PRIVILEGED_HELPER_DIR}/$$(basename "$$f"); \
	done
	@echo "==> Installing polkit actions..."
	for f in ${POLKIT_ACTIONS}; do \
		sed "s|@PREFIX@|${PREFIX}|g" "$$f" | \
			install -Dm644 /dev/stdin ${DESTDIR}${POLKIT_ACTIONS_DIR}/$$(basename "$$f"); \
	done
	$(MAKE) stamp-system

# Updates before 2026.10.0-beta.6 installed the shared data under PREFIX/share,
# the old DATADIR default (#280 VM). XDG_DATA_DIRS lists /usr/local/share before
# /usr/share, so those copies would shadow the ones installed now: they go. Only
# what is lyona's, and only where lyona's own license directory shows that lyona
# installed there: its GTK themes and AppImage entry, and the cursor and GRUB
# themes beside their license. A theme you installed yourself is kept, whatever
# its name. Each removal is named.
remove-legacy-shared-data:
	@legacy="${DESTDIR}${PREFIX}/share"; \
	if [ "${PREFIX}/share" = "${DATADIR}" ] || [ ! -d "$$legacy/licenses/lyona" ] || \
		[ -L "$$legacy/licenses/lyona" ]; then exit 0; fi; \
	remove() { \
		if [ -e "$$1" ] || [ -L "$$1" ]; then \
			echo "  Removing an earlier update's copy: $$1"; \
			rm -rf -- "$$1"; \
		fi; \
	}; \
	for path in "$$legacy"/themes/Lyona-*; do remove "$$path"; done; \
	remove "$$legacy/applications/lyona-appimage.desktop"; \
	if [ -d "$$legacy/licenses/lyona/capitaine-cursors" ]; then \
		remove "$$legacy/icons/${CAPITAINE_DARK_THEME}"; \
		remove "$$legacy/icons/${CAPITAINE_LIGHT_THEME}"; \
	fi; \
	if [ -d "$$legacy/licenses/lyona/grub-themes" ]; then \
		remove "$$legacy/grub/themes/${GRUB_THEME_NAME}"; \
	fi; \
	remove "$$legacy/licenses/lyona"

# Written last, and only from this target, so an install that fails partway
# through never leaves a stamp claiming success.
stamp-system:
	@echo "==> Recording system install provenance..."
	install -d -m 0755 ${DESTDIR}/etc
	temp=$$(mktemp "${DESTDIR}/etc/.lyona-release.XXXXXX"); \
	{ \
		printf 'LYONA_VERSION=%s\n' "${VERSION}"; \
		printf 'LYONA_COMMIT=%s\n' "${LYONA_COMMIT}"; \
		printf 'LYONA_SOURCE=%s\n' "${LYONA_SOURCE}"; \
		printf 'LYONA_PREFIX=%s\n' "${PREFIX}"; \
		printf 'LYONA_MANPREFIX=%s\n' "${MANPREFIX}"; \
		printf 'LYONA_DATADIR=%s\n' "${DATADIR}"; \
		printf 'LYONA_XSESSIONSDIR=%s\n' "${XSESSIONSDIR}"; \
		printf 'LYONA_INSTALL_DATE=%s\n' "$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	} >"$$temp"; \
	chmod 0644 "$$temp"; \
	mv -f "$$temp" "${DESTDIR}/etc/lyona-release"

install-gtk-themes:
	@echo "==> Generating GTK themes from the palettes..."
	mkdir -p "${DESTDIR}${DATADIR}/themes"
	scripts/lyona-gtk-theme generate-all config/themes.toml \
		"${DESTDIR}${DATADIR}/themes"

install-cursors:
	@echo "==> Installing Capitaine cursor themes..."
	rm -rf \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_LIGHT_THEME}"
	mkdir -p "${DESTDIR}${DATADIR}/icons"
	@# --no-preserve=ownership: run as root, cp -a would keep the building user's
	@# ownership, leaving system cursor themes that user could rewrite.
	cp -a --no-preserve=ownership "assets/cursors/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/"
	cp -a --no-preserve=ownership "assets/cursors/${CAPITAINE_LIGHT_THEME}" \
		"${DESTDIR}${DATADIR}/icons/"
	install -Dm644 assets/cursors/COPYING \
		"${DESTDIR}${CAPITAINE_LICENSE_DIR}/COPYING"

# Copying the theme into place changes nothing about booting; selecting it is
# a separate, reversible step in scripts/lyona-grub-theme.
install-grub-theme:
	@echo "==> Installing the ${GRUB_THEME_NAME} GRUB theme..."
	rm -rf "${DESTDIR}${DATADIR}/grub/themes/${GRUB_THEME_NAME}"
	mkdir -p "${DESTDIR}${DATADIR}/grub/themes"
	@# --no-preserve=ownership because GRUB parses theme.txt as root at boot,
	@# so it must not stay owned by the user who ran the build.
	cp -a --no-preserve=ownership "assets/grub/${GRUB_THEME_NAME}" \
		"${DESTDIR}${DATADIR}/grub/themes/"
	install -Dm644 assets/grub/LICENSE \
		"${DESTDIR}${GRUB_THEME_LICENSE_DIR}/LICENSE"

install-user:
	@test -n "${USER_HOME}" || { echo "USER_HOME could not be determined." >&2; exit 1; }
	@test "$$(id -u)" -ne 0 || { echo "Refusing to install user files as root. Run install-user as the target user." >&2; exit 1; }
	@echo "==> Installing user files for ${OWNER}..."
	if [ ! -e "${USER_HOME}/.xinitrc" ]; then \
		install -Dm644 scripts/.xinitrc "${USER_HOME}/.xinitrc"; \
	else \
		echo "  Preserving existing ${USER_HOME}/.xinitrc"; \
	fi
	@echo "==> Removing the old per-user copy of the scripts and defaults..."
	@# The system copy in ${LIB_DIR} and ${SHARE_DIR} is the only runtime source
	@# (S12-13). Both trees were replaced wholesale on every earlier install, so
	@# nothing of the user's is in them; the rest of ${DATA_DIR} is untouched.
	@# Preserve both trees whenever the checkout and data directory overlap.
	cleanup_data=1; \
	if [ -e "${DATA_DIR}" ]; then \
		checkout_path=$$(realpath .) && data_path=$$(realpath "${DATA_DIR}") || exit 1; \
		case "$${checkout_path%/}/" in "$${data_path%/}/"*) cleanup_data=0 ;; esac; \
		case "$${data_path%/}/" in "$${checkout_path%/}/"*) cleanup_data=0 ;; esac; \
	fi; \
	if [ "$$cleanup_data" -eq 1 ]; then \
		rm -rf "${DATA_DIR}/config" "${DATA_DIR}/scripts"; \
	fi
	@echo "==> Seeding application config without overwriting user files..."
	mkdir -p ${CFG_DIR}
	@# quickshell is installed wholesale below; polkit holds the system polkit
	@# actions (POLKIT_ACTIONS, @PREFIX@ unexpanded), which are never user config;
	@# picom is lyona's default, installed to SHARE_DIR/xdg and used from there:
	@# a user copy would shadow every later update of it (#244).
	for dir in config/*/; do \
		b=$$(basename "$$dir"); \
		if [ "$$b" = quickshell ] || [ "$$b" = polkit ] || [ "$$b" = picom ]; then \
			continue; \
		fi; \
		dst=${CFG_DIR}/$$b; \
		if [ -L "$$dst" ]; then \
			echo "  Preserving symlink $$dst"; \
			continue; \
		fi; \
		mkdir -p "$$dst"; \
		cp -aL -n --no-preserve=ownership "$$dir"/. "$$dst"/; \
	done
	@echo "==> Seeding dwm-scoped XDG autostart overrides..."
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
		XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS}" \
		scripts/seed-autostart-overrides.sh
	@echo "==> Replacing managed Quickshell config..."
	test -n "${CFG_DIR}"
	rm -rf "${CFG_DIR}/quickshell"
	mkdir -p "${CFG_DIR}/quickshell"
	cp -aL --no-preserve=ownership config/quickshell/. "${CFG_DIR}/quickshell"/
	@echo "==> Seeding user config (skipping existing files)..."
	mkdir -p ${CFG_DIR}/lyona
	test -f ${CFG_DIR}/lyona/hotkeys.toml || install -Dm644 config/hotkeys.toml ${CFG_DIR}/lyona/hotkeys.toml
	test -f ${CFG_DIR}/lyona/themes.toml  || install -Dm644 config/themes.toml  ${CFG_DIR}/lyona/themes.toml
	test -f ${CFG_DIR}/lyona/window-rules.toml || install -Dm644 config/window-rules.toml ${CFG_DIR}/lyona/window-rules.toml
	@# lyona-update builds releases with ~/.config/lyona/config.h (decision D-18).
	@# Only a customised checkout config.h is copied, never over an existing one;
	@# a plain copy of the default would only go stale as config.def.h changes.
	if [ -f config.h ] && ! cmp -s config.h config.def.h && [ ! -e ${CFG_DIR}/lyona/config.h ]; then \
		install -Dm644 config.h ${CFG_DIR}/lyona/config.h; \
		echo "  Copied your customised config.h to ${CFG_DIR}/lyona/config.h; lyona-update builds with it."; \
	fi
	@echo "==> Reconciling the account with this release (#273)..."
	@# The profile install.sh recorded, the defaults, the AppImage handler and
	@# the hotkeys migration: what lyona-update and install.sh both apply. Like
	@# install.sh, a failure here is a warning: the rest of the update goes on.
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" XDG_DATA_HOME="${XDG_DATA_HOME}" \
		XDG_STATE_HOME="${XDG_STATE_HOME}" scripts/lyona-reconcile-user || \
		echo "  Warning: the account's defaults were not all reconciled; run scripts/lyona-reconcile-user to try again." >&2
	@echo "==> Migrating legacy graphical-session startup..."
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" scripts/migrate-graphical-session.sh
	@echo "==> Installing Meslo font aliases..."
	mkdir -p ${CFG_DIR}/fontconfig/conf.d
	if [ ! -f ${CFG_DIR}/fontconfig/conf.d/50-meslolgs-nerd-font-aliases.conf ]; then \
		{ \
			printf '%s\n' '<?xml version="1.0"?>'; \
			printf '%s\n' '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">'; \
			printf '%s\n' '<fontconfig>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS NF</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS NF</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS NF</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '</fontconfig>'; \
		} > ${CFG_DIR}/fontconfig/conf.d/50-meslolgs-nerd-font-aliases.conf; \
	else \
		echo "  Preserving existing Meslo font alias file."; \
	fi
	# Not forced (#250): nothing above writes a font, and an alias is read when
	# a font is looked up, not cached. A plain run still rescans any font
	# directory that changed, and costs milliseconds rather than seconds.
	fc-cache >/dev/null 2>&1 || true
	@echo "==> Fixing executable permissions..."
	for dir in config/*/; do \
		b=$$(basename $$dir); \
		if [ ! -L "${CFG_DIR}/$$b" ]; then \
			find "${CFG_DIR}/$$b" \( -name '*.sh' -o -name '*.py' \) -print0 2>/dev/null | xargs -0 -r chmod +x; \
		fi; \
	done
	@echo "==> Applying initial theme convergence..."
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" scripts/theme-apply.sh || \
		echo "  Warning: initial theme convergence failed; run scripts/theme-apply.sh after logging in." >&2
	$(MAKE) stamp-user
	@echo ""
	@echo "  dwm installed successfully."
	@echo "  Log out and select 'dwm', or start with: startx"
	@echo ""

# Written last, and only from this target, so an install that fails partway
# through never leaves a stamp claiming success.
stamp-user:
	@echo "==> Recording user install provenance..."
	mkdir -p "${XDG_STATE_HOME}/lyona"
	temp=$$(mktemp "${XDG_STATE_HOME}/lyona/.install.state.XXXXXX"); \
	{ \
		printf 'LYONA_VERSION=%s\n' "${VERSION}"; \
		printf 'LYONA_COMMIT=%s\n' "${LYONA_COMMIT}"; \
		printf 'LYONA_SOURCE=%s\n' "${LYONA_SOURCE}"; \
		printf 'LYONA_DATA_DIR=%s\n' "${DATA_DIR}"; \
		printf 'LYONA_CONFIG_DIR=%s\n' "${CFG_DIR}"; \
		printf 'LYONA_SOURCE_TREE=%s\n' "$$(realpath .)"; \
		printf 'LYONA_INSTALL_DATE=%s\n' "$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	} >"$$temp"; \
	chmod 0600 "$$temp"; \
	mv -f "$$temp" "${XDG_STATE_HOME}/lyona/install.state"

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm \
		${DESTDIR}${PREFIX}/bin/${THUMB} \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		${DESTDIR}${XSESSIONSDIR}/dwm.desktop \
		${DESTDIR}${DATADIR}/applications/lyona-appimage.desktop \
		${DESTDIR}/etc/lyona-release
	rm -rf \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_LIGHT_THEME}" \
		"${DESTDIR}${CAPITAINE_LICENSE_DIR}" \
		"${DESTDIR}${DATADIR}/grub/themes/${GRUB_THEME_NAME}" \
		"${DESTDIR}${GRUB_THEME_LICENSE_DIR}"
	@# One directory per palette, so the list comes from the palettes rather
	@# than from a second copy of it that can fall out of step.
	awk '/^\[theme\./ { id = $$0; sub(/^\[theme\./, "", id); sub(/\].*$$/, "", id); print id; }' config/themes.toml \
		| while IFS= read -r id; do \
			rm -rf "${DESTDIR}${DATADIR}/themes/Lyona-$$id"; \
		done
	for name in ${INSTALL_COMMAND_NAMES} ${INSTALL_LIB_NAMES} ${RETIRED_COMMAND_NAMES}; do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$name; \
	done
	for name in ${INSTALL_LIB_NAMES} ${INSTALL_SESSION_SCRIPT_NAMES} ${RETIRED_LIB_NAMES} ${TOML_TOOL} ${XWATCH}; do \
		rm -f ${DESTDIR}${LIB_DIR}/$$name; \
	done
	rm -rf ${DESTDIR}${PYTHON_LIB_DIR}/${PYTHON_PACKAGE}
	-rmdir ${DESTDIR}${PYTHON_LIB_DIR} 2>/dev/null
	-rmdir ${DESTDIR}${LIB_DIR} 2>/dev/null
	for name in ${INSTALL_DEFAULT_NAMES}; do \
		rm -f ${DESTDIR}${SHARE_DIR}/config/$$name; \
	done
	rm -f ${DESTDIR}${SHARE_DIR}/xdg/picom/picom.conf
	-rmdir ${DESTDIR}${SHARE_DIR}/config ${DESTDIR}${SHARE_DIR}/xdg/picom \
		${DESTDIR}${SHARE_DIR}/xdg ${DESTDIR}${SHARE_DIR} 2>/dev/null
	for name in $(notdir ${PRIVILEGED_HELPERS}); do \
		rm -f ${DESTDIR}${PRIVILEGED_HELPER_DIR}/$$name; \
	done
	for name in $(notdir ${POLKIT_ACTIONS}); do \
		rm -f ${DESTDIR}${POLKIT_ACTIONS_DIR}/$$name; \
	done

# The release asset is a source archive (Sync Sprint 12 S12-19): the files git
# knows about -- tracked, plus untracked ones not ignored, which a release never
# has because lyona-release requires a clean tree -- under lyona-VERSION/.
# The prefix goes on member names only (tar's S flag): a symlink's target, such
# as the cursor themes' relative links, stays as git has it. Every mode is
# normalised to 0644 or 0755, keeping only the executable bit git records. tar
# and gzip write to temporary files, so a failure never leaves a partial
# archive. lyona-update and lyona-update-root build and install from it as a
# checkout does. It never holds a built binary, config.h or objects. Byte-for-byte
# reproducible from the same tree and SOURCE_DATE_EPOCH.
release:
	@set -eu; \
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
		{ echo "make release must run in a git checkout: the archive is git's file list" >&2; exit 1; }; \
	list="$$(mktemp)"; \
	archive_tar="$$(mktemp)"; \
	trap 'rm -f "$$list" "$$archive_tar" "${RELEASE_ARCHIVE}.partial"' EXIT; \
	git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -zu >"$$list"; \
	mkdir -p "$$(dirname -- "${RELEASE_ARCHIVE}")"; \
	if ! tar --null -T "$$list" \
		--transform 's,^,${RELEASE_NAME}/,S' \
		--sort=name \
		--mtime="@${SOURCE_DATE_EPOCH}" \
		--owner=0 --group=0 --numeric-owner \
		--mode='u=rwX,go=rX' \
		--format=gnu \
		-cf "$$archive_tar" || \
		! gzip -n -c "$$archive_tar" >"${RELEASE_ARCHIVE}.partial"; then \
		echo "make release: could not create ${RELEASE_ARCHIVE}" >&2; \
		exit 1; \
	fi; \
	mv -f -- "${RELEASE_ARCHIVE}.partial" "${RELEASE_ARCHIVE}"; \
	echo "==> Created ${RELEASE_ARCHIVE}"

# Every shell script under scripts/, found by its shebang rather than kept by
# hand (Sync Sprint 12 S12-15): a hand-kept list had missed 13, including the
# privileged dwm-settings-display-root. The sourced libraries (*.sh) start with
# a "# shellcheck shell=" line, not a shebang, so they are added by name.
HASH := \#
SHELL_SCRIPTS = $(sort $(wildcard scripts/*.sh) $(shell for f in scripts/*; do \
	[ -f "$$f" ] && head -n 1 -- "$$f" | grep -Eq '^$(HASH)!.*(/|env )(ba)?sh([[:space:]]|$$)' && \
	printf '%s\n' "$$f"; done))

check-shell:
	shellcheck install.sh ${SHELL_SCRIPTS} tests/*.sh

check-format:
	shfmt -d install.sh ${SHELL_SCRIPTS} tests/*.sh

check-session-guards:
	tests/test-autostart.sh
	tests/test-autostart-compositor.sh
	tests/test-autostart-tray-wait.sh
	tests/test-autostop.sh

check-session-migration:
	tests/test-graphical-session-migration.sh

check-webapp-launch:
	tests/test-webapp-launch.sh

check-screenshot:
	tests/test-dwm-screenshot.sh

check-release-helper:
	tests/test-release-helper.sh

# The ISO and promotion workflows' own scripts, run against stub gh.
check-release-workflows:
	@tests/test-release-workflows.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-xvfb-runtime: all
	status=0; tests/test-xvfb-runtime.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-07: the parent-bound watchdog does not poll, and the network
# and media watchers in the QML models neither drop changes nor respawn forever.
.PHONY: check-dwm-watchdog check-quickshell-watchers-xvfb check-quickshell-idle-watchers-xvfb
.PHONY: check-quickshell-state-bridge-xvfb check-quickshell-state-model-xvfb
.PHONY: check-dwm-reload-theme-xvfb check-quickshell-watcher-lifetime-xvfb
check-dwm-watchdog:
	status=0; /usr/bin/python3 tests/test-dwm-watchdog.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-watchers-xvfb:
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-quickshell-watchers-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# The full shell's watchers, idle: within 0.5 points of zero CPU. 10 s here; the
# plan's 30 s with DWM_IDLE_WATCHERS_SECONDS=30.
check-quickshell-idle-watchers-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-quickshell-idle-watchers-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# The state bridge with real dwm and windows: one rebuild per burst of events.
check-quickshell-state-bridge-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-quickshell-state-bridge-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-state-model-xvfb:
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-quickshell-state-model-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# A config reload runs theme-apply.sh only for themes.toml, start-up and SIGUSR1.
check-dwm-reload-theme-xvfb: all
	status=0; xvfb-run -a /usr/bin/python3 tests/test-dwm-reload-theme-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# No watcher outlives a Quickshell that is killed (the full shell, every Settings section).
check-quickshell-watcher-lifetime-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-quickshell-watcher-lifetime-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-06: nothing in the shell renders markup from other programs.
.PHONY: check-quickshell-plain-text check-quickshell-plain-text-xvfb
check-quickshell-plain-text:
	tests/test-quickshell-plain-text.sh

check-quickshell-plain-text-xvfb: all
	status=0; tests/test-quickshell-plain-text-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# The panel's updates-available indicator on a real shell: a connection checks,
# a click opens Settings > System, and it stays idle (Sync Sprint 15 S15-02).
.PHONY: check-quickshell-update-indicator-xvfb
check-quickshell-update-indicator-xvfb: all
	status=0; tests/test-quickshell-update-indicator-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# The clock's month calendar on a real shell: keys move it, Escape and a click
# outside close it (Sync Sprint 12 S12-20).
.PHONY: check-quickshell-calendar-xvfb
check-quickshell-calendar-xvfb: all
	status=0; tests/test-quickshell-calendar-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-05: unit tests for the TOML parser dwm uses for all three
# runtime files.
# Sync Sprint 12 S12-14: WatchedProcess, which the resident watchers share.
.PHONY: check-quickshell-watched-process-xvfb
check-quickshell-watched-process-xvfb:
	status=0; tests/test-quickshell-watched-process-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-14: every themes.toml reader sees what dwm sees.
.PHONY: check-theme-readers
check-theme-readers: ${TOML_TOOL}
	status=0; tests/test-theme-readers.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-14: lyona-toml, the scripts' reader on dwm's parser.
.PHONY: check-lyona-toml
check-lyona-toml: ${TOML_TOOL}
	status=0; tests/test-lyona-toml.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

.PHONY: check-tomlparser
check-tomlparser:
	tests/test-tomlparser.sh

# Sync Sprint 12 S12-13: dwm runs its session scripts from the install, or from
# LYONA_DEV_SCRIPTS, and never from that override as root.
.PHONY: check-session-scripts-xvfb
check-session-scripts-xvfb: all
	status=0; tests/test-session-scripts-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# Sync Sprint 12 S12-04: dwm starts with working keys whatever hotkeys.toml holds.
.PHONY: check-dwm-config-fallback
check-dwm-config-fallback: all
	status=0; tests/test-dwm-config-fallback.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

.PHONY: check-ci-parity
check-ci-parity:
	tests/test-ci-parity.sh

check-build-config:
	tests/test-configure-build.sh

check-dev-sync-install:
	tests/test-dev-sync-install.sh
	tests/test-install-cleanup.sh

check-terminal:
	tests/test-dwm-terminal.sh

check-gearlever-install:
	tests/test-install-gearlever.sh

# lyona-appimage (#260). Its fixture test skips (77) without squashfs-tools,
# except in CI, which installs it: there a skip is a failure.
check-lyona-appimage:
	tests/test-desktop-entry.sh
	tests/test-appimage-handler.sh
	@status=0; tests/test-lyona-appimage.sh || status=$$?; \
		if [ "$$status" -eq 77 ] && [ -z "$${CI:-}" ]; then exit 0; fi; \
		exit "$$status"

check-herdr-install:
	tests/test-install-herdr.sh

check-mybash-install:
	tests/test-install-mybash.sh

# Topgrade, built with cargo from a rustup toolchain (Sync Sprint 15 S15-06).
check-topgrade-install:
	tests/test-install-topgrade.sh

check-lock:
	tests/test-dwm-lock.sh

check-default-apps:
	tests/test-dwm-default-apps.sh
	tests/test-default-apps-mime-cache.sh
	tests/test-seed-default-apps.sh
	tests/test-reconcile-user.sh

check-xdg-autostart:
	tests/test-dwm-xdg-autostart.sh

check-display-profile:
	tests/test-dwm-display-profile.sh

check-display-profiles:
	/usr/bin/python3 tests/test-display-profiles.py

check-display-setup:
	tests/test-dwm-display-setup.sh

check-diagnostics:
	tests/test-dwm-diagnostics.sh

check-status:
	tests/test-dwm-status.sh

check-session-launch:
	tests/test-dwm-session-launch.sh

check-gtk-theme:
	tests/test-lyona-gtk-theme.sh

check-app-palettes:
	/usr/bin/python3 tests/test-app-palettes.py

check-qt-palette-xvfb:
	@tests/test-qt-palette-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

# dwm-window-thumb and the overview's previews (Sync Sprint 9 S9-01), wired in by
# Sync Sprint 12 S12-12: both start their own Xvfb and skip (77) without it.
.PHONY: check-window-thumb-xvfb check-overview-thumbnails-xvfb check-overview-close-xvfb
check-window-thumb-xvfb: all
	@/usr/bin/python3 tests/test-window-thumb-xvfb.py; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status
	@/usr/bin/python3 tests/test-window-thumb-staleness-xvfb.py; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-overview-thumbnails-xvfb: all
	@/usr/bin/python3 tests/test-overview-thumbnails-xvfb.py; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

# The overview's close asks the window (WM_DELETE_WINDOW through dwm's
# _NET_CLOSE_WINDOW), so a window with unsaved work can refuse (S12-12).
check-overview-close-xvfb: all
	@status=0; xvfb-run -a /usr/bin/python3 tests/test-overview-close-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

.PHONY: check-theme-apply-gtk-fallback
check-theme-apply-gtk-fallback:
	tests/test-theme-apply-gtk-fallback.sh

.PHONY: check-theme-apply-qt-palette
check-theme-apply-qt-palette:
	tests/test-theme-apply-qt-palette.sh

check-plymouth-theme:
	tests/test-lyona-plymouth-theme.sh

check-grub-theme:
	tests/test-lyona-grub-theme.sh

check-shell-contracts:
	tests/test-shell-contracts.sh

check-test-lib:
	tests/test-lib.sh

.PHONY: check-ci-schedule
check-ci-schedule:
	tests/test-ci-schedule.sh

check-dwm-roundtrips:
	tests/test-dwm-x-roundtrips.sh

.PHONY: check-dwm-floating-guards
check-dwm-floating-guards:
	tests/test-dwm-floating-guards.sh

check-monitor-tags:
	tests/test-monitor-tag-switching.sh

check-quickshell-launcher:
	tests/test-quickshell-launcher.sh

check-quickshell-network:
	tests/test-quickshell-network.sh

check-quickshell-connectivity:
	tests/test-quickshell-connectivity.sh

check-quickshell-controls:
	tests/test-quickshell-controls.sh

check-quickshell-audio:
	tests/test-quickshell-audio.sh

check-quickshell-lifecycle:
	tests/test-quickshell-lifecycle-locale.sh

check-quickshell-controlcenter:
	tests/test-quickshell-controlcenter.sh

check-quickshell-power-backend:
	tests/test-quickshell-power-backend.sh

check-quickshell-power-model:
	tests/test-quickshell-power-model.sh

check-quickshell-power: check-quickshell-power-backend check-quickshell-power-model

check-quickshell-session-actions:
	tests/test-quickshell-session-actions.sh

check-quickshell-defaults-model:
	tests/test-quickshell-defaults-model.sh

.PHONY: check-quickshell-queued-run-xvfb
check-quickshell-queued-run-xvfb:
	@tests/test-quickshell-queued-run-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

.PHONY: check-settings-display-security
check-settings-display-security:
	@tests/test-settings-display-security.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

# Root-only and container-only, like the display helper test above: the System
# Health root helper's trust and request checks (Sync Sprint 12 S12-15).
.PHONY: check-system-health-root-security
check-system-health-root-security:
	@tests/test-system-health-root-security.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

# Root-only and container-only, like the display helper test above: it runs
# lyona-update-root as root and writes system paths (Sync Sprint 12 S12-01).
.PHONY: check-update-root-backups
check-update-root-backups:
	@tests/test-lyona-update-root-backups.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-quickshell-update-model:
	tests/test-quickshell-update-model.sh

check-quickshell-appearance-model:
	tests/test-quickshell-appearance-model.sh

check-quickshell-design-system:
	tests/test-quickshell-design-system.sh

check-quickshell-large-surfaces:
	tests/test-quickshell-large-surfaces.sh

check-quickshell-large-surfaces-xvfb: all
	status=0; tests/test-quickshell-large-surfaces-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-system-management:
	tests/test-quickshell-system-management.sh

check-quickshell-system-management-xvfb: all
	status=0; tests/test-quickshell-system-management-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-system-discovery-cycle:
	status=0; tests/test-quickshell-system-discovery-cycle.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-update-ui-xvfb: all
	status=0; tests/test-quickshell-update-ui-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-health-navigation-xvfb: all
	status=0; tests/test-quickshell-health-navigation-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-information-ui-xvfb: all
	status=0; tests/test-quickshell-information-ui-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-theme-contrast: all
	status=0; tests/test-quickshell-theme-contrast-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-overview-load-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-overview-load-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# _NET_ACTIVE_WINDOW from a pager and _DWM_MONITOR_WINDOWS, with the real dwm,
# on one screen and on two Xinerama screens (#280 VM).
check-dwm-activate-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a -s "-screen 0 1024x768x24" \
		/usr/bin/python3 tests/test-dwm-activate-xvfb.py || status=$$?; \
		if [ "$$status" -ne 0 ] && [ "$$status" -ne 77 ]; then exit "$$status"; fi; \
	status=0; DWM_TEST_MONITORS=2 dbus-run-session -- xvfb-run -a \
		-s "+xinerama -screen 0 1024x768x24 -screen 1 800x600x24" \
		/usr/bin/python3 tests/test-dwm-activate-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# A monitor keeps one bar while other docks come and go (#280 VM), real dwm.
check-dwm-bar-docks-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a -s "-screen 0 1024x768x24" \
		/usr/bin/python3 tests/test-dwm-bar-docks-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-overview-keyboard-xvfb: all
	status=0; dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-overview-keyboard-xvfb.py || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-overview-xvfb: all
	status=0; tests/test-quickshell-overview-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-panel-menus: all
	tests/test-quickshell-panel-menus.sh
	dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-panel-popup.py

check-quickshell-overview: all
	tests/test-quickshell-overview.sh

check-quickshell-panel-settings:
	tests/test-quickshell-panel-settings.sh

check-accessibility:
	tests/test-dwm-accessibility-settings.sh
	tests/test-quickshell-accessibility.sh

check-quickshell-command-menu:
	tests/test-quickshell-command-menu.sh

check-quickshell-notifications:
	tests/test-quickshell-closed-popups.sh
	tests/test-quickshell-notifications.sh

check-quickshell-tray:
	tests/test-quickshell-tray.sh

check-quickshell-xdg:
	tests/test-quickshell-xdg.sh

check-cursor-reload:
	xvfb-run -a /usr/bin/python3 tests/test-cursor-reload.py

check-xkbset:
	xvfb-run -a /usr/bin/python3 tests/test-dwm-xkbset.py

check-picom:
	$(call run_managed_test,/usr/bin/python3 tests/test-picom.py)

check-picom-xvfb:
	$(call run_managed_test,/usr/bin/python3 tests/test-picom-xvfb.py)

.PHONY: check-quickshell-picom-model-xvfb
check-quickshell-picom-model-xvfb:
	@tests/test-quickshell-picom-model-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-quickshell-health-xvfb:
	tests/test-quickshell-health-xvfb.sh

check-quickshell-settings-loading:
	status=0; tests/test-quickshell-settings-loading.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-settings-responsiveness-xvfb:
	@tests/test-quickshell-settings-responsiveness-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

.PHONY: check-quickshell-wallpaper-reconcile-xvfb
check-quickshell-wallpaper-reconcile-xvfb:
	@tests/test-quickshell-wallpaper-reconcile-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-quickshell-update-progress-xvfb:
	@tests/test-quickshell-update-progress-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-quickshell-qml:
	scripts/quickshell-qmllint --root config/quickshell

check-system-health:
	tests/test-system-health.sh

check-system-management:
	/usr/bin/python3 tests/test-system-management.py

check-settings:
	tests/test-settings.sh
	tests/test-settings-input.sh

check-appearance:
	tests/test-dwm-settings-appearance.sh
	tests/test-dwm-settings-appearance-inventory.sh
	tests/test-dwm-settings-font.sh
	tests/test-dwm-settings-wallpaper.sh
	tests/test-dwm-settings-theme.sh
	tests/test-dwm-settings-toolkit.sh
	tests/test-theme-apply-install-lock.sh

check-phase5-optional-components:
	tests/test-dwm-settings-appearance.sh
	tests/test-dwm-settings-appearance-inventory.sh
	tests/test-dwm-settings-toolkit.sh
	tests/test-dwm-settings-wallpaper.sh
	tests/test-quickshell-appearance-model.sh
	tests/test-quickshell-controlcenter.sh

check-quickshell-settings-xvfb: all
	tests/test-quickshell-settings-xvfb.sh

check-desktop-smoke-xvfb: all
	tests/test-desktop-smoke-xvfb.sh

check-lightdm-config:
	tests/test-lightdm-config.sh

check-archiso:
	tests/test-arch-iso-builder.sh

check-arch-platform:
	@$(call run_managed_test,tests/test-arch-platform.sh)

check-arch-packages:
	tests/test-arch-packages.sh

# AUR use is limited to the reviewed places docs/AUR-PACKAGES.md lists (D-27).
# check-no-aur is the target's old name, kept for existing scripts.
check-aur-policy:
	tests/test-aur-policy.sh
	tests/test-dwm-aur.sh

check-no-aur: check-aur-policy

# The live medium's driver for older NVIDIA cards, against a stub chroot (Sync
# Sprint 14).
check-legacy-nvidia:
	tests/test-legacy-nvidia.sh

check-cachyos:
	tests/test-arch-cachyos.sh

check-quickshell-state:
	tests/test-quickshell-state.sh
	tests/test-dwm-properties.sh

check-quickshell-state-close:
	tests/test-quickshell-state-close.sh

check-install: check-install-manifest

check-install-manifest: all
	@set -eu; \
	stage="$$(mktemp -d)"; \
	before="$$(mktemp)"; \
	after="$$(mktemp)"; \
	actual="$$(mktemp)"; \
	expected="$$(mktemp)"; \
	trap 'rm -rf "$$stage" "$$before" "$$after" "$$actual" "$$expected"' EXIT; \
	install -Dm644 /dev/null "$$stage/pre-existing"; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$before"; \
	$(MAKE) install-system \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions; \
	{ \
		printf '%s\n' \
			pre-existing \
			usr/bin/dwm \
			usr/bin/${THUMB} \
			usr/share/man/man1/dwm.1 \
			usr/share/xsessions/dwm.desktop \
			usr/share/applications/lyona-appimage.desktop \
			etc/lyona-release; \
		for name in ${INSTALL_COMMAND_NAMES}; do \
			printf 'usr/bin/%s\n' "$$name"; \
		done; \
		for name in ${INSTALL_LIB_NAMES} ${INSTALL_SESSION_SCRIPT_NAMES} ${TOML_TOOL} ${XWATCH}; do \
			printf 'usr/lib/lyona/%s\n' "$$name"; \
		done; \
		for name in $(notdir ${INSTALL_PYTHON}); do \
			printf 'usr/lib/lyona/python/${PYTHON_PACKAGE}/%s\n' "$$name"; \
		done; \
		for name in ${INSTALL_DEFAULT_NAMES}; do \
			printf 'usr/share/lyona/config/%s\n' "$$name"; \
		done; \
		printf '%s\n' usr/share/lyona/xdg/picom/picom.conf; \
		for name in $(notdir ${PRIVILEGED_HELPERS}); do \
			printf 'usr/libexec/lyona/%s\n' "$$name"; \
		done; \
		find "assets/cursors/${CAPITAINE_DARK_THEME}" \
			\( -type f -o -type l \) \
			-printf 'usr/share/icons/${CAPITAINE_DARK_THEME}/%P\n'; \
		find "assets/cursors/${CAPITAINE_LIGHT_THEME}" \
			\( -type f -o -type l \) \
			-printf 'usr/share/icons/${CAPITAINE_LIGHT_THEME}/%P\n'; \
		awk '/^\[theme\./ { id = $$0; sub(/^\[theme\./, "", id); sub(/\].*$$/, "", id); print "usr/share/themes/Lyona-" id "/index.theme"; print "usr/share/themes/Lyona-" id "/gtk-2.0/gtkrc"; print "usr/share/themes/Lyona-" id "/gtk-3.0/gtk.css"; print "usr/share/themes/Lyona-" id "/gtk-4.0/gtk.css"; print "usr/share/themes/Lyona-" id "/qt/colors.conf"; }' config/themes.toml; \
		find "assets/grub/${GRUB_THEME_NAME}" \
			\( -type f -o -type l \) \
			-printf 'usr/share/grub/themes/${GRUB_THEME_NAME}/%P\n'; \
		printf '%s\n' \
			usr/share/licenses/lyona/capitaine-cursors/COPYING \
			usr/share/licenses/lyona/grub-themes/LICENSE; \
		for name in $(notdir ${POLKIT_ACTIONS}); do \
			printf 'usr/share/polkit-1/actions/%s\n' "$$name"; \
		done; \
	} | sort > "$$expected"; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$actual"; \
	cmp "$$expected" "$$actual"; \
	for name in dwm ${THUMB} ${INSTALL_COMMAND_NAMES}; do \
		test -x "$$stage/usr/bin/$$name"; \
	done; \
	for name in $(notdir ${PRIVILEGED_HELPERS}); do \
		test -x "$$stage/usr/libexec/lyona/$$name"; \
	done; \
	for name in ${INSTALL_SESSION_SCRIPT_NAMES} ${TOML_TOOL} ${XWATCH}; do \
		test -x "$$stage/usr/lib/lyona/$$name"; \
	done; \
	status=0; PYTHONDONTWRITEBYTECODE=1 "$$stage/usr/bin/dwm-system-management" >/dev/null 2>&1 || status=$$?; \
	test "$$status" = 2; \
	grep -Fq 'org.freedesktop.policykit.exec.path">/usr/libexec/lyona/dwm-settings-display-root' \
		"$$stage/usr/share/polkit-1/actions/com.lyona.settings-display.policy"; \
	grep -Fq 'org.freedesktop.policykit.exec.path">/usr/libexec/lyona/dwm-system-health-root' \
		"$$stage/usr/share/polkit-1/actions/com.lyona.system-health.policy"; \
	grep -Fq 'org.freedesktop.policykit.exec.path">/usr/libexec/lyona/lyona-update-root' \
		"$$stage/usr/share/polkit-1/actions/com.lyona.update.policy"; \
	grep -Fqx 'Exec=/usr/bin/dwm' \
		"$$stage/usr/share/xsessions/dwm.desktop"; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_DARK_THEME}/cursors/default"; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_LIGHT_THEME}/cursors/default"; \
	test -f "$$stage/usr/share/grub/themes/${GRUB_THEME_NAME}/theme.txt"; \
	$(MAKE) uninstall \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$after"; \
	cmp "$$before" "$$after"; \
	echo "==> Install manifest and uninstall symmetry validated."

check-live-backup-label:
	tests/test-live-backup-label.sh

check-legacy-shared-data:
	tests/test-legacy-shared-data.sh

check-install-preservation:
	tests/test-install-preservation.sh

.PHONY: check-install-multilib check-install-time-sync check-iso-install-credentials check-live-medium-cleanup \
	check-installed-helper-paths check-download-pins check-iso-install-warnings check-install-summary \
	check-lyona-shell check-gearlever-first-login check-iso-install-wifi check-install-step-timing \
	check-iso-install-mirrors check-iso-install-recovery
check-install-multilib:
	tests/test-install-multilib.sh

check-install-time-sync:
	tests/test-install-time-sync.sh

check-iso-install-credentials:
	status=0; tests/test-iso-install-credentials.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-lyona-version:
	tests/test-lyona-version.sh

check-lyona-update:
	tests/test-lyona-update.sh

# The update indicator's helper against a stub checkupdates (Sync Sprint 15
# S15-02). It reads window-rules.toml through lyona-toml (Sync Sprint 16 R16-44).
check-lyona-update-indicator: ${TOML_TOOL}
	tests/test-lyona-update-indicator.sh

# Updates in a terminal against a stub terminal, yay, pacman and flatpak (Sync
# Sprint 15 S15-03, S15-04).
check-lyona-update-terminal:
	tests/test-lyona-update-terminal.sh

# Sync Sprint 16, from the 2026-10-03 whole-repo review.
# R16-01: the live medium's passwordless sudoers rule never outlives the run.
check-live-medium-cleanup:
	tests/test-live-medium-cleanup.sh

# R16-03, R16-48: installed helpers use installed paths, and QML runs helpers
# through Commands.
check-installed-helper-paths:
	tests/test-installed-helper-paths.sh

# R16-15, R16-16: what the installers download while sudo is cached is pinned.
check-download-pins:
	tests/test-download-pins.sh

# R16-22, R16-29, R16-30: the image install's closing screen, steps and cancel.
check-iso-install-warnings:
	tests/test-iso-install-warnings.sh
	tests/test-iso-vm-guest.sh
	tests/test-first-login-keys.sh

# #237: the image installer's Wi-Fi step, against a stub iwd (busctl) and gum.
check-iso-install-wifi:
	status=0; tests/test-iso-install-wifi.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

# #249: the image installer ranks the mirrors in the user's country.
check-iso-install-mirrors:
	tests/test-iso-install-mirrors.sh

# #265, #266: the image installer applies the keymap, goes back, and recovers.
check-iso-install-recovery:
	tests/test-iso-install-recovery.sh

# #250: both install paths time each step and end with a table.
check-install-step-timing:
	tests/test-install-step-timing.sh

# R16-28: the installer's summary lists every change (a dry run; Arch only).
check-install-summary:
	@tests/test-install-summary.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

# R16-47: keybinds open the shell through lyona-shell.
check-lyona-shell:
	tests/test-lyona-shell.sh

# An image install leaves Gear Lever for the first login.
check-gearlever-first-login:
	tests/test-gearlever-first-login.sh

# The panel weather helper against a stub curl (Sync Sprint 12 S12-20).
check-lyona-weather:
	@tests/test-lyona-weather.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status

check-test-runner:
	@$(call run_managed_test,tests/test-run-tests.sh)

# The archive is reproducible, holds the sources and no build output, and builds
# on its own: extracted alone, `make all` produces dwm (S12-19).
release-check:
	@set -eu; \
	work="$$(mktemp -d)"; \
	trap 'rm -rf "$$work"' EXIT; \
	$(MAKE) release; \
	test -f "${RELEASE_ARCHIVE}"; \
	cp "${RELEASE_ARCHIVE}" "$$work/first.tar.gz"; \
	$(MAKE) release; \
	cmp "$$work/first.tar.gz" "${RELEASE_ARCHIVE}"; \
	tar -tzf "${RELEASE_ARCHIVE}" > "$$work/listing"; \
	for path in Makefile config.mk config.def.h dwm.c drw.c util.c tomlparser.c config.c rtconfig.h \
		${TOML_TOOL}.c ${THUMB}.c ${XWATCH}.c dwm.desktop install.sh scripts/dwm-system-management \
		scripts/lyona_system_management/cli.py config/themes.toml; do \
		grep -Fqx "${RELEASE_NAME}/$$path" "$$work/listing" || \
			{ echo "Release archive is missing $$path." >&2; exit 1; }; \
	done; \
	if grep -Ev '^${RELEASE_NAME}/' "$$work/listing" | grep -q .; then \
		echo "Release archive has entries outside ${RELEASE_NAME}/." >&2; exit 1; \
	fi; \
	if grep -Eq '(^|/)config\.h$$|\.o$$|^${RELEASE_NAME}/(dwm|${THUMB}|${TOML_TOOL}|${XWATCH})$$|^${RELEASE_NAME}/(release|\.git)/' \
		"$$work/listing"; then \
		echo "Release archive contains build output, local configuration or git data." >&2; \
		exit 1; \
	fi; \
	tar -tvzf "${RELEASE_ARCHIVE}" > "$$work/long-listing"; \
	if grep -F ' -> ${RELEASE_NAME}/' "$$work/long-listing" | grep -q .; then \
		echo "Release archive rewrote a symlink target." >&2; exit 1; \
	fi; \
	if awk '$$1 !~ /^(-rw-r--r--|-rwxr-xr-x|lrwxr-xr-x|lrwxrwxrwx)$$/' "$$work/long-listing" | grep -q .; then \
		echo "Release archive has a mode other than 0644 or 0755." >&2; exit 1; \
	fi; \
	tar -xzf "${RELEASE_ARCHIVE}" -C "$$work"; \
	$(MAKE) -s -C "$$work/${RELEASE_NAME}" all >/dev/null; \
	test -x "$$work/${RELEASE_NAME}/dwm"; \
	echo "==> Release archive validated: a reproducible source archive that builds."

check:
	$(MAKE) clean
	$(MAKE) all
	$(MAKE) check-shell
	$(MAKE) check-format
	$(MAKE) check-build-config
	$(MAKE) check-arch-platform
	$(MAKE) check-dev-sync-install
	$(MAKE) check-default-apps
	$(MAKE) check-ci-parity
	$(MAKE) check-xdg-autostart
	$(MAKE) check-diagnostics
	$(MAKE) check-status
	$(MAKE) check-test-lib
	$(MAKE) check-ci-schedule
	$(MAKE) check-shell-contracts
	$(MAKE) check-gtk-theme
	$(MAKE) check-app-palettes
	$(MAKE) check-qt-palette-xvfb
	$(MAKE) check-window-thumb-xvfb
	$(MAKE) check-overview-thumbnails-xvfb
	$(MAKE) check-overview-close-xvfb
	$(MAKE) check-theme-apply-gtk-fallback
	$(MAKE) check-theme-apply-qt-palette
	$(MAKE) check-plymouth-theme
	$(MAKE) check-grub-theme
	$(MAKE) check-session-launch
	$(MAKE) check-dwm-roundtrips
	$(MAKE) check-dwm-floating-guards
	$(MAKE) check-display-profile
	$(MAKE) check-display-profiles
	$(MAKE) check-display-setup
	$(MAKE) check-monitor-tags
	$(MAKE) check-quickshell-launcher
	$(MAKE) check-quickshell-controls
	$(MAKE) check-quickshell-audio
	$(MAKE) check-quickshell-controlcenter
	$(MAKE) check-quickshell-lifecycle
	$(MAKE) check-quickshell-power-backend
	$(MAKE) check-quickshell-power-model
	$(MAKE) check-quickshell-session-actions
	$(MAKE) check-quickshell-defaults-model
	$(MAKE) check-quickshell-queued-run-xvfb
	$(MAKE) check-quickshell-update-model
	$(MAKE) check-quickshell-appearance-model
	$(MAKE) check-quickshell-settings-loading
	$(MAKE) check-quickshell-settings-xvfb
	$(MAKE) check-quickshell-settings-responsiveness-xvfb
	$(MAKE) check-quickshell-update-progress-xvfb
	$(MAKE) check-quickshell-wallpaper-reconcile-xvfb
	$(MAKE) check-desktop-smoke-xvfb
	$(MAKE) check-xvfb-runtime
	$(MAKE) check-dwm-config-fallback
	$(MAKE) check-session-scripts-xvfb
	$(MAKE) check-tomlparser
	$(MAKE) check-lyona-toml
	$(MAKE) check-theme-readers
	$(MAKE) check-quickshell-watched-process-xvfb
	$(MAKE) check-quickshell-plain-text
	$(MAKE) check-quickshell-plain-text-xvfb
	$(MAKE) check-quickshell-calendar-xvfb
	$(MAKE) check-quickshell-update-indicator-xvfb
	$(MAKE) check-dwm-watchdog
	$(MAKE) check-quickshell-watchers-xvfb
	$(MAKE) check-quickshell-idle-watchers-xvfb
	$(MAKE) check-quickshell-state-bridge-xvfb
	$(MAKE) check-quickshell-state-model-xvfb
	$(MAKE) check-dwm-reload-theme-xvfb
	$(MAKE) check-quickshell-watcher-lifetime-xvfb
	$(MAKE) check-quickshell-design-system
	$(MAKE) check-quickshell-large-surfaces
	$(MAKE) check-quickshell-large-surfaces-xvfb
	$(MAKE) check-quickshell-panel-menus
	$(MAKE) check-quickshell-overview
	$(MAKE) check-quickshell-overview-xvfb
	$(MAKE) check-overview-keyboard-xvfb
	$(MAKE) check-dwm-activate-xvfb
	$(MAKE) check-dwm-bar-docks-xvfb
	$(MAKE) check-overview-load-xvfb
	$(MAKE) check-quickshell-theme-contrast
	$(MAKE) check-quickshell-panel-settings
	$(MAKE) check-accessibility
	$(MAKE) check-quickshell-command-menu
	$(MAKE) check-quickshell-qml
	$(MAKE) check-quickshell-system-management
	$(MAKE) check-quickshell-system-management-xvfb
	$(MAKE) check-quickshell-system-discovery-cycle
	$(MAKE) check-quickshell-update-ui-xvfb
	$(MAKE) check-quickshell-health-navigation-xvfb
	$(MAKE) check-quickshell-information-ui-xvfb
	$(MAKE) check-quickshell-health-xvfb
	$(MAKE) check-quickshell-notifications
	$(MAKE) check-quickshell-tray
	$(MAKE) check-quickshell-xdg
	$(MAKE) check-cursor-reload
	$(MAKE) check-xkbset
	$(MAKE) check-picom
	$(MAKE) check-picom-xvfb
	$(MAKE) check-quickshell-picom-model-xvfb
	$(MAKE) check-system-health
	$(MAKE) check-system-management
	$(MAKE) check-settings
	$(MAKE) check-appearance
	$(MAKE) check-phase5-optional-components
	$(MAKE) check-quickshell-network
	$(MAKE) check-quickshell-connectivity
	$(MAKE) check-terminal
	$(MAKE) check-gearlever-install
	$(MAKE) check-lyona-appimage
	$(MAKE) check-herdr-install
	$(MAKE) check-mybash-install
	$(MAKE) check-topgrade-install
	$(MAKE) check-lock
	$(MAKE) check-session-guards
	$(MAKE) check-session-migration
	$(MAKE) check-webapp-launch
	$(MAKE) check-screenshot
	$(MAKE) check-release-helper
	$(MAKE) check-release-workflows
	$(MAKE) check-archiso
	$(MAKE) check-cachyos
	$(MAKE) check-quickshell-state
	$(MAKE) check-quickshell-state-close
	$(MAKE) check-arch-packages
	$(MAKE) check-aur-policy
	$(MAKE) check-legacy-nvidia
	$(MAKE) check-install
	$(MAKE) check-install-preservation
	$(MAKE) check-legacy-shared-data
	$(MAKE) check-live-backup-label
	$(MAKE) check-install-multilib
	$(MAKE) check-install-time-sync
	$(MAKE) check-iso-install-credentials
	$(MAKE) check-lyona-version
	$(MAKE) check-lyona-update
	$(MAKE) check-lyona-update-indicator
	$(MAKE) check-lyona-update-terminal
	$(MAKE) check-live-medium-cleanup
	$(MAKE) check-installed-helper-paths
	$(MAKE) check-download-pins
	$(MAKE) check-iso-install-warnings
	$(MAKE) check-iso-install-wifi
	$(MAKE) check-install-step-timing
	$(MAKE) check-iso-install-mirrors
	$(MAKE) check-iso-install-recovery
	$(MAKE) check-install-summary
	$(MAKE) check-lyona-shell
	$(MAKE) check-gearlever-first-login
	$(MAKE) check-lyona-weather
	$(MAKE) check-test-runner
	$(MAKE) check-lightdm-config
	$(MAKE) release-check

.PHONY: clean all check check-accessibility check-appearance check-phase5-optional-components check-build-config check-build-deps check-default-apps check-xdg-autostart check-dev-sync-install \
	check-cursor-reload check-xkbset check-picom check-picom-xvfb \
	check-test-runner \
	check-display-profile check-display-profiles check-display-setup check-archiso check-arch-packages check-aur-policy check-no-aur check-arch-platform check-format check-install \
	check-gearlever-install check-lyona-appimage check-herdr-install check-mybash-install check-topgrade-install check-install-manifest check-install-preservation check-legacy-shared-data check-live-backup-label check-lyona-version check-lyona-update check-lock \
	check-session-guards check-session-migration check-webapp-launch check-screenshot check-release-helper check-release-workflows check-shell check-diagnostics check-status check-test-lib check-shell-contracts check-gtk-theme check-app-palettes check-qt-palette-xvfb check-plymouth-theme check-grub-theme check-session-launch check-dwm-roundtrips check-system-health check-system-management check-settings \
	check-quickshell-launcher check-quickshell-controls check-quickshell-audio check-quickshell-controlcenter check-quickshell-lifecycle check-quickshell-power check-quickshell-power-backend check-quickshell-power-model check-quickshell-session-actions check-quickshell-defaults-model check-quickshell-update-model check-quickshell-appearance-model check-quickshell-design-system check-quickshell-large-surfaces check-quickshell-large-surfaces-xvfb check-quickshell-panel-menus check-quickshell-overview check-quickshell-overview-xvfb check-overview-keyboard-xvfb check-dwm-activate-xvfb check-dwm-bar-docks-xvfb check-overview-load-xvfb check-quickshell-theme-contrast check-quickshell-panel-settings check-quickshell-command-menu check-quickshell-notifications check-quickshell-tray check-quickshell-xdg check-quickshell-health-xvfb check-quickshell-settings-loading check-quickshell-settings-xvfb check-quickshell-settings-responsiveness-xvfb check-quickshell-update-progress-xvfb check-desktop-smoke-xvfb check-quickshell-system-management check-quickshell-system-management-xvfb check-quickshell-system-discovery-cycle check-quickshell-update-ui-xvfb check-quickshell-health-navigation-xvfb check-quickshell-information-ui-xvfb check-quickshell-network check-quickshell-connectivity check-quickshell-qml check-lightdm-config check-terminal check-xvfb-runtime install install-system install-user \
	install-cursors install-grub-theme install-gtk-themes remove-legacy-shared-data stamp-system stamp-user native release release-check uninstall
