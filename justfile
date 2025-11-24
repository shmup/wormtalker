# wormboard build and run commands

# build the windows executable
build:
    zig build

# build release version
release:
    zig build -Doptimize=ReleaseSafe

# run with wine (via flatpak)
wine: build
    wine zig-out/bin/wormboard.exe
