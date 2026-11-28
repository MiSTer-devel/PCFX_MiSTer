# [NEC PC-FX](https://en.wikipedia.org/wiki/PC-FX) core for [MISTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

This is an emulator of the NEC PC-FX video game console.


## Hardware Requirements
SDRAM of any size is required.  (Clock rate is ~86 MHz.)


## Features
* CUE+BIN and CHD format support
* Internal backup (save) and external FX-BMP RAM
* Automatic backup RAM mounted for each game
* Load an external FX-BMP ROM
* Two game controllers


## Installation

- Build my fork of [Main\_MiSTer, branch pcfx](https://github.com/ReverendGumby/Main_MiSTer/tree/pcfx) (adds CD support).  Or, use the pre-built binary in `releases/pcfx/`.
- Copy files to the SD card:
   - `MiSTer` (main binary) to `/` (root)
   - Latest *.rbf: from `releases/` to `_Console/`
   - PC-FX ROM BIOS to `games/PCFX/boot.rom`

Core tested with ROM `pcfx.rom` (MD5 sum 08e36edbea28a017f79f8d4f7ff9b6d7).  The shortintro patch from [PC-FX\_Bios\_Patches](https://github.com/pcfx-devel/PC-FX_Bios_Patches.git) also works.


## Usage

When you load a CD, a .sav file of the same name as the CD is automatically mounted and loaded as internal backup RAM.  An empty, formatted RAM is created if needed.

If the MiSTer user LED[0] turns on, the core has encountered a fatal error:

- CPU: NMI (Non-Maskabable Interrupt) taken
- CPU: HALT instruction executed


## Development status

### Phase 1: Make it work (current)

The CPU is definitely not cycle-accurate.  Available documentation is not consistent or clear enough for me to figure out all details of the 5-stage pipeline and its interlocks.

Original hardware has three async. DRAMs that operate in parallel: the system RAM and the two KING RAMs.  All three are emulated using the MiSTer SDRAM module.  To support this, I wrote a multi-bank SDRAM controller.  Each DRAM is mapped to a separate SDRAM bank; because accesses to different banks can be interleaved, we can approximate parallel DRAM access.  The KING RAMs source BG video data at pixel clock rate, and so they are given priority over system RAM.  As such, CPU memory timing is not accurately reproduced.

Where documentation for major subsystems was lacking (e.g., HuC6271 RAINBOW), the software multi-system emulator [Mednafen](https://mednafen.github.io) was referenced to fill the gaps.

### Games

- Playable
   - [Return To Zork](https://en.wikipedia.org/wiki/Return_to_Zork)
- Unknown
   - .. everything else


## TODOs

- Video
   - HuC6261 (NEW Iron Guanyin)
      - YUV chroma key
   - Huc6272 (KING)
      - BG subscreens
      - Some color formats
   - Analog output, direct video output
- Audio (SOUNDBOX)
   - PSG (wavetable synthesis)
   - Output mixer
- CD
   - Audio track (CD-DA) playback
   - Subcode support
- MiSTer
   - Upstream PCFX to Main\_MiSTer
