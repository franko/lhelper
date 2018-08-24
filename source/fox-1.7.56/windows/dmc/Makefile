#
#  Top-level makefile for Digital Mars C++
#

all:
	cd ..\..\utils
	smake -fMakefile.dmc
	cd ..\lib
	smake -fMakefile.dmc
	cd ..\tests
	smake -fMakefile.dmc
	cd ..\adie
	smake -fMakefile.dmc
	cd ..\pathfinder
	smake -fMakefile.dmc
	cd ..\calculator
	smake -fMakefile.dmc
	cd ..\shutterbug
	make -fMakefile.dmc

clean:
	cd ..\..\utils
	smake -fMakefile.dmc clean
	cd ..\lib
	smake -fMakefile.dmc clean
	cd ..\tests
	smake -fMakefile.dmc clean
	cd ..\adie
	smake -fMakefile.dmc clean
	cd ..\pathfinder
	smake -fMakefile.dmc clean
	cd ..\calculator
	smake -fMakefile.dmc clean
	cd ..\shutterbug
	smake -fMakefile.dmc clean
