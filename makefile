main: src/main.zig client
	zig build-exe src/main.zig -lc -lX11 -lXft -I/usr/include/freetype2
client: src/client.zig
	zig build-exe src/client.zig -lc -lX11 -lXft -I/usr/include/freetype2 