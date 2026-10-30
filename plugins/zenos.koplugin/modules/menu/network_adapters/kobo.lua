-- GZreader: Kindle only; ZenOS's Kobo Wi-Fi adapter isn't included.
return {
    isSupported = function() return false end,
    new = function() return nil end,
    install = function() end,
}
