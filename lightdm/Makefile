.PHONY: install print-config

LIGHTDM_DIR = $(DESTDIR)/etc/lightdm
LIGHTDM_CONF = $(LIGHTDM_DIR)/lightdm.conf
PIXMAPS_DIR = $(DESTDIR)/usr/share/pixmaps
THEMES_DIR = $(DESTDIR)/usr/share/themes
GREETER_THEME = Lyona-tokyonight
LIGHTDM_SEAT_SECTION ?= Seat:*
LIGHTDM_GREETER_SESSION ?= lightdm-slick-greeter
LIGHTDM_USER_SESSION ?= dwm
LIGHTDM_SESSION_WRAPPER ?= /etc/lightdm/Xsession
LIGHTDM_LOGIND_CHECK ?= true

print-config:
	@if [ "$(LIGHTDM_LOGIND_CHECK)" = true ]; then \
		printf '%s\n' '[LightDM]'; \
		printf '%s\n' 'logind-check-graphical=true'; \
		printf '\n'; \
	fi; \
	printf '[%s]\n' "$(LIGHTDM_SEAT_SECTION)"; \
	printf 'greeter-session=%s\n' "$(LIGHTDM_GREETER_SESSION)"; \
	printf 'user-session=%s\n' "$(LIGHTDM_USER_SESSION)"; \
	if [ -n "$(LIGHTDM_SESSION_WRAPPER)" ]; then \
		printf 'session-wrapper=%s\n' "$(LIGHTDM_SESSION_WRAPPER)"; \
	fi

install:
	tmp=$$(mktemp); \
	trap 'rm -f "$$tmp"' EXIT; \
	$(MAKE) --no-print-directory print-config >"$$tmp"; \
	if [ -f $(LIGHTDM_CONF) ] && ! cmp -s "$$tmp" $(LIGHTDM_CONF); then \
		cp -a $(LIGHTDM_CONF) $(LIGHTDM_CONF).lyona.$$(date +%Y%m%d%H%M%S).bak; \
	fi; \
	install -Dm644 "$$tmp"                           $(LIGHTDM_CONF)
	install -Dm644 slick-greeter.conf                $(LIGHTDM_DIR)/slick-greeter.conf
	install -Dm644 wallpaper.jpg                     $(PIXMAPS_DIR)/lyona.jpg
	install -Dm644 ../assets/logo/lyona-icon.png     $(PIXMAPS_DIR)/lyona-logo.png
	../scripts/lyona-gtk-theme generate tokyonight ../config/themes.toml \
		$(THEMES_DIR)/$(GREETER_THEME)
	find $(THEMES_DIR)/$(GREETER_THEME) -type d -exec chmod 0755 {} +
	find $(THEMES_DIR)/$(GREETER_THEME) -type f -exec chmod 0644 {} +
