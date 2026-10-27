-- hikari-chapters: which chapters are an opening, intro, ending or outro, by
-- their title. A module, not a script: hikari-skip.lua (the skip button) and
-- hikari-resume.lua (an episode counts as watched once its ending starts)
-- load it, so both read chapter titles the same way.
--
-- Usage:
--   local kinds = chapters.kinds()            -- a fresh copy, free to extend
--   chapters.classify(kinds, 'Ending')        -> the `endings` kind
--   chapters.classify(kinds, 'Intro', true)   -> `intros`, even if turned off
--
-- Decisions:
-- - The patterns are the ones uosc uses for its chapter ranges (lib/utils.lua,
--   serialize_chapter_ranges), plus the Japanese words. An opening or intro
--   only counts when another chapter follows it (`requires_next`); that is up
--   to the caller, which knows the chapter list.
-- - Endings also take `Credits`, `Credits ...` and `... Credits`, which uosc
--   does not: Crunchyroll's releases name their chapters Intro, Episode,
--   Credits (and Preview). Like ED and Ending, with or without a chapter
--   after it. `End Credits` is one of them; `Credit` alone is not (no release
--   we know of uses it), nor are `Discredits` or `Creditscene`.
-- - kinds() hands out a new table each time: hikari-skip adds the user's
--   extra patterns and its on/off options to its copy, and nobody else sees
--   them.
-- - Titles come from the file: only cut to MAX_TITLE bytes and compared with
--   patterns, never shown.

local M = {}

M.MAX_TITLE = 200

-- Order matters: the first kind whose patterns match wins. `label` is the key
-- of the skip button text in hikari-i18n.
local KINDS = {
	{
		name = 'openings', label = 'skip_opening', requires_next = true,
		patterns = {'^op ', '^op$', ' op$', '^opening$', ' opening$'},
		words = {'オープニング'},
	},
	{
		name = 'intros', label = 'skip_intro', requires_next = true,
		patterns = {'^intro$', ' intro$', '^avant$', '^prologue$'},
		words = {},
	},
	{
		name = 'endings', label = 'skip_ending',
		patterns = {'^ed ', '^ed$', ' ed$', '^ending ', '^ending$', ' ending$',
			'^credits$', '^credits ', ' credits$'},
		words = {'エンディング'},
	},
	{
		name = 'outros', label = 'skip_outro',
		patterns = {'^outro$', ' outro$', '^closing$', '^closing ', '^preview$', '^pv$'},
		words = {},
	},
}

local function copy(list)
	local out = {}
	for i, value in ipairs(list) do out[i] = value end
	return out
end

-- A fresh copy of the kinds, every one enabled.
function M.kinds()
	local out = {}
	for i, kind in ipairs(KINDS) do
		out[i] = {
			name = kind.name, label = kind.label, requires_next = kind.requires_next, enabled = true,
			patterns = copy(kind.patterns), words = copy(kind.words),
		}
	end
	return out
end

-- Kind for a chapter title, or nil. Lower-case, trimmed, cut to MAX_TITLE.
-- With `all`, kinds turned off (enabled = false) count too.
function M.classify(kinds, title, all)
	if type(title) ~= 'string' then return nil end
	local text = title:sub(1, M.MAX_TITLE):lower():gsub('^%s+', ''):gsub('%s+$', '')
	for _, kind in ipairs(kinds) do
		if kind.enabled or all then
			for _, pattern in ipairs(kind.patterns) do
				local ok, found = pcall(string.find, text, pattern)
				if ok and found then return kind end
			end
			for _, word in ipairs(kind.words) do
				if text:find(word, 1, true) then return kind end
			end
		end
	end
	return nil
end

return M
