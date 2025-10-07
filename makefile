OS := $(shell uname -s)

ifeq ($(OS),Darwin)
	X11_INCLUDE := -I/opt/X11/include -I/opt/X11/include/freetype2
	X11_LIB := -L/opt/X11/lib
else
	X11_INCLUDE := -I/usr/include/freetype2
	X11_LIB :=
endif

ZIGFLAGS := -lc -lX11 -lXft $(X11_LIB) $(X11_INCLUDE)

all: zwmcmd zwm

zwm: 
	zig build-exe src/zwm.zig $(ZIGFLAGS)
zwmcmd: 
	zig build-exe src/zwmcmd.zig $(ZIGFLAGS)

clean: 
	rm -f zwm zwmcmd
