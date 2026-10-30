-- Second run after ghosts.lua: GZreader starting again (settings kept).
-- Prints the session's processes once it has started.
return {
    start = 25,
    { fn = function()
        local sid = os.getenv("GZ_SID") -- ghosts.sh's session (the emulated /proc/self can't tell)
        local p = io.popen("ps -e -o pid=,ppid=,etimes=,sid=,args= 2>/dev/null")
        local out = {}
        for line in p:lines() do
            local fields = { line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.*)$") }
            if fields[4] == sid and not fields[5]:match("^ps ") and not fields[5]:match("^sh %-c ps") then
                out[#out + 1] = string.format("  %6s %6s %5ss  %s", fields[1], fields[2], fields[3], fields[5]:sub(1, 110))
            end
        end
        p:close()
        print("[emu] PROCS after restarting (" .. #out .. ")\n" .. table.concat(out, "\n"))
    end, after = 1 },
}
