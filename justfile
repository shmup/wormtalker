# use bash for cross-platform compatibility
set shell := ["bash", "-c"]

exe := if os() == "windows" { "zig-out/bin/wormtalker.exe" } else { "wine zig-out/bin/wormtalker.exe" }

build:
    zig build

# build embedded mode (fat binary with all wavs compiled in)
build-embed:
    zig build -Dembed=true

# build embedded mode with ADPCM compression (~4x smaller, requires ffmpeg)
build-embed-compressed:
    zig build -Dembed=true -Dcompress=true

# build release runtime mode
release:
    zig build -Doptimize=ReleaseSafe

# build release embedded mode
release-embed:
    zig build -Doptimize=ReleaseSafe -Dembed=true

# build release embedded with ADPCM compression (~4x smaller)
release-embed-compressed:
    zig build -Doptimize=ReleaseSafe -Dembed=true -Dcompress=true

# build full explorer mode (all wav directories)
build-full:
    zig build -Dfull=true

# build release full explorer mode
release-full:
    zig build -Doptimize=ReleaseSafe -Dfull=true

# build release small (smallest binary)
release-small:
    zig build -Doptimize=ReleaseSmall

# build release small embedded
release-small-embed:
    zig build -Doptimize=ReleaseSmall -Dembed=true

# build release small embedded with compression (smallest possible)
release-small-embed-compressed:
    zig build -Doptimize=ReleaseSmall -Dembed=true -Dcompress=true

# run the executable (uses wine on non-windows)
run: build
    {{ exe }}

# run with browse flag
run-browse: build
    {{ exe }} -b

# run embedded version
run-embed: build-embed
    {{ exe }}

# run full explorer mode
run-full: build-full
    {{ exe }}

# docker builds - output goes to ./dist/
docker-build:
    MYUID=$(id -u) MYGID=$(id -g) docker compose run --rm build

docker-embed:
    MYUID=$(id -u) MYGID=$(id -g) EMBED=true docker compose run --rm build

docker-embed-compressed:
    MYUID=$(id -u) MYGID=$(id -g) EMBED=true COMPRESS=true docker compose run --rm build

docker-small:
    MYUID=$(id -u) MYGID=$(id -g) OPTIMIZE=ReleaseSmall docker compose run --rm build

docker-small-embed:
    MYUID=$(id -u) MYGID=$(id -g) OPTIMIZE=ReleaseSmall EMBED=true docker compose run --rm build

docker-small-embed-compressed:
    MYUID=$(id -u) MYGID=$(id -g) OPTIMIZE=ReleaseSmall EMBED=true COMPRESS=true docker compose run --rm build

deploy:
  @just release-small
  cp zig-out/bin/wormtalker.exe /var/www/html/worms/tools
  @just release-small-embed-compressed
  cp zig-out/bin/wormtalker.exe /var/www/html/worms/tools/wormtalker-bundled.exe
