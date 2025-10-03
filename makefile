all: zwmcmd zwm

zwm: 
	zig build-exe src/zwm.zig -lc -lX11 -lXft -I/usr/include/freetype2
zwmcmd: 
	zig build-exe src/zwmcmd.zig -lc -lX11 -lXft -I/usr/include/freetype2

clean: 
	rm -f zwm zwmcmd