# kavrhgen

This thing converts a KiCAD netlist with an AVR in it into a C header file with pin definitions.

When I make a little circuit board with an AVR, I always have to transfer the pinout to a header file so I can work with the pins nicely without having to write pin numbers every time. But this task of transferring pin descriptions from schematic to source code is boring and error-prone. After all, I already have the information "what is connected to what" stored on my disk. So I wrote this litte script to generate my `pinning.h` directly from my KiCAD netlist.

The script uses the names of the nets to name the defines in the generated header file. So, if you connect a label to an IO, the script assumes you want to name the pin exactly like you named the label.

## Project status

I've just written this script because I needed a header file. So, don't expect it to be perfect but I think it should cover most cases you'd want to use it for. Maybe someday I'll include support for other MCUs.

## Usage

    kavrhgen [options] NETLIST

outputs a `pinning.h` by default. Look at `kavrhgen --help` for all command line options available.

## Features

- For each pin, a define with the DDR, PORT and PIN register is generated along with one for the bit number or bit mask.
- If there is more than one AVR in the schematic, the first one in the netlist is picked. This can be overridden by explicitly specifying the reference of the AVR (like `kavrhgen -r U2 netlist.net`).
- If a net is connected to multiple pins, there will be a primitive disambiguation by appending `_A`, `_B`, `_C` and so on.
- If you don't want some pins to appear in the header file, simply include a comma-seperated list with the `-i` flag. Pin numbers and pin names both work, so things like `-i 31,PD5,12` are okay.

## Configuration

The configuration file (`kavrhgen.conf` by default) allows some options for customization:

- `IgnoreNets` contains a list with nets that won't lead to a define. Otherwise, connecting ground to an IO would effect defines for a signal namend `GND`.
- `Capitalize` controls if the defines should be all caps.
- `InvertSymbol` is the string by which KiCAD's `~` is replaced.
- `DDRFormat`, `PORTFormat`, `PINFormat` and `BitFormat` are `printf`-like formatting strings controlling what the names of the defines for the registers and the for the bit. You may find my format a bit confusing, so you can change that.
- `UseBitMasks` controls whether the header file contains masks like `(1 << 5)` or just plain bit numbers like `5`.

## Limitations

- It only works with KiCAD and I only tested it with Eeschema 2015-02-26 BZR 5453.
- It only works with AVRs. This might actually change as there are some other MCU families I like to use.
- Because the script does not fully understand the netlist and only parses the parts it need with convoluted regexes, some Eeschema update might actually break it.
- The logic which pin is an IO and which is not actually depends on your KiCAD library. If you have some strange pin names in your schematic symbols, then the script can have problems figuring out what you want.
- It does not work if you don't have a footprint assigned to the AVR.
- When there are multiple labels connected to one IO, there is just one net name in the netlist. It is pretty random what name you will get for your pin as it depends on Eeschema.

If it does not work but you think it should, please send me a example netlist so I can debug things.
