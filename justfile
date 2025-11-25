# use bash for cross-platform compatibility
set shell := ["bash", "-c"]

exe := if os() == "windows" { "zig-out/bin/wormtalker.exe" } else { "wine zig-out/bin/wormtalker.exe" }

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

# build release small (smallest binary)
release-small:
    zig build -Doptimize=ReleaseSmall

# build release small embedded
release-small-embed:
    zig build -Doptimize=ReleaseSmall -Dembed=true

# run the executable (uses wine on non-windows)
run: build
    {{ exe }}

# run with browse flag
run-browse: build
    {{ exe }} -b

# run embedded version
run-embed: build-embed
    {{ exe }}
