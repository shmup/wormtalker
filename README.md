# wormtalker

a sound board for worms armageddon, named after Shit Talker v1.2 by jaundice

## build

```bash
zig build                        # runtime mode (scans worms install)
zig build -Dembed=true           # embedded mode (fat binary with wavs)
zig build -Doptimize=ReleaseSafe # release build
```

## run

```bash
./zig-out/bin/wormboard.exe      # windows
wine zig-out/bin/wormboard.exe   # linux
```

use `-b` to force the browse dialog (skip registry lookup)

## controls

- **up/down**: switch sound banks
- **1-9, 0, qwerty row**: play sounds

-----

<img width="661" height="490" alt="wormtalker screenshot" src="https://github.com/user-attachments/assets/12454a3b-695f-49ed-8c3a-50bc858b3b69" />
