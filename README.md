# Nimshot - a *very* specialized tool for Anbernic RG35XX

[Nimshot](https://github.com/mihara/nimshot): Convert screenshots taken on your Anbernic RG35XX into rom images right on the device itself.

## Why?

While everyone uses [Skraper](https://www.skraper.net/) to produce metadata for their rom collections, I've had nothing but trouble with it.

+ It is very slow for sufficiently large collections.
+ I wanted to use [these XML definitions](https://github.com/timault/Garlic-Os-Skraper-) with it, but the Linux version produces empty screenshots when used with custom definitions for whatever reason.
+ It is in general not well-behaved and painful to use.
+ The screenshots themselves are occasionally horridly compressed JPG files.
+ To top it all off, it couldn't identify a large portion of my roms.

I eventually set Scraper to just download the screenshots themselves and then set up a processing script with ImageMagick, which would do the requisite stretching and overlaying for me to match the skin I selected. This worked passably well and covered about a third of my collection, so that obviously wasn't enough.

Then I came up with the idea to take screenshots for all the roms that Skraper couldn't identify on the device itself, and cooked up a Python script which would automatically identify which rom a given screenshot applies to and run the ImageMagick bash processing script on it. This worked well too, but eventually I was fed up with pulling the card to run it every time.

Fortunately, RG35XX is a sufficiently fast device to do that sort of thing natively, and this program lets you do this as painlessly as possible.

It should be usable on any variant of RG35XX Linux, provided the general layout of roms and their image directories matches GarlicOS, and its RetroArch is set up to save screenshots the same way.

## Installation, configuration and usage

### What exactly does it do

1. Nimshot will go through every file in your `Screenshots` directory, and attempt to identify which rom they were taken from.
2. If the rom it relates to is found, the screenshot will be resized to fit the 640x480 screen of RG35XX vertically, positioned along the right edge, left edge, or in the center, (as per the settings in `nimshot.cfg`) and then a PNG image the configuration specifies will be overlaid on it, before saving the result to the right `Imgs` directory.
3. The original screenshot will be deleted when that is done.

RetroArch in its default GarlicOS configuration only saves the rom filename in the screenshot filename, neither its location nor extension are available. `Ms. Pacman.gg` and `Ms. Pacman.smc` would produce the same screenshot filename. In such cases, the screenshot is ignored and not touched.

With GarlicOS launcher in particular, `Ms. Pacman (GG).gg` and `Ms. Pacman (SNES).smc` look the same in the launcher, -- that is, names get cut off at the first `(` or `[` -- but have different filenames, and this was how I've been getting around that for roms duplicated between different consoles.

Nimshot can also delete `Imgs/<xxx>.png` files for which roms no longer exist, but that's a completely separate function.

### Installation

1. Unpack `nimshot.zip` from the Releases page to wherever your `APPS` live.
2. Open `nimshot.cfg` in your favorite text editor and verify the paths are what you want them to be. The configuration file is commented and tells you what each option means, but it does require your attention, as by default it's configured for a single-card installation.
3. Keep `gradient.png`, replace it with [a different mask you like](https://github.com/timault/Garlic-Os-Skraper-), or remove it entirely if you don't want a mask to be applied.

You will end up with two new entries in your `APPS`, both of which should be self-explanatory.

### Caveats

+ I am not responsible for it eating the contents of your SD card, which *should* be impossible, but probably isn't.
+ If you don't want the screenshots to be applied to roms, move them out of `Screenshots` *before* running Nimshot! Dingux Commander is an essential tool when using Nimshot, especially because it allows you to preview the screenshots taken.
+ Multiple screenshots from the same rom will overwrite each other, normally in the order they were taken, though that isn't actually guaranteed. If this is a concern, clear out the unwanted screenshots first.
+ In case of a serious misconfiguration, Nimshot may fail before it can tell you why did it fail. To debug such issues, try to run it through `adb shell` and see what the error message is, if anything.
+ Nimshot only works on screenshots produced by RetroArch. Screenshots made by the Screenshot Daemon are named differently, and will not be applied automatically, so you're mostly on your own for `PORTS`. If you manually rename those screenshots to match those of RetroArch, they will be found just fine.
+ It is assumed that screenshot pixels are square, or close enough that you wouldn't notice. This is, unfortunately, not necessarily the case -- specifically, in case of SNES and Amiga screenshots in certain graphics modes, you may end up with a very distorted image. Nimshot attempts to handle such screenshots specially, but there's no guarantee I caught every case. If you trip over a case it does not handle, please make a screenshot and send it to me.

## Compiling from source

If you don't want to tack on any more features, just don't bother, it's a bit of a pain. Otherwise, read on.

Nimshot is written in [Nim](https://nim-lang.org/), which I would describe to the uninitiated as "C for Python programmers" -- it's a lot more than that, but that's the selling point in my opinion. The build scripts currently only work on Linux, and if you want to compile on Windows or OSX, you're mostly on your own, though there's no reason it shouldn't be possible.

You need an installation of Nim version 2.0.0 or newer. You should be able to run Nimshot locally by compiling with `nimble build`, provided you're not touching the framebuffer-involving parts, (`-d:useFB`) which is why they're hidden behind a compile flag.

Two different methods of compiling for RG35XX are available:

### musl toolchain

This produces a static binary, which should also run on flavors of Linux other than GarlicOS.

+ `nimble toolchain` will download and install a musl-cc compiler.
+ `nimble muslRelease` will produce a binary in packaging/APPS/nimshot
+ `nimble push` will push it to `/mnt/mmc/Roms/APPS/nimshot/` over ADB, assuming you have that set up.
+ `nimble package` will package a release.

### uclibc docker toolchain

This involves Docker, and uses the same compiler everyone else does when developing for RG35XX from a docker image I specially made to contain the Nim compiler as well. Actual advantages turn out to be nonexistent, however: the resulting dynamically compiled binary is the same size as the static binary built with musl, which is why I'm not using this method when building the distribution. Still, this is there for completeness.

+ `nimble dockerRelease` will produce a binary in packaging/APPS/nimshot while automatically pulling down the right docker image to do it.
+ `nimble push` will push it to `/mnt/mmc/Roms/APPS/nimshot/` over ADB, assuming you have that set up.
+ `nimble package` will package a release.

## License

This program is released under the terms of [MIT License](LICENSE).
