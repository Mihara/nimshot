
import std/[os, parsecfg, strtabs, strutils, parseopt]
import pixie

const NimblePkgVersion {.strdefine.}: string = "0.0.0"

import fbpaste

var font: Font
var fontStroke: Font

const fontSize = 22
    # This was arrived at experimentally, and pixie is making it difficult
    # to calculate the actual line height in advance.
const fontLineHeight = fontSize + 10
const fontColor = "#fc8c14"
const fontOutline = black
const textBg = black
const outlineSize = 1.0

const txtMarginX = 16
const txtMarginY = 16

const maxLines = toInt(trunc((targetHeight - txtMarginY*2) / fontLineHeight))
var screenBuffer: seq[string]

type
    Location = enum
        Right, Left, Center

type
    ActionMode = enum
        Convert, Clean

func fitInto(srcWidth, srcHeight, maxWidth, maxHeight: float): tuple[
    width: float, height: float] =

    let ratio = min(maxWidth / srcWidth, maxHeight / srcHeight)
    result.width = srcWidth*ratio
    result.height = srcHeight*ratio

proc print(s: string) =
    echo s
    screenBuffer.add(s)

proc drawText(img: Image, s: string) =
    # Why does drawing text with an outline have to be so complicated.
    const boundingBox = vec2(targetWidth - txtMarginX*2,
            targetHeight-txtMarginY*2)
    const textStart = translate(vec2(txtMarginX, txtMarginY))

    let txt = font.typeset(s, boundingBox, wrap = false)
    let strk = fontStroke.typeset(s, boundingBox, wrap = false)
    img.strokeText(strk, textStart, outlineSize)
    img.fillText(txt, textStart)

proc rumble(state: bool) =
    try:
        writeFile("/sys/class/power_supply/battery/moto",
                if state: "80" else: "0")
    except IOError:
        discard


proc showConsole(pause: bool = true, clear: bool = false,
        rumble: bool = false) =
    let textBuffer = newImage(targetWidth, targetHeight)
    textBuffer.fill(textBg)
    let start = max(0, screenBuffer.len - maxLines)
    textBuffer.drawText(join(screenBuffer[start .. min(screenBuffer.len-1,
            start+maxLines-1)], "\n"))
    blitImage(textBuffer)
    const rumbleLength = 100
    if rumble:
        rumble(true)
        sleep(rumbleLength)
        rumble(false)
    if pause:
        sleep(if rumble: 2000-rumbleLength else: 2000)
    if clear:
        screenBuffer = @[]

proc forceAspect(img: Image, x: int, y: int): Image =
    result = img.resize(toInt((targetHeight/y)*x.float), targetHeight)

proc processImage(fromData: string, maskImage: Image,
    position: Location, romName: string): string =
    # Logic is like so:
    # 1. Load the image.
    # 2. Resize the image to be 480 y, while maintaining aspect ratio.
    # 3. Create a new blank black 640x480 image.
    # 4. Paste the image into the target at the configured corner.
    # 5. Paste the overlay over the image at the configured location.
    # 6. Save.

    const topLeftCorner = translate(vec2(0, 0))

    var sourceImage: Image

    try:
        sourceImage = decodeImage(fromData)
    except PixieError:
        return ""

    # Dirty hack: Try to save distorted SNES, Amiga, Atari 2600 and PSX screenshots
    # by forcing them into a specific aspect ratio, through remembering specific
    # sizes of screenshots where pixels are not square.
    # Notice that these are sizes RetroArch saves screenshots at, not necessarily actual
    # console resolutions.
    let r = (w: sourceImage.width, h: sourceImage.height)
    if r in [
        # SNES has an unusual aspect ratio (8:7) but few resolutions where pixels are not square.
        (w: 512, h: 224), (w: 256, h: 224), (w: 512, h: 239), (w: 256, h: 239),
                (w: 256, h: 448),
        # So does NES. Normally, it needs no special handling,
        # but the S-Video and such filters are implemented by doubling virtual X
        # resolution.
        (w: 602, h: 224),
        ]:
        sourceImage = sourceImage.forceAspect(8, 7)
    elif r in [
        (w: 720, h: 270), (w: 720, h: 240), # Amiga
        (w: 160, h: 210), # Atari 2600
        # PSX is rapidly emerging as the craziest platform, which will eventually
        # result in a false positive somewhere.
        (w: 368, h: 480), (w: 368, h: 240), (w: 640, h: 240), (w: 512, h: 240),
        (w: 512, h: 480), (w: 512, h: 208), (w: 512, h: 256)
        ]:
        sourceImage = sourceImage.forceAspect(4, 3)
    else:
        # Otherwise it's a normal resize that assumes square pixels.
        # We explicilty fit into something four times as wide as the screen,
        # so as to only fit on vertical.
        let
            (newWidth, newHeight) = fitInto(
                sourceImage.width.float,
                sourceImage.height.float,
                targetWidth.float * 4,
                targetHeight.float
            )
        sourceImage = sourceImage.resize(toInt(newWidth), toInt(newHeight))

    var
        canvas = newImage(targetWidth, targetHeight)

    # Fill canvas with black.
    canvas.fill(black)

    # Paste the resized screenshot at the edge desired.
    # In theory it should be possible to scale and translate in one operation.
    # In practice I can't be bothered enough to figure that out.
    let position = case position
        of Right: translate(vec2((targetWidth-sourceImage.width).float32, 0.0))
        of Left: translate(vec2(0.0, 0.0))
        of Center: translate(vec2(((targetWidth-sourceImage.width) / 2).float32, 0.0))

    canvas.draw(sourceImage, position)

    # Paste the mask over that.
    if maskImage != nil:
        canvas.draw(maskImage, topLeftCorner)

    result = canvas.encodeImage(FileFormat.PngFormat)

    # Now that we have encoded the image into PNG that will be saved,
    # we can safely draw further on it, so draw the rom name
    # before blitting.
    canvas.drawText(romName)
    blitImage(canvas)


