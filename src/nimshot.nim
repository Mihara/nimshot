
import std/[os, parsecfg, strtabs, strutils, parseopt]
import pixie

const NimblePkgVersion {.strdefine.}: string = "0.0.0"
const useFB {.booldefine.}: bool = false

import fbpaste

when useFB:

    var font: Font
    var fontStroke: Font

    const fontSize = 22
    const fontColor = "#fc8c14"
    const fontOutline = "#000000"
    const outlineSize = 1.0

    const txtMarginX = 16
    const txtMarginY = 16

    const maxLines = toInt((targetHeight - txtMarginY*2) / fontSize) - 1

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
    when useFB:
        screenBuffer.add(s)

proc drawText(img: Image, s: string) =
    when useFB:

        # Why does drawing text with an outline have to be so complicated.
        const boundingBox = vec2(targetWidth - txtMarginX*2,
                targetHeight-txtMarginY*2)
        const textStart = translate(vec2(txtMarginX, txtMarginY))

        let txt = font.typeset(s, boundingBox, wrap = false)
        let strk = fontStroke.typeset(s, boundingBox, wrap = false)
        img.strokeText(strk, textStart, outlineSize)
        img.fillText(txt, textStart)

    discard

proc showConsole(pause: bool = true, clear: bool = false) =
    when useFB:
        let textBuffer = newImage(targetWidth, targetHeight)
        textBuffer.fill("#000000")
        let start = max(0, screenBuffer.len - maxLines)
        textBuffer.drawText(join(screenBuffer[start .. min(screenBuffer.len-1,
                start+maxLines-1)], "\n"))
        blitImage(textBuffer)
        if pause:
            sleep(2000)
        if clear:
            screenBuffer = @[]
    discard

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

    # Dirty hack: Try to save distorted SNES, Amiga and PSX screenshots by doubling lines,
    # through remembering specific sizes of screenshots where pixels are not square.
    if (sourceImage.width == 512 and sourceImage.height == 224) or (
            sourceImage.width == 512 and sourceImage.height == 239) or (
            sourceImage.width == 720 and sourceImage.height == 270) or (
                    sourceImage.width == 640 and sourceImage.height == 240):
        sourceImage = sourceImage.resize(sourceImage.width,
                sourceImage.height*2)
    # Turns out, vertically doubling modes also exist.
    # I sure hope there isn't an arcade game with this exact resolution.
    if (sourceImage.width == 256 and sourceImage.height == 448):
        sourceImage = sourceImage.resize(sourceImage.width*2,
                sourceImage.height)

    let
        # We explicilty fit into something four times as wide as the screen,
        # so as to only fit on vertical.
        (newWidth, newHeight) = fitInto(sourceImage.width.float,
            sourceImage.height.float, targetWidth.float * 4, targetHeight.float)
        screenshot = sourceImage.resize(toInt(newWidth), toInt(newHeight))

    var
        canvas = newImage(targetWidth, targetHeight)

    # Fill canvas with black.
    canvas.fill(rgba(0, 0, 0, 255))

    # Paste the resized screenshot at the edge desired.
    # In theory it should be possible to scale and translate in one operation.
    # In practice I can't be bothered enough to figure that out.
    let position = case position
        of Right: translate(vec2((targetWidth-screenshot.width).float32, 0.0))
        of Left: translate(vec2(0.0, 0.0))
        of Center: translate(vec2(((targetWidth-screenshot.width) / 2).float32, 0.0))

    canvas.draw(screenshot, position)

    # Paste the mask over that.
    if maskImage != nil:
        canvas.draw(maskImage, topLeftCorner)

    result = canvas.encodeImage(FileFormat.PngFormat)

    when useFB:
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

    when useFB:

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
                let chunks = rsplit(filename, '-', 2, )

                if len(chunks) == 3 and len(chunks[1]) == 6 and len(chunks[
                        2]) == 6:

                    let romName = chunks[0]

                    if romNames.hasKey(romName):

                        print "* " & filename & ext

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
    showConsole()
