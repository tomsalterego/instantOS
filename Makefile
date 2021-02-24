PREFIX = /usr

.PHONY: all
all: install

.PHONY: install
install: install_external  install_local

# This should really be handled in a better way, because:
# - The external hotkey version might be out of sync with what is installed here
# - It makes things harder in Nix and with updating
.PHONY: install_external
install_external:
	curl -s 'https://raw.githubusercontent.com/instantOS/instantLOGO/master/description/thanks.txt'> ${DESTDIR}${PREFIX}/share/instantutils/thanks.txt
	curl -s 'https://raw.githubusercontent.com/instantOS/instantos.github.io/master/youtube/hotkeys.md' | \
		sed 's/^\([^|#]\)/    \1/g' | \
		sed 's/^##*[ ]*/ /g' >${DESTDIR}${PREFIX}/share/instantutils/keybinds

.PHONY: install_local
install_local:
	install -Dm 755 autostart.sh ${DESTDIR}${PREFIX}/bin/instantautostart
	install -Dm 755 status.sh ${DESTDIR}${PREFIX}/bin/instantstatus
	install -Dm 755 monitor.sh ${DESTDIR}${PREFIX}/bin/instantmonitor
	install -Dm 755 instantutils.sh ${DESTDIR}${PREFIX}/bin/instantutils
	install -Dm 755 installinstantos.sh ${DESTDIR}${PREFIX}/bin/installinstantos
	mkdir -p ${DESTDIR}${PREFIX}/share/instantutils
	cp -r mirrors ${DESTDIR}${PREFIX}/share/instantutils/
	cp -r setup ${DESTDIR}${PREFIX}/share/instantutils/
	find -regex './desktop/.*desktop' -exec install -Dm 644 "{}" ${DESTDIR}${PREFIX}/share/applications \;
	find -regex './programs/.*' -exec install -Dm 755 "{}" ${DESTDIR}${PREFIX}/bin/ \;
	find -regex './xorg/.*' -exec install -Dm 755 "{}" ${DESTDIR}/etc/X11/xorg.conf.d \;