when isMainModule:

    var cfgfile = getAppDir() / "nimshot.cfg"

    var cmdp = initOptParser(quoteShellCommand(commandLineParams()))

    var activeMode = ActionMode.Convert

    var dryRun = false

    print "Nimshot v" & NimblePkgVersion

    for kind, key, val in cmdp.getOpt():
        case kind
        of cmdArgument:
            case key
            of "clean":
                activeMode = ActionMode.Clean
            of "convert":
                activeMode = ActionMode.Convert
            else:
                print "Valid commands are: clean, convert."
                showConsole()
                quit(QuitFailure)
        of cmdLongOption, cmdShortOption:
            case key
            of "c", "config":
                cfgfile = val
            of "d", "dry-run":
                dryRun = true
        of cmdEnd: assert(false)

    print case activeMode
        of Convert: "Converting screenshots."
        of Clean: "Cleaning orphaned screenshots."

    if dryRun:
        print "Dry run, changes will not be applied."

    print "Loading config file " & cfgfile

    let
        cfg = loadConfig(cfgfile)
        roms = cfg.getSectionValue("path", "roms")
        screenshots = cfg.getSectionValue("path", "screenshots")
        position = case cfg.getSectionValue("image", "position", "right")
            of "right": Location.Right
            of "left": Location.Left
            of "center": Location.Center
            else: Location.Right
        maskFile = cfg.getSectionValue("image", "mask", "")

    font = readFont(cfg.getSectionValue("image", "font",
        "/mnt/mmc/CFW/font/Oswald-Regular.otf"))
    font.size = fontSize
    font.paint = fontColor
    fontStroke = font.copy()
    fontStroke.paint = fontOutline

    let maskImage = if len(maskFile) > 0: decodeImage(readFile(
            maskFile)) else: nil

    # Now go fish through our paths. First we need to build a table of rom filenames we know.
    var romNames = newStringTable()

    var ambiguousNames: seq[string]

    # We need to explicitly only go down one level into roms, so don't recurse.
    for (kind, path) in walkDir(roms):
        if kind == pcDir:
            for (kind, filepath) in walkDir(path):
                if kind == pcFile:

                    # Garlic counts all files as roms, so should we.
                    let (dir, name, _) = splitFile(filepath)

                    if name in ambiguousNames:
                        # Encountered a known ambiguous name, skip.
                        continue
                    if romNames.hasKey(name):
                        # Encountered a new ambiguous name.
                        romNames.del(name)
                        ambiguousNames.add(name)
                        continue

                    # Now save the path to table, adding the imgs path too.
                    romNames[name] = dir / "Imgs"

    print "Identified " & $len(romNames) & " rom entries."

    showConsole(clear = true)

    case activeMode

    of Convert:
        for (kind, shotPath) in walkDir(screenshots):
            if kind == pcFile:

                let (_, filename, ext) = splitFile(shotPath)

                if ext != ".png":
                    continue

                # Strscans is really less reliable than it should be.

                var romName = ""

                # RetroArch naming pattern.
                if (let dateChunks = rsplit(filename, '-', 2, ); len(
                        dateChunks) == 3 and len(dateChunks[1]) == 6 and len(
                        dateChunks[2]) == 6):
                    romName = dateChunks[0]
                # Screenshot Daemon naming pattern.
                elif (let numberChunks = rsplit(filename, '_', 1); len(
                        numberChunks) == 2 and len(numberChunks[1]) == 3):
                    romName = numberChunks[0]

                if romName != "" and romNames.hasKey(romName):

                    print "+ " & filename & ext

                    if dryRun:
                        continue

                    # Make sure the target images directory exists.
                    createDir(romNames[romName])
                    # Process our screenshot and save it.
                    writeFile(romNames[romName] / romName & ".png",
                            processImage(readFile(shotPath), maskImage,
                                    position, romName))
                    removeFile(shotPath)
                else:
                    if romName in ambiguousNames:
                        print "? " & filename
                    else:
                        print "- " & filename

    of Clean:
        # Now we need to go through the Imgs directories and identify files that
        # definitely do not have corresponding rom entries.
        for (kind, path) in walkDir(roms):

            if kind == pcDir:
                # Make a list of actual files Garlic would consider roms in this rom dir.
                var romFiles: seq[string]
                for (kind, romPath) in walkDir(path):
                    if kind == pcFile:
                        let (_, filename, _) = splitFile(romPath)
                        romFiles.add(filename)

                # Then go through the screenshots.
                let imgDir = path / "Imgs"
                if dirExists(imgDir):
                    for (kind, pic) in walkDir(imgDir):
                        if kind == pcFile:
                            let (_, filename, ext) = splitFile(pic)
                            if ext == ".png" and filename notin romFiles:
                                print "- " & pic[len(roms)+1 .. ^1]
                                if not dryRun:
                                    removeFile(pic)

    print "Done."
    showConsole(rumble = true)
