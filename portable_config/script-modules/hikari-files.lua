-- hikari-files: writing a file whole or not at all. A module, not a script:
-- the scripts that save a choice (hikari-palettes, hikari-subs, hikari-upscale,
-- hikari-language, hikari-skip) or a state (hikari-update) load it, so all of
-- them write the same careful way.
--
-- Usage:
--   files.write_file_atomic(path, content)    -> true, or false and the error
--
-- Decisions:
-- - Through `<path>.tmp` and a rename, so a crash never leaves half a file.
-- - A leftover .tmp (or a link planted there) is removed first, so io.open
--   creates a new file instead of writing through whatever was there. One mpv
--   writes each of these files, so the fixed .tmp name is enough (the resume
--   list and the AniSkip cache, written by every mpv window, use names of
--   their own).

local M = {}

function M.write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	os.remove(tmp)
	local file, err = io.open(tmp, 'wb')
	if not file then return false, err end
	local ok, write_err = file:write(content)
	local closed, close_err = file:close()
	if not ok or not closed then
		os.remove(tmp)
		return false, write_err or close_err
	end
	local renamed, rename_err = os.rename(tmp, path)
	if not renamed then
		-- On Windows rename() won't replace an existing file: remove it and retry.
		os.remove(path)
		renamed, rename_err = os.rename(tmp, path)
	end
	if not renamed then
		os.remove(tmp)
		return false, rename_err
	end
	return true
end

return M
