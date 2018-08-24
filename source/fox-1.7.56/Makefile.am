## Process this file with automake to produce Makefile.in

# For non-gcc compilers, change the options to "no-dependencies"
AUTOMAKE_OPTIONS = foreign dist-zip

SUBDIRS    = utils include lib chart doc tests shutterbug adie pathfinder calculator controlpanel windows
EXTRA_DIST = ADDITIONS AUTHORS INSTALL LICENSE LICENSE_ADDENDUM TRACING README fox.spec fox-config index.html aclocal.m4

bin_SCRIPTS = fox-config

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = fox17.pc

CLEANFILES = $(distdir).tar.gz $(distdir).zip

snapshot: dist-all
	cp $(distdir).tar.gz /home/site/ftp/pub/fox-snapshot.tar.gz
	cp $(distdir).zip /home/site/ftp/pub/fox-snapshot.zip



web: distdir
	cd $(distdir)/doc && doxygen doxygen.cfg
	cp -r $(distdir)/doc/* /home/site/html

#web: distdir
#	cp -r $(distdir)/doc/* /net/webby/html

drop: dist-all
	cp $(distdir).tar.gz /home/site/ftp/pub
	cp $(distdir).zip /home/site/ftp/pub
	sha1sum $(distdir).tar.gz >/home/site/ftp/pub/$(distdir).tar.gz.sha1sum
	sha1sum $(distdir).zip >/home/site/ftp/pub/$(distdir).zip.sha1sum
	cd /home/site/ftp/pub && ln -sf $(distdir).tar.gz fox-latest.tar.gz
	cd /home/site/ftp/pub && ln -sf $(distdir).zip fox-latest.zip
