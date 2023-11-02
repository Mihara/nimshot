# Package

version       = "0.1.6"
author        = "Eugene Medvedev"
description   = "A very specialized tool for RG35XX"
license       = "MIT"
srcDir        = "src"
bin           = @["nimshot"]

# Dependencies

requires "nim >= 2.0.0"
requires "pixie >= 5.0.6"
requires "linuxfb >= 0.1.0"

# Tasks

# We're already requiring nim >= 2.0.0, so we can assume that 'distros' is available.
import os

task toolchain, "Acquire the relevant musl.cc toolchain.":
  exec("wget -O /tmp/muslcc.tgz https://musl.cc/armv7l-linux-musleabihf-cross.tgz")
  exec("mkdir -p toolchain")
  exec("tar -xzvf /tmp/muslcc.tgz -C toolchain")
  exec("rm /tmp/muslcc.tgz")  

task muslRelease, "Produce a static release build through musl toolchain.":

  let
    gccExe = "toolchain/armv7l-linux-musleabihf-cross/bin/armv7l-linux-musleabihf-gcc"
    compile = join([
        "c",
        "-d:useFB",
        "-d:NimblePkgVersion=" & version,
        "-d:release",
        "-d:strip",
        "--cpu:arm",
        "--os:linux",
        "--arm.linux.gcc.exe:" & gccExe,
        "--arm.linux.gcc.linkerexe:" & gccExe,
        "--opt:speed",
        "--passL:-static",
        "--passC:-mtune=cortex-a9",
        "--passC:-mfpu=neon-fp16",
        "--passC:-march=armv7-a",
        "--out:packaging/APPS/nimshot/nimshot",
        os.joinpath(srcDir, projectName() & ".nim")
    ]," ")

  echo "=== Building for RG35XX..."
  selfExec compile

  echo "Done."


task dockerRelease, "Build a release through the docker toolchain.":
  let
    executable = "packaging/APPS/nimshot/nimshot"
    nimbleCmd = join([
      "nimble build",
      "-y",
      "-d:useFB",
      "-d:NimblePkgVersion=" & version,
      "-d:release",
      "-d:strip",
      # Notably, non-static binaries don't run through ADB shell but work when launched locally
      #"--passL:static",
      "--opt:speed",
      "--cpu:arm",
      "--os:linux",
      "--arm.linux.gcc.exe:$CC",
      "--arm.linux.gcc.linkerexe:$CC",
      "--passC:-mtune=cortex-a9",
      "--passC:-mfpu=neon-fp16",
      "--passC:-mfloat-abi=softfp",
      "--passC:-march=armv7-a",
    ]," ")
    dockerCmd = join([
      "docker run -it --rm -v ", 
      thisDir() & ":/root/workspace",
      "mihara/nim-rg35xx-toolchain", 
      "/bin/bash -ic '" & nimbleCmd & " && chown nobody:nogroup nimshot && chmod 777 nimshot'",
    ]," ")

  echo "=== Preloading dependdencies..."
  # Install dependencies locally ourselves, so the dockered compiler doesn't get them owned by root,
  # and doesn't reload them every time.
  exec("nimble install -yl --depsOnly")

  echo "=== Building for RG35XX..."
  exec(dockerCmd)
  # Then move the file where it belongs. It's still owned by nobody though...
  exec(join(["mv", bin[0], executable]," "))
  echo "Done."

task push, "Send release binary to device with ADB.":
  exec("adb push packaging/APPS/nimshot/nimshot /mnt/mmc/Roms/APPS/nimshot/nimshot")

task package, "Package a built release.":
  exec("cp README.md packaging/APPS/nimshot/README.md")
  exec("cp LICENSE packaging/APPS/nimshot/LICENSE")
  exec("rm -f build/nimshot.zip")
  exec("cd packaging && 7z a ../build/nimshot-" & version & ".zip *")
