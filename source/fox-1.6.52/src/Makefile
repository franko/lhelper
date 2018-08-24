include source-files.mak

DEFS += -DWIN32=1 \
  -DPACKAGE_NAME=\"fox\" -DPACKAGE_TARNAME=\"fox\" -DPACKAGE_VERSION=\"1.6.52\" \
  -DPACKAGE_STRING=\"fox\ 1.6.52\" -DPACKAGE_BUGREPORT=\"jeroen@fox-toolkit.com\" \
  -DPACKAGE_URL=\"\" -DPACKAGE=\"fox\" -DVERSION=\"1.6.52\" \
  -DNDEBUG -DDLL_EXPORT -DPIC

# can define -DHAVE_GL_H to enable opengl

FOX_LIBRARY = libfox16.a

INCLUDES += -I../include

CXXCOMPILE = $(CXX) $(CXXFLAGS) $(DEFS) $(INCLUDES)

FOX_OBJ_FILES := $(FOX_SOURCE_FILES:%.cpp=%.o)
DEP_FILES := $(FOX_SOURCE_FILES:%.cpp=.deps/%.P)

DEPS_MAGIC := $(shell mkdir .deps > /dev/null 2>&1 || :)

.PHONY: clean all

all: $(FOX_LIBRARY)

$(FOX_LIBRARY): $(FOX_OBJ_FILES)
	ar cr $@ $(FOX_OBJ_FILES)

clean:
	rm -f *.o $(FOX_LIBRARY)

include makerules

-include $(DEP_FILES)
