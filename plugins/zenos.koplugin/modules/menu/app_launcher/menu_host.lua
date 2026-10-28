local ZenArrangeList = require("common/ui/zen_arrange_list")

local M = {}

function M.show(opts)
    opts = opts or {}
    return ZenArrangeList.show{
        title = opts.title or "",
        item_table = opts.item_table or {},
        refresh_func = opts.refresh_func,
        allow_arrange = false,
        hide_footer_cancel = true,
        menu_mode = true,
        back_visible = opts.back_visible,
    }
end

return M
