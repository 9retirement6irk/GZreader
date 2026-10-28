-- Preserve the full waveform unless KOReader's UI flash avoidance is enabled.
return function()
    return G_reader_settings:isTrue("avoid_flashing_ui") and "ui" or "full"
end
