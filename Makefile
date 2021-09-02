NAME			= shasta_wrapper
CONFDIR			= /etc
LIBDIR			= /usr/share/shasta_wrapper/lib
SBINDIR			= /usr/sbin
VERSION			= 0.8.0
RELEASE			= 1

SOURCE			= src
SOURCE_ETC		= $(SOURCE)/etc
SOURCE_LIB		= $(SOURCE)/lib
SOURCE_SBIN		= $(SOURCE)/sbin
LOCALTMPDIR		= tmp

ARCHIVE_DIR		= "$(NAME)-$(VERSION)"
ARCHIVE_FILE		= "$(NAME).tar.gz"
SPEC_FILE		= "$(NAME).spec"


all: fix-perms build-spec

fix-perms:
	chmod 640 "$(SOURCE_ETC)/"*
	chmod 755 "$(SOURCE_LIB)/"*
	chmod 750 "$(SOURCE_SBIN)/"*

build-spec: 
	cp "$(SPEC_FILE).in" "$(SPEC_FILE)"
	sed -i "s|%VERSION%|$(VERSION)|g" "$(SPEC_FILE)"
	sed -i "s|%RELEASE%|$(RELEASE)|g" "$(SPEC_FILE)"
	sed -i "s|%NAME%|$(NAME)|g" "$(SPEC_FILE)"
	sed -i "s|%SBINDIR%|$(SBINDIR)|g" "$(SPEC_FILE)"
	sed -i "s|%CONFDIR%|$(CONFDIR)|g" "$(SPEC_FILE)"
	sed -i "s|%LIBDIR%|$(LIBDIR)|g" "$(SPEC_FILE)"

dist: clean all
	mkdir -p "$(LOCALTMPDIR)/$(ARCHIVE_DIR)"
	rsync -Carv --exclude --delete "$(LOCALTMPDIR)" ./ "$(LOCALTMPDIR)/$(ARCHIVE_DIR)/"
	tar -C "$(LOCALTMPDIR)" -czvf "$(ARCHIVE_FILE)" "$(ARCHIVE_DIR)"

rpm: dist
	rpmbuild -ta "$(ARCHIVE_FILE)"

clean:
	rm -rf $(LOCALTMPDIR)
	rm -f $(SPEC_FILE) 
	rm -f $(ARCHIVE_FILE)

install: all
	mkdir -p "$(DESTDIR)$(CONFDIR)"
	mkdir -p "$(DESTDIR)$(SBINDIR)"
	mkdir -p "$(DESTDIR)$(LIBDIR)"
	cp -ar "$(SOURCE_ETC)/"* "$(DESTDIR)$(CONFDIR)/"
	cp -ar "$(SOURCE_SBIN)/"* "$(DESTDIR)$(SBINDIR)/"
	cp -ar "$(SOURCE_LIB)/"* "$(DESTDIR)$(LIBDIR)/"
	sed -i 's|%LIBDIR%|$(LIBDIR)|g' "$(DESTDIR)$(SBINDIR)/shasta"
	sed -i 's|%VERSION%|$(VERSION)|g' "$(DESTDIR)$(SBINDIR)/shasta"
	sed -i 's|%RELEASE%|$(RELEASE)|g' "$(DESTDIR)$(SBINDIR)/shasta"

test:
	SHASTACMD_LIBDIR=./src/lib ./src/sbin/shasta regression build
