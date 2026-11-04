local isAndroid, _ = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")

local function probeDevice()
    if isAndroid then
        return require("device/android/device")
    end

    -- GZreader: the Nook 1st Edition (Android 1.5 underneath, but GZreader runs
    -- as a Linux program there, like on a Kindle; platform/nook/gzreader.sh)
    if os.getenv("GZ_DEVICE") == "nook1" or lfs.attributes("/sys/devices/platform/bravo-vfb", "mode") then
        return require("device/nook/device")
    end
    -- and the Nook Simple Touch (its e-ink driver's page flip setting)
    if os.getenv("GZ_DEVICE") == "nooktouch" or lfs.attributes("/sys/class/graphics/fb0/pgflip_refresh", "mode") then
        return require("device/nook/touch")
    end

    local kindle_test_stat = lfs.attributes("/proc/usid")
    if kindle_test_stat then
        return require("device/kindle/device")
    end

    local kobo_test_stat = lfs.attributes("/bin/kobo_config.sh") or lfs.attributes("/usr/bin/hwdetect.sh") or lfs.attributes("/usr/bin/hwdetect")
    if kobo_test_stat then
        return require("device/kobo/device")
    end

    local pbook_test_stat = lfs.attributes("/ebrmain")
    if pbook_test_stat then
        return require("device/pocketbook/device")
    end

    local remarkable_test_stat = lfs.attributes("/usr/bin/xochitl")
    if remarkable_test_stat then
        return require("device/remarkable/device")
    end

    local sony_prstux_test_stat = lfs.attributes("/etc/PRSTUX")
    if sony_prstux_test_stat then
        return require("device/sony-prstux/device")
    end

    local cervantes_test_stat = lfs.attributes("/usr/bin/ntxinfo")
    if cervantes_test_stat then
        return require("device/cervantes/device")
    end

    -- add new ports here:
    --
    -- if --[[ implement a proper test instead --]] false then
    --     return require("device/newport/device")
    -- end

    if util.loadSDL3() then
        return require("device/sdl/device")
    end

    error("Could not find hardware abstraction for this platform. If you are trying to run the emulator, please ensure SDL is installed.")
end

local dev = probeDevice()
dev:init()
return dev
