zwm: src/zwm.zig zwmcmd
	zig build-exe src/zwm.zig -lc -lX11 -lXft -I/usr/include/freetype2
zwmcmd: src/zwmcmd.zig
	zig build-exe src/zwmcmd.zig -lc -lX11 -lXft -I/usr/include/freetype2
