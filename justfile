set shell := ["cmd", "/c"]

# wormboard build and run commands

# build runtime mode (tiny binary, reads from worms installation)
build:
    zig build

# build embedded mode (fat binary with all wavs compiled in)
build-embed:
    zig build -Dembed=true

# build release runtime mode
release:
    zig build -Doptimize=ReleaseSafe

# build release embedded mode
release-embed:
    zig build -Doptimize=ReleaseSafe -Dembed=true

# run the executable
run: build
    zig-out\bin\wormboard.exe

# run embedded version
run-embed: build-embed
    zig-out\bin\wormboard.exe
