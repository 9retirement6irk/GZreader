local function apply_empty_library()
    local FileChooser = require("ui/widget/filechooser")
    if FileChooser._zen_empty_library_patched then return end
    FileChooser._zen_empty_library_patched = true

    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Size = require("ui/size")
    local paths = require("common/paths")
    local _ = require("gettext")
    local orig_updatePageInfo = FileChooser.updatePageInfo

    function FileChooser:updatePageInfo(...)
        -- (GZreader's shelves say it themselves, on the top shelf)
        local empty = self.name == "filemanager" and paths.isHomeRoot(self.path) and not self._gz_shelves
        if empty then
            for _i, item in ipairs(self.item_table) do
                if not item.is_go_up then empty = false; break end
            end
        end
        if empty and self._gz_empty_recheck_path ~= self.path then
            -- GZreader: an empty list here can be a listing that hasn't been
            -- built yet. If the folder has books, list it again instead of
            -- asking for a home folder.
            local lfs = require("libs/libkoreader-lfs")
            local has_files = false
            local ok_dir, iter, dir_obj = pcall(lfs.dir, self.path)
            if ok_dir then
                for name in iter, dir_obj do
                    if name:sub(1, 1) ~= "." then has_files = true; break end
                end
            end
            if has_files then
                self._gz_empty_recheck_path = self.path -- once per folder: no refresh loop
                local UIManager = require("ui/uimanager")
                UIManager:nextTick(function()
                    if type(self.refreshPath) == "function" then self:refreshPath() end
                end)
                empty = false
            end
        end
        if empty then
            -- GZreader: the home folder is always the GZreader folder, so no
            -- "Set home folder" button here (until 1.23.11); just what to do
            local width = self.inner_dimen and self.inner_dimen.w or self.width
            local content = VerticalGroup:new{
                TextBoxWidget:new{
                    text = _("No books yet"),
                    face = Font:getFace("smallinfofont"),
                    width = width,
                    alignment = "center",
                },
                VerticalSpan:new{ width = Size.padding.large },
                TextBoxWidget:new{
                    text = _("Books you download from the Catalog tab appear here."),
                    face = Font:getFace("cfont", 16),
                    width = width - 2 * Size.padding.large,
                    alignment = "center",
                },
            }
            local height = self.available_height or self.inner_dimen.h - self.others_height
            table.insert(self.item_group, CenterContainer:new{
                dimen = Geom:new{
                    w = width,
                    h = math.max(content:getSize().h, height - self.item_group:getSize().h),
                },
                content,
            })
            self.item_group:resetLayout()
        end
        return orig_updatePageInfo(self, ...)
    end
end

return apply_empty_library
