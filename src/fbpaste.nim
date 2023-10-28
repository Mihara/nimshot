import std/[posix, exitprocs]
import pixie
import linuxfb

#[
    This blits a pixie image to the framebuffer as directly as feasible.
]#

const targetWidth* = 640
const targetHeight* = 480

var fd: cint
var mapPtr: pointer = nil
var fix_info: fb_fix_screeninfo
var var_info: fb_var_screeninfo
var backup_var_info: fb_var_screeninfo

let blankImage* = newImage(targetHeight, targetWidth)
blankImage.fill("#000000")

# Needs a forward declaration.
proc blitImage*(img: Image)

proc cleanupFb() =

    blitImage(blankImage)
    discard munmap(mapPtr, fix_info.smem_len.cint)
    discard ioctl(fd, FBIOPUT_VSCREENINFO, addr backup_var_info)
    discard fd.close()

proc initFb() =
    fd = open("/dev/fb0", O_RDWR)

    discard ioctl(fd, FBIOGET_FSCREENINFO, addr fix_info)
    discard ioctl(fd, FBIOGET_VSCREENINFO, addr var_info)

    # Save a backup, we'll be setting it back later.
    discard ioctl(fd, FBIOGET_VSCREENINFO, addr backup_var_info)

    # For debugging:
    #let dbg = repr(fix_info) & "\n" & repr(var_info)
    #writeFile("/mnt/mmc/debug.log", dbg)

    # We're working in 32 bits and setting this mode deliberately,
    # but generally we can handle both 32 bit and 16 bit now.

    var_info.bits_per_pixel = 32
    var_info.xres_virtual = targetWidth
    var_info.yres_virtual = targetHeight

    discard ioctl(fd, FBIOPUT_VSCREENINFO, addr var_info)

    # Debugging:
    # discard ioctl(fd, FBIOGET_VSCREENINFO, addr var_info)
    #let dbg = repr(fix_info) & "\n" & repr(var_info)
    #writeFile("/mnt/mmc/debug.log", dbg)

    mapPtr = mmap(nil, fix_info.smem_len.int, PROT_READ or PROT_WRITE,
                MAP_SHARED, fd, 0)

    addExitProc(cleanupFb)

func colorTo565(c: ColorRGBX): uint16 {.inline.} =
    let color = c.rgba
    result = ((color.r.uint16 and
                    0b11111000) shl 8) or ((color.g.uint16 and
                            0b11111100) shl 3) or (
                    color.b.uint16 shr 3)

func colorTo32bit(c: ColorRGBX): uint32 {.inline.} =
    let color = c.rgba
    result = ((color.b.uint32 shl 16) or (color.g.uint32 shl 8) or (
            color.r.uint32)) and 0x00ffffff.uint32

# This is abstracted away so that I don't have to repeat it myself.
# The compiler repeats this loop anyway, which is probably faster in the long run anyway.
template blitLoop(p: untyped, pixel: untyped) =
    for y in 0 .. img.height:
        if y >= var_info.yres.int:
            continue
        for x in 0 .. img.width:
            if x >= var_info.xres.int:
                continue
            p[((y * var_info.xres.int) + x).int] = pixel(img[x, y])

proc blitImage*(img: Image) =

    if mapPtr == nil:
        initFb()

    case var_info.bits_per_pixel
    of 16:
        let fbPtr = cast[ptr UncheckedArray[uint16]](mapPtr)
        blitLoop(fbPtr, colorTo565)
    of 32:
        let fbPtr = cast[ptr UncheckedArray[uint32]](mapPtr)
        blitLoop(fbPtr, colorTo32bit)
    else:
        echo "How the hell."
        quit(QuitFailure)
