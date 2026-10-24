-- hikari-skip: "skip opening / ending" button for uosc (and suji).
--
-- While playback is inside a chapter that looks like an opening or an ending,
-- a rounded button is drawn at the bottom right, above uosc's (or suji's)
-- controls and timeline. Clicking it (or the `skip` binding) jumps to the start of the next
-- chapter. Files with no opening or ending chapters get the times from
-- AniSkip when they are anime releases (see below). Outside those ranges
-- nothing is drawn and no input is taken.
--
-- With auto_skip (off by default) the openings, the endings or both are
-- skipped on their own, once per file, with "‹ Watch opening" for a few
-- seconds to go back (see the decisions below).
--
-- mpv turns this file name into the script name `hikari_skip`, so:
--   input.conf:  <key> script-binding hikari_skip/skip
--                <key> script-binding hikari_skip/open-menu   (automatic skip)
--
-- Decisions:
-- - Chapters are classified with the same title patterns uosc uses for its
--   chapter ranges (lib/utils.lua, serialize_chapter_ranges), plus the Japanese
--   words: script-modules/hikari-chapters.lua, shared with hikari-resume.lua.
--   An opening or intro only counts when another chapter follows it.
-- - Layout is in real OSD pixels times a scale factor, like uosc does
--   (hidpi * scale, or scale_fullscreen when fullscreen or maximized), so the
--   button keeps its place above uosc's bar in any window size. The default
--   margin_bottom clears uosc's default bottom stack: timeline 40 + timeline
--   border 1 + controls margin 8 + controls 32 = 81, plus a 15 px gap.
-- - With suji: suji publishes how high its controls reach,
--   user-data/suji/margins = {bottom = N}, in OSD pixels with its own scale
--   included, the same whether its controls are shown or hidden, and deletes
--   it while turned off. When `bottom` is a number above 0, the button sits
--   that high plus SUJI_GAP times this script's scale (the 15 px gap above),
--   and margin_bottom does not count. Without it (no suji, suji turned off,
--   or 0) the button goes where margin_bottom says, as before. suji only
--   takes clicks on its row and timeline strip, below that height, so the
--   button's clicks are not shared with it.
-- - With suji 0.3.0 or newer turned on, suji draws the button, with its own
--   look: hikari draws nothing and takes no clicks, and sends
--   `show-action hikari-skip {text, command}` instead, the command being a
--   script-message-to this script (ACTION_MESSAGE) that skips as a click on
--   our own button does. The text is the same label; a new label (language,
--   kind of range, next episode) is a new show-action. `hide-action
--   hikari-skip` goes when the button would go: the range ends or changes to
--   none, the skip dismisses it, idle, a new file, and while a menu of uosc,
--   mpv's console or its context menu is open (as our own button: a click
--   there belongs to them); show-action comes again when they close. suji
--   hides it itself while a menu of its own is open and keeps it while its
--   controls are hidden, so those and the window size are left to it. suji
--   leaves it up after a click (only we know when the skip is done) and
--   swallows the second click of a double click itself, so the double-click
--   guard is not started for it. The version is user-data/suji/version (suji
--   0.3.1 or newer) or, without it, the one in the last `suji-version`
--   message (suji 0.3.0 sends only that, and only to the scripts already
--   running when it starts); the property must be text, and either needs
--   major.minor 0.3 or more. A property that is there but not valid wins
--   over the message on purpose, as in suji's API example. The property is
--   observed rather than read on file-loaded and on entering a range: mpv
--   loads the scripts at the same time, so it is often missing when this
--   script loads, and the observer is told when suji sets it; a script
--   loaded later with load-script gets its value at once (it misses that
--   file's file-loaded). Its first value comes from mpv after this script
--   has loaded, so nothing is decided while loading. mpv only tells an
--   observer when the value changes, and a suji loaded again sets the same
--   version: that case is the `suji-version` message's, which is why the
--   message stays. With neither (suji 0.3.0 started before this script), the
--   version is unknown and the button is drawn here, as with suji 0.2.x.
--   When the version stops counting while suji has our button up,
--   hide-action is sent first, so no two buttons show. suji drops its action
--   buttons when turned off and does not bring them back: when
--   user-data/suji/enabled turns true again, show-action is sent again; while
--   it is anything else (suji off or gone), the button is ours again. A
--   suji-version message (suji loaded again while playing) sends it again too.
-- - Clicks: a private input section with MBTN_LEFT is enabled only while the
--   button is visible and the pointer is over it, and disabled as soon as it
--   leaves, so every other click reaches uosc and mpv untouched. It is the
--   mechanism uosc itself uses (mp.set_key_bindings / enable_key_bindings):
--   unlike mp.add_forced_key_binding it lets us enable the section without
--   `allow-vo-dragging`, so pressing the button never starts a window drag.
--   The skip fires on button release, like a normal button, and the section
--   stays enabled until that release so the up event never leaks to an
--   input.conf MBTN_LEFT binding. After a skip done with the mouse the button
--   is gone, but the section stays enabled for one `input-doubleclick-time`
--   (the guard): the second click of a double click is swallowed there, along
--   with MBTN_LEFT_DBL, so it neither toggles fullscreen nor drags the window.
-- - The skip seeks `absolute+exact` to the next chapter's start, and the range
--   is "dismissed" so the button goes away at once even if the seek lands a
--   frame short. A dismissed range shows again when playback leaves it, goes
--   before its start, or is moved by a seek far from where the skip went. For
--   a last-chapter ending: `playlist-next` when the playlist has another
--   entry, otherwise a seek to one second before the end, so mpv finishes the
--   file the way it normally would (keep-open, idle...). With neither (no next
--   entry and no known duration) the skip does nothing.
-- - Chapter titles come from the file: they are only cut to a bounded length
--   and compared with patterns, never shown.
-- - Hidden while a menu of uosc or suji is open (user-data/uosc/menu/type,
--   user-data/suji/menu/type), mpv's console or its context menu: a click
--   there belongs to them.
-- - The label follows hikari's language (hikari-i18n) and is redrawn as soon
--   as it changes. The box is sized from the label's width: CJK and other
--   full-width characters count double.
-- - AniSkip (aniskip=yes, the default): only for a file whose chapters mark no
--   opening, intro or ending (they count even if the options turn that kind
--   off; an outro chapter does not), once
--   it has loaded, with a duration, and only when hikari-title.lua has
--   published a release with one plain episode that looks like anime
--   (user-data/hikari_title/release) for the path playing. The lookup, its
--   checks and its cache are in script-modules/hikari-aniskip.lua. Its
--   opening and ending become ranges like the chapters' ones (same button,
--   same binding, same double-click guard), the opening skipping to its end,
--   an ending that runs to the end of the file like a last-chapter ending.
--   An answer that arrives once the opening is over changes nothing on
--   screen; one that arrives after the file changed (end-file counts the
--   files) is dropped.
-- - Next episode (next_episode=yes, the default): hikari-resume.lua publishes
--   the next episode of the file playing in user-data/hikari_resume/next
--   ({path, next}; files only, never streams). When it is for this very path
--   and the next entry of the playlist is that file (compared with one kind
--   of separator, and without case on Windows), the button that would do
--   `playlist-next` (a last-chapter ending, as before) reads "Next episode ›"
--   instead of "Skip ending ›". With it queued, an AniSkip ending that ends
--   less than FINAL_MARGIN seconds before the end of the file (as
--   hikari-resume's END_MARGIN) counts as the last thing in it: the button
--   stays to the end and goes to the next episode, with that label. A file
--   with no ending range at all (no chapter, no AniSkip, or endings=no) gets
--   the "Next episode ›" button from NEXT_SHARE of its duration to the end.
--   It is checked again when the published value, playlist-pos or
--   playlist-count changes. next_episode=no leaves all of it as in hikari 0.8.
-- - Automatic skip (auto_skip=no|openings|endings|all, `no` by default): the
--   ranges that have a button anyway, so the openings, intros, endings and
--   outros options count, and so do AniSkip and streams. "openings" are the
--   opening and intro ranges, "endings" the ending and outro ones; the "Next
--   episode ›" range of a file without an ending is never skipped on its own
--   (hikari-resume plays the next episode by its own rules). The skip is the
--   button's (skip_range): to the next chapter or the end of an AniSkip range,
--   and for a range that runs to the end, playlist-next or the end of the file,
--   so content after an ending (a scene after the credits) is not skipped,
--   except, as with the button, the less than FINAL_MARGIN seconds an AniSkip
--   ending leaves when the next episode is queued.
-- - When: each range is looked at once as playback enters it (`judged`), and
--   skipped only when playback got there by playing, or when the file starts
--   or is resumed inside it. time-pos tells: a step forward of at most
--   FLOW_STEP seconds with no `seek` event in between is playback, anything
--   else a jump, and `flow` is where the last jump (or the file) started. A
--   range is entered by playing when that start is more than SEEK_MARGIN
--   seconds before the range's: a seek with the arrow keys lands on a keyframe,
--   which may be a little short of a range it was aimed into. A jump before
--   SETTLE seconds of the file have played counts as where the file starts:
--   continue watching's question pauses at 0 and seeks once answered, and
--   mpv's own resume starts there at once. So a seek (a click on the timeline,
--   a key, a chapter key) into a range later on does not skip it. That mark
--   (`flow.auto`) lasts for the whole stretch of playback that follows, so
--   AniSkip times that arrive late, with playback already inside the opening
--   it has played into from the start, still skip it, halfway through. Our own
--   skip's seek (`auto_target`, only until the next jump) counts as playback
--   too: a range that starts where it lands (an ending, then a preview) is
--   skipped as well, also halfway through a file. While continue watching's
--   question is open (PROMPT_TYPE in uosc or suji, or mpv's console for the
--   selector, which any use of the console holds up too), and for
--   PROMPT_GRACE seconds after (its seek), ranges are not looked at: they are
--   once it has gone, where it left playback, so the race with the time
--   hikari-resume reads and the 5 s of "‹ Watch opening" behind the menu are
--   both avoided. A range longer than AUTO_MAX_SHARE of the file (a chapter
--   list that marks nearly all of it as one) is never skipped on its own; its
--   button stays. Each range is skipped on its own once per file at most
--   (`auto_done`, by kind and start); turning the mode on inside a range
--   leaves that one alone.
--   time-pos is observed while the mode is not `no` even without ranges, so the
--   first value of each file is its start; observing starts on a file already
--   playing (the mode turned on) count as settled, and stopping forgets the
--   last time, so an old one is never compared with a new one.
-- - Undo: after a skip that stays in the file, the button reads "‹ Watch
--   opening" (intro, ending, preview) for UNDO_TIME seconds, also with suji
--   (show-action, hide-action when it ends) and in place of any skip button.
--   Clicking it or the `skip` binding seeks back to the range's start, and that
--   range is not skipped on its own again in this file; its own skip button
--   shows there as usual. A short OSD message ("Opening skipped") says what
--   happened: mpv's OSD text, top left, for 2 s, takes no clicks and covers
--   nothing of the button, unlike a second button or a box of our own.
-- - The mode is picked in a menu (the `open-menu` binding, Alt+S in
--   input.conf; uosc's, suji's or mpv's selector, script-modules/hikari-menu.lua)
--   with the four modes and the current one marked, an OSD message saying the
--   new one. One key for a menu, as Alt+l for the language: all four modes in
--   sight, rather than a key to press up to three times. suji's More menu takes
--   no entries from scripts (its API has none), so with suji the menu opens on
--   its own, out of the More button. hikari-menu.lua is loaded like
--   hikari-aniskip.lua: without it (a partial copy) the button still works
--   and only the menu does not open.
-- - The pick is saved in STATE_PATH (`auto_skip=<mode>`, like hikari-update's
--   state: read by this script only, never included from mpv.conf) and wins
--   over auto_skip from the options while the file is there; deleting it goes
--   back to them. A broken, unknown or hand-edited file is ignored (a warning
--   for an unknown mode); only MAX_STATE bytes are read. Updating hikari keeps
--   it; uninstalling removes it, like hikari-update.txt.
--
-- Options (script-opts/hikari-skip.conf): see that file.

local msg = require('mp.msg')
local options = require('mp.options')
local utils = require('mp.utils')

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua. Single-file
-- scripts get no mpv folder in package.path, so the folder is added for this
-- one require and taken out again (see the header of hikari-i18n.lua).
local i18n = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-i18n')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-i18n.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

-- Chapter kinds by title: ~~/script-modules/hikari-chapters.lua, loaded like
-- the texts above.
local chapter_kinds = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-chapters')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-chapters.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

local OPTIONS_ID = 'hikari-skip'
-- Input section names are global to mpv, so ours carries the script name.
local MOUSE_SECTION = mp.get_script_name() .. '_button'
-- The button hides this many seconds before the next chapter starts, so a
-- frame that lands just short of the boundary does not keep it on screen.
local END_MARGIN = 0.25
-- Average glyph width as a fraction of the font size, to size the box.
local CHAR_WIDTH = 0.52
-- Where hikari-resume.lua publishes the next episode of the file playing.
local NEXT_PROP = 'user-data/hikari_resume/next'
-- An AniSkip ending this close to the end of the file is its last part.
local FINAL_MARGIN = 10
-- Without an ending, the "Next episode" button shows from this share on.
local NEXT_SHARE = 0.95
-- How high suji's controls reach, and the gap above them at scale 1.
local SUJI_MARGINS_PROP = 'user-data/suji/margins'
local SUJI_GAP = 15
-- suji's action button (suji 0.3.0 or newer): whether suji is on, the id of
-- our button, and the message its command sends back to this script.
local SUJI_ENABLED_PROP = 'user-data/suji/enabled'
-- suji's version as text (suji 0.3.1 or newer; 0.3.0 only sends suji-version).
local SUJI_VERSION_PROP = 'user-data/suji/version'
local ACTION_ID = 'hikari-skip'
local ACTION_MESSAGE = 'skip-action'
-- Automatic skip: the modes, in the menu's order, with the key of their text
-- and the kinds they skip (intros go with openings, outros with endings).
local AUTO_MODES = {'no', 'openings', 'endings', 'all'}
local AUTO_LABELS = {no = 'auto_skip_off', openings = 'auto_skip_openings', endings = 'auto_skip_endings', all = 'auto_skip_all'}
local AUTO_KINDS = {
	no = {}, openings = {openings = true, intros = true}, endings = {endings = true, outros = true},
	all = {openings = true, intros = true, endings = true, outros = true},
}
local MENU_TYPE = 'hikari-skip'
local MODE_MESSAGE = 'set-auto-skip'
-- Where the menu saves its pick, and how much of that file is read.
local STATE_PATH = '~~/hikari-skip.txt'
local MAX_STATE = 4096
-- How long "‹ Watch opening" stays after a skip.
local UNDO_TIME = 5
-- time-pos moving forward by at most FLOW_STEP seconds is playback; a file
-- counts as playing from where it started until SETTLE seconds have played.
local FLOW_STEP = 2
local SETTLE = 3
-- A seek that lands less than SEEK_MARGIN seconds before a range (a keyframe
-- short of where it was aimed) is a seek into it; our own skip lands within
-- OWN_MARGIN of where it went.
local SEEK_MARGIN = 1.5
local OWN_MARGIN = 1
-- A range longer than this share of the file is never skipped on its own.
local AUTO_MAX_SHARE = 0.9
-- Continue watching's question (hikari-resume.lua): nothing is skipped on its
-- own while it is open, nor for PROMPT_GRACE seconds after (its seek).
local PROMPT_TYPE = 'hikari-resume-prompt'
local PROMPT_GRACE = 0.5

local opts = {
	openings = true,
	endings = true,
	intros = true,
	outros = false,
	-- Extra Lua patterns, separated by '|', matched against the lower-case title.
	extra_openings = '',
	extra_endings = '',
	extra_intros = '',
	extra_outros = '',
	margin_bottom = 96,
	margin_right = 16,
	font_size = 18,
	opacity = 0.85,
	scale = 1,
	scale_fullscreen = 1.3,
	-- Opening and ending times from AniSkip for files without such chapters.
	aniskip = true,
	-- "Next episode ›" when the next episode is next in the playlist.
	next_episode = true,
	-- Skip on their own: no, openings, endings or all (see AUTO_MODES).
	auto_skip = 'no',
}
options.read_options(opts, OPTIONS_ID)

-- AniSkip lookups: ~~/script-modules/hikari-aniskip.lua, loaded like the
-- texts above, and only when wanted. Without it the button still works with
-- chapters.
local aniskip = (function()
	if not opts.aniskip then return nil end
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then return nil end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-aniskip')
	package.path = saved
	if not ok then
		msg.warn('hikari: cannot load script-modules/hikari-aniskip.lua (reinstall hikari): ' .. tostring(module))
		return nil
	end
	return module
end)()
-- Menus: ~~/script-modules/hikari-menu.lua (uosc's, or mpv's own selector
-- without uosc), loaded like AniSkip's module: without it the button still
-- works, only the automatic skip menu does not open.
local menu = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then return nil end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-menu')
	package.path = saved
	if not ok then
		msg.warn('hikari: cannot load script-modules/hikari-menu.lua (reinstall hikari): ' .. tostring(module))
		return nil
	end
	return module
end)()
-- Where hikari-title.lua publishes the series and episode of the file playing.
local RELEASE_PROP = 'user-data/hikari_title/release'

-- Number within [min, max]; `default` when it is not a number (or NaN).
-- Infinities end up at the bounds, so every option stays finite.
local function clamp(value, min, max, default)
	value = tonumber(value)
	if not value or value ~= value then return default end
	return math.min(max, math.max(min, value))
end
opts.margin_bottom = clamp(opts.margin_bottom, 0, 10000, 96)
opts.margin_right = clamp(opts.margin_right, 0, 10000, 16)
opts.font_size = clamp(opts.font_size, 1, 200, 18)
opts.scale = clamp(opts.scale, 0.1, 10, 1)
opts.scale_fullscreen = clamp(opts.scale_fullscreen, 0.1, 10, 1.3)
opts.opacity = clamp(opts.opacity, 0, 1, 0.85)
if type(opts.auto_skip) ~= 'string' or not AUTO_KINDS[opts.auto_skip] then
	msg.warn('Ignoring auto_skip=' .. (tostring(opts.auto_skip):sub(1, 64):gsub('%c', '?'))
		.. ': it takes no, openings, endings or all')
	opts.auto_skip = 'no'
end

-- Our own copy of the kinds (see hikari-chapters.lua), in its order, with the
-- options below. `label` is the key of the button text in hikari-i18n.
local KINDS = chapter_kinds.kinds()

-- Adds the user's extra patterns; malformed ones are dropped with a warning.
for _, kind in ipairs(KINDS) do
	kind.enabled = opts[kind.name] and true or false
	local extra = opts['extra_' .. kind.name]
	if type(extra) == 'string' then
		for pattern in extra:gmatch('[^|]+') do
			if pcall(string.find, '', pattern) then
				kind.patterns[#kind.patterns + 1] = pattern
			else
				msg.warn('Ignoring invalid pattern in extra_' .. kind.name .. ': ' .. pattern)
			end
		end
	end
end

local KIND_BY_NAME = {}
for _, kind in ipairs(KINDS) do KIND_BY_NAME[kind.name] = kind end
-- The range at the end of a file with no ending, when the next episode is queued.
local NEXT_KIND = {name = 'next episode', label = 'skip_next_episode', enabled = true}

-- Kind for a chapter title, or nil (see hikari-chapters.lua). With `all`,
-- kinds turned off in the options count too.
local function classify(title, all)
	return chapter_kinds.classify(KINDS, title, all)
end

-- Skippable ranges: {kind, start, finish, next_time}. `finish` is the next
-- chapter's start, the duration for a last chapter, or math.huge if unknown.
local function build_ranges(chapters, duration)
	local list = {}
	if type(chapters) == 'table' then
		for _, chapter in ipairs(chapters) do
			if type(chapter) == 'table' and type(chapter.time) == 'number'
				and chapter.time > -math.huge and chapter.time < math.huge then -- also rejects NaN
				list[#list + 1] = {time = chapter.time, title = chapter.title, order = #list}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		return a.order < b.order
	end)
	local ranges = {}
	for i, chapter in ipairs(list) do
		local kind = classify(chapter.title)
		local nxt = list[i + 1]
		if kind and (nxt or not kind.requires_next) then
			local finish = nxt and nxt.time
				or (type(duration) == 'number' and duration > chapter.time and duration) or math.huge
			if finish > chapter.time then
				ranges[#ranges + 1] = {kind = kind, start = chapter.time, finish = finish, next_time = nxt and nxt.time}
			end
		end
	end
	return ranges
end

-- Does the file mark its opening (or intro, as many releases call the
-- opening song) or its ending with chapters, whatever the options say? Then
-- AniSkip is not asked.
local function has_skip_chapters(chapters)
	if type(chapters) ~= 'table' then return false end
	for _, chapter in ipairs(chapters) do
		local kind = type(chapter) == 'table' and classify(chapter.title, true)
		if kind and kind.name ~= 'outros' then return true end
	end
	return false
end

-- Ranges from AniSkip's results (see hikari-aniskip.lua) for a file of
-- `duration` seconds, as build_ranges makes them. An ending that runs to the
-- end of the file skips like a last-chapter ending (next_time nil). With
-- `next_queued`, so does one that ends within FINAL_MARGIN of the end, and its
-- button stays to the end.
local function aniskip_ranges(results, duration, next_queued)
	local ranges = {}
	if not aniskip or not results then return ranges end
	for _, r in ipairs(aniskip.select(results, duration)) do
		local kind = KIND_BY_NAME[r.kind == 'opening' and 'openings' or 'endings']
		if kind.enabled then
			local to_end = r.finish >= duration - 1
			local finish = r.finish
			if not to_end and next_queued and r.kind ~= 'opening' and r.finish >= duration - FINAL_MARGIN then
				to_end, finish = true, duration
			end
			ranges[#ranges + 1] = {kind = kind, start = r.start, finish = finish,
				next_time = not to_end and r.finish or nil, aniskip = true}
		end
	end
	return ranges
end

-- Index of the range that contains `time`, or nil.
local function range_at(ranges, time)
	if type(time) ~= 'number' then return nil end
	for i, range in ipairs(ranges) do
		if time >= range.start and time < range.finish - END_MARGIN then return i end
	end
	return nil
end

-- Colours ---------------------------------------------------------------------

-- uosc's defaults, used when the palette does not set a key.
local DEFAULT_COLORS = {
	foreground = 'ffffff', foreground_text = '000000',
	background = '000000', background_text = 'ffffff',
}

-- Reads foreground/background colours from the `uosc-color` script option
-- (`foreground=RRGGBB,background=RRGGBB,...`). Unknown keys and malformed
-- values are ignored.
local function parse_colors(script_opts)
	local colors = {}
	for key, value in pairs(DEFAULT_COLORS) do colors[key] = value end
	local spec = type(script_opts) == 'table' and script_opts['uosc-color']
	if type(spec) ~= 'string' then return colors end
	for pair in spec:sub(1, 1000):gmatch('[^,]+') do
		local key, value = pair:match('^%s*([%w_]+)%s*=%s*#?(%x%x%x%x%x%x)%s*$')
		if key and DEFAULT_COLORS[key] then colors[key] = value:lower() end
	end
	return colors
end

-- RRGGBB -> BBGGRR, the order ASS colour tags use.
local function to_bgr(hex)
	return (hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2)):upper()
end

-- Opacity 0..1 -> ASS alpha (00 opaque, FF transparent).
local function to_alpha(opacity)
	return string.format('%02X', math.floor((1 - opacity) * 255 + 0.5))
end

-- Drawing -----------------------------------------------------------------------

local function round(value) return math.floor(value + 0.5) end

-- Same idea as uosc's ass_escape: no literal backslash sequences, no override
-- blocks, no line breaks.
local function ass_escape(text)
	text = text:gsub('\\', '\\\239\187\191')
	text = text:gsub('{', '\\{'):gsub('}', '\\}')
	text = text:gsub('[\r\n]', ' ')
	return text
end

-- Width of a text in "narrow characters": East Asian wide and full-width
-- characters (CJK, Hangul, kana, full-width forms) count 2, the rest 1.
local function text_width(text)
	local width = 0
	for char in text:gmatch('[\1-\127\194-\244][\128-\191]*') do
		local code = char:byte(1)
		if #char == 3 then
			code = (code % 16) * 4096 + (char:byte(2) % 64) * 64 + char:byte(3) % 64
		end
		local wide = #char == 3 and ((code >= 0x1100 and code <= 0x115F) or (code >= 0x2E80 and code <= 0xA4CF)
			or (code >= 0xAC00 and code <= 0xD7A3) or (code >= 0xF900 and code <= 0xFAFF)
			or (code >= 0xFE30 and code <= 0xFE4F) or (code >= 0xFF00 and code <= 0xFF60)
			or (code >= 0xFFE0 and code <= 0xFFE6))
		width = width + (wide and 2 or 1)
	end
	return width
end

-- ASS drawing of a rectangle with rounded corners (Bezier quarter circles).
local function rounded_rect(x0, y0, x1, y1, r)
	local k = round(r * 0.4477) -- 1 - 0.5523, the circle approximation constant
	return string.format(
		'm %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d '
		.. 'l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d',
		x0 + r, y0, x1 - r, y0, x1 - k, y0, x1, y0 + k, x1, y0 + r,
		x1, y1 - r, x1, y1 - k, x1 - k, y1, x1 - r, y1,
		x0 + r, y1, x0 + k, y1, x0, y1 - k, x0, y1 - r,
		x0, y0 + r, x0, y0 + k, x0 + k, y0, x0 + r, y0)
end

-- The automatic skip picked in the menu ------------------------------------------

-- The mode saved in STATE_PATH, or nil: no file, or no valid `auto_skip=`
-- line in it (a broken or hand-edited file is ignored; the last line wins).
local function read_saved_mode()
	local path = mp.command_native({'expand-path', STATE_PATH})
	if type(path) ~= 'string' or path == '' then return nil end
	local file = io.open(path, 'rb')
	if not file then return nil end
	local content = file:read(MAX_STATE)
	file:close()
	local value
	for line in ((type(content) == 'string' and content or '') .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', '')
		local key, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
		if key == 'auto_skip' then value = v end
	end
	if value == nil then return nil end
	if not AUTO_KINDS[value] then
		msg.warn('Ignoring ' .. STATE_PATH .. ': unknown automatic skip ' .. (value:sub(1, 64):gsub('%c', '?')))
		return nil
	end
	return value
end

-- Writes through a temporary file and a rename so a crash never leaves half a file.
local function write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	-- A leftover .tmp (or a link planted there) goes first, so io.open creates
	-- a new file instead of writing through whatever was there.
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

-- Saves a mode of AUTO_MODES; on failure, a warning and a message on screen.
local function save_mode(mode)
	local path = mp.command_native({'expand-path', STATE_PATH})
	local ok, err = false, 'no config folder'
	if AUTO_KINDS[mode] and type(path) == 'string' and path ~= '' then
		ok, err = write_file_atomic(path, '# Written by hikari-skip.lua: the automatic skip picked in its menu.'
			.. ' It wins over auto_skip in script-opts/hikari-skip.conf; delete this file to follow that again.\n'
			.. 'auto_skip=' .. mode .. '\n')
	end
	if not ok then
		msg.warn('Could not save the automatic skip to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message(i18n.t('auto_skip_save_failed'), 3)
	end
	return ok
end

-- State -------------------------------------------------------------------------

local state = {
	chapters = nil, duration = nil, ranges = {},
	-- dismissed: {start, target} of the range skipped last; `target` is where
	-- the skip seeked to (nil for playlist-next).
	time = nil, current = nil, dismissed = nil,
	-- AniSkip: `file` counts the files played, so a late answer is dropped;
	-- `asked` once per file; `results` the answer for this file.
	file = 0, loaded = false, asked = false, results = nil,
	next_queued = false, -- the next playlist entry is the next episode (see next_episode_queued)
	guard_until = nil, guard_timer = nil, -- double-click guard after a mouse skip
	idle = false, menu_open = false, suji_menu_open = false, console_open = false, context_menu_open = false,
	osd_w = 0, osd_h = 0,
	suji_bottom = nil, -- user-data/suji/margins.bottom, when above 0
	-- suji_on: user-data/suji/enabled is true; suji_published: the value of
	-- user-data/suji/version; suji_announced: the last suji-version message;
	-- suji_actions: the version (the first, or else the second) is 0.3.0 or
	-- newer; action: the text of the show-action sent, nil when none is up.
	suji_on = false, suji_published = nil, suji_announced = nil, suji_actions = false, action = nil,
	fullscreen = false, maximized = false, hidpi = 1,
	colors = parse_colors(nil),
	mouse = nil, hovered = false, pressed = false, guard_press = false, section_enabled = false,
	drawn = nil, -- last data sent to the overlay, nil when nothing is drawn
	-- Automatic skip. auto_saved: the mode saved by the menu, which wins over
	-- opts.auto_skip. For this file: auto_done, the ranges skipped on their own
	-- (by range_id); judged, the id of the range whose entry was looked at last;
	-- last_time, played (seconds of playback), flow ({start, auto}: where the
	-- last jump went and whether it counts as the file's start) and seeked (a
	-- `seek` event since the last time-pos), see track_flow; undo, {start,
	-- label, timer} while "‹ Watch opening" is up.
	auto_saved = nil, auto_done = {}, judged = nil,
	last_time = nil, played = 0, flow = nil, seeked = false, undo = nil,
	-- auto_target: where our last automatic skip seeked, until time-pos jumps.
	-- prompt_uosc, prompt_suji: continue watching's question is open in uosc or
	-- suji (the selector's is mpv's console, console_open); prompt_open: any of
	-- the three, as last seen; prompt_timer: the PROMPT_GRACE after it closed.
	auto_target = nil, prompt_uosc = false, prompt_suji = false, prompt_open = false, prompt_timer = nil,
}
state.auto_saved = read_saved_mode()

local overlay = mp.create_osd_overlay('ass-events')

local function auto_mode()
	return state.auto_saved or opts.auto_skip
end

local function is_dismissed(index)
	local range = index and state.ranges[index]
	return range ~= nil and state.dismissed ~= nil and state.dismissed.start == range.start
end

-- In a range that has not been skipped, with a file playing.
local function is_active()
	return state.current ~= nil and not is_dismissed(state.current) and not state.idle
end

-- A menu of uosc, mpv's console or its context menu is open: clicks are theirs.
-- (suji's own menus are counted apart: suji hides its action buttons itself.)
local function covered()
	return state.menu_open or state.console_open or state.context_menu_open
end

-- The key of a range's label: "Next episode" for one that goes to the next
-- entry of the playlist when that entry is the next episode.
local function label_key(range)
	if range.kind == NEXT_KIND or (not range.next_time and state.next_queued) then return NEXT_KIND.label end
	return range.kind.label
end

-- The key of the button's text: "‹ Watch opening" for a while after an
-- automatic skip, otherwise the label of the range playing; nil: no button.
local function button_key()
	if state.idle then return nil end
	if state.undo then return state.undo.label end
	if is_active() then return label_key(state.ranges[state.current]) end
	return nil
end

local function is_visible()
	return button_key() ~= nil and not state.menu_open and not state.suji_menu_open and not state.console_open and not state.context_menu_open
		and state.osd_w > 0 and state.osd_h > 0
end

local function current_scale()
	local base = (state.fullscreen or state.maximized) and opts.scale_fullscreen or opts.scale
	return (state.hidpi > 0 and state.hidpi or 1) * base
end

-- suji draws the button: it is on and understands show-action.
local function suji_draws()
	return state.suji_on and state.suji_actions
end

-- Button rectangle in OSD pixels, or nil when hidden (or drawn by suji).
local function layout()
	if not is_visible() or suji_draws() then return nil end
	local label = i18n.t(button_key())
	local s = current_scale()
	local fs = round(opts.font_size * s)
	local pad_x, pad_y = round(fs * 0.8), round(fs * 0.5)
	local w = round(text_width(label) * fs * CHAR_WIDTH) + pad_x * 2
	local h = fs + pad_y * 2
	local x1 = state.osd_w - round(opts.margin_right * s)
	local y1
	if state.suji_bottom then
		y1 = state.osd_h - round(state.suji_bottom) - round(SUJI_GAP * s)
	else
		y1 = state.osd_h - round(opts.margin_bottom * s)
	end
	return {
		x0 = x1 - w, y0 = y1 - h, x1 = x1, y1 = y1,
		font_size = fs, radius = math.min(round(6 * s), math.floor(h / 2)),
		border = math.max(1, round(1.5 * s)), label = label,
	}
end

local function ass_data(rect, hovered)
	local c = state.colors
	local fill, fill_alpha, text
	if hovered then
		fill, fill_alpha, text = c.foreground, '00', c.foreground_text
	else
		fill, fill_alpha, text = c.background, to_alpha(opts.opacity), c.background_text
	end
	local box = string.format('{\\an7\\pos(0,0)\\bord%d\\shad0\\blur0\\1c&H%s&\\1a&H%s&\\3c&H%s&\\3a&H00&\\p1}%s{\\p0}',
		rect.border, to_bgr(fill), fill_alpha, to_bgr(c.foreground),
		rounded_rect(rect.x0, rect.y0, rect.x1, rect.y1, rect.radius))
	local label = string.format('{\\an5\\pos(%d,%d)\\fs%d\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H00&}%s',
		round((rect.x0 + rect.x1) / 2), round((rect.y0 + rect.y1) / 2), rect.font_size,
		to_bgr(text), ass_escape(rect.label))
	return box .. '\n' .. label
end

local function inside(rect, mouse)
	if not rect or type(mouse) ~= 'table' or mouse.hover == false then return false end
	local x, y = tonumber(mouse.x), tonumber(mouse.y)
	return x ~= nil and y ~= nil and x >= rect.x0 and x <= rect.x1 and y >= rect.y0 and y <= rect.y1
end

-- Enables the click section while it is wanted (pointer over the visible
-- button, a press on it not yet released, or the double-click guard) and
-- disables it otherwise.
-- Re-enabling moves it back to the top of mpv's section stack, above uosc's.
local function guard_active()
	return state.guard_until ~= nil and mp.get_time() < state.guard_until
end

local function update_section()
	local want = state.hovered or state.pressed or guard_active()
	if want then
		mp.enable_key_bindings(MOUSE_SECTION, '')
		state.section_enabled = true
	elseif state.section_enabled then
		mp.disable_key_bindings(MOUSE_SECTION)
		state.section_enabled = false
	end
end

local on_mouse_pos
local mouse_watched = false

-- Shows suji's action button with the text of our button, changes it, or
-- hides it, when that differs from what was sent last.
local function sync_action()
	local key = suji_draws() and not covered() and button_key()
	local text = key and i18n.t(key) or nil
	if text == state.action then return end
	if text then
		mp.commandv('script-message-to', 'suji', 'show-action', ACTION_ID, utils.format_json({
			text = text,
			command = {'script-message-to', mp.get_script_name(), ACTION_MESSAGE},
		}))
	else
		mp.commandv('script-message-to', 'suji', 'hide-action', ACTION_ID)
	end
	state.action = text
end

-- Brings overlay, hover state, click section and suji's action button in line
-- with the state.
local function refresh()
	sync_action()
	local rect = layout()
	-- Only follow the pointer while there is a button to point at.
	if rect and not mouse_watched then
		mp.observe_property('mouse-pos', 'native', on_mouse_pos)
		mouse_watched = true
		state.mouse = mp.get_property_native('mouse-pos')
	elseif not rect and mouse_watched then
		mp.unobserve_property(on_mouse_pos)
		mouse_watched = false
		state.mouse = nil
	end
	state.hovered = inside(rect, state.mouse)
	update_section()
	if not rect then
		if state.drawn then
			overlay:remove()
			state.drawn = nil
		end
		return
	end
	local data = ass_data(rect, state.hovered)
	local key = state.osd_w .. 'x' .. state.osd_h .. '\n' .. data
	if key == state.drawn then return end
	overlay.res_x, overlay.res_y = state.osd_w, state.osd_h
	overlay.data = data
	overlay:update()
	state.drawn = key
end

on_mouse_pos = function(_, mouse)
	state.mouse = mouse
	-- While the pointer stays on the button, refresh() re-enables our section
	-- on every move, keeping it above anything enabled since.
	refresh()
end

-- Seconds as `12.345`, built from integers so the decimal separator never
-- depends on the C locale.
local function format_time(seconds)
	local ms = math.max(0, round(seconds * 1000))
	return string.format('%d.%03d', math.floor(ms / 1000), ms % 1000)
end

local function log_range(range)
	msg.verbose(string.format('In a skippable range: %s from %s%s', range.kind.name,
		format_time(range.start), range.aniskip and ' (AniSkip)' or ''))
end

-- Looks at the range playing once as playback enters it, and skips it when
-- the automatic skip wants it (defined below, after skip_range).
local auto_skip_check

-- Recomputes which range we are in; redraws only when that changes.
local function update_current()
	local index = range_at(state.ranges, state.time)
	local dismissed = state.dismissed
	-- Back before the skipped range's start (or out of it): it shows again.
	if dismissed and (not is_dismissed(index) or (state.time and state.time < dismissed.start)) then
		state.dismissed = nil
	end
	if index == state.current and state.dismissed == dismissed then return end
	if index and index ~= state.current then log_range(state.ranges[index]) end
	state.current = index
	-- Before drawing: a range skipped on its own never shows its skip button.
	auto_skip_check()
	refresh()
end

-- How playback moves, for the automatic skip: a step forward of at most
-- FLOW_STEP seconds with no seek in between is playback (it adds to `played`);
-- the first time of a file, or anything else, starts a new `flow` there,
-- which counts as the file's start while less than SETTLE seconds have played.
local function track_flow(time)
	if type(time) ~= 'number' then return end
	local last = state.last_time
	state.last_time = time
	local delta = last and time - last
	if delta and not state.seeked and delta >= 0 and delta <= FLOW_STEP then
		state.played = state.played + delta
		return
	end
	state.seeked = false
	-- Our own skip landing: playback goes on from there as if it had played
	-- through, so a range that starts where it lands is entered by playing.
	local own = state.auto_target ~= nil and math.abs(time - state.auto_target) <= OWN_MARGIN
	state.auto_target = nil
	state.flow = {start = time, auto = own or state.played < SETTLE}
end

local function on_time(_, time)
	track_flow(time)
	state.time = time
	update_current()
end

local time_watched = false

-- Listens to time-pos while there are ranges, or while the automatic skip is
-- on (so it sees each file from its start). Starting on a file that is
-- already playing: that is not where it started.
local function watch_time()
	local want = #state.ranges > 0 or auto_mode() ~= 'no'
	if want and not time_watched then
		mp.observe_property('time-pos', 'number', on_time)
		time_watched = true
		state.time = mp.get_property_number('time-pos')
		if state.time and state.last_time == nil then
			state.last_time, state.played = state.time, SETTLE
			state.flow = {start = state.time, auto = false}
		end
	elseif not want and time_watched then
		mp.unobserve_property(on_time)
		time_watched = false
		-- Watched again later: start afresh, not from this old time.
		state.last_time = nil
	end
end

local function rebuild()
	local before = state.current and state.ranges[state.current]
	state.ranges = build_ranges(state.chapters, state.duration)
	if state.results and not has_skip_chapters(state.chapters) and type(state.duration) == 'number' then
		for _, range in ipairs(aniskip_ranges(state.results, state.duration, state.next_queued)) do
			state.ranges[#state.ranges + 1] = range
		end
		table.sort(state.ranges, function(a, b) return a.start < b.start end)
	end
	-- No ending at all, and the next episode is next: a button for the last 5 %.
	local duration = state.duration
	if state.next_queued and type(duration) == 'number' and duration > 0 and duration < math.huge then
		local ending = false
		for _, range in ipairs(state.ranges) do
			if range.kind.name == 'endings' then ending = true end
		end
		if not ending then
			state.ranges[#state.ranges + 1] = {kind = NEXT_KIND, start = duration * NEXT_SHARE, finish = duration}
		end
	end
	state.current = nil
	-- Keep a dismissal while its range still exists (a stream's duration
	-- grows and rebuilds the ranges without anything really changing).
	if state.dismissed then
		local found = false
		for _, range in ipairs(state.ranges) do
			if range.start == state.dismissed.start then found = true break end
		end
		if not found then state.dismissed = nil end
	end
	-- No skippable chapters (and no automatic skip): do not even listen to time-pos.
	watch_time()
	state.current = range_at(state.ranges, state.time)
	-- Opening a file inside a range, or times that arrive during one: logged
	-- as update_current does (not again when only the duration moved).
	local now = state.current and state.ranges[state.current]
	if now and not (before and before.start == now.start and before.kind == now.kind) then log_range(now) end
	auto_skip_check()
	refresh()
end

-- Skips the current range. Returns true if it did something. `undo`, for an
-- automatic skip, goes up with the seek ("‹ Watch opening"; not for
-- playlist-next, which leaves the file).
local function skip_range(undo)
	local range = state.ranges[state.current]
	local target
	if range.next_time then
		target = range.next_time
	else
		local pos = mp.get_property_number('playlist-pos', -1)
		local count = mp.get_property_number('playlist-count', 0)
		local duration = mp.get_property_number('duration')
		if pos and count and pos >= 0 and pos + 1 < count then
			state.dismissed = {start = range.start}
			mp.commandv('playlist-next')
			refresh()
			return true
		elseif not duration or duration ~= duration or duration == math.huge or duration == -math.huge then
			-- Nowhere to go: leave the button where it is.
			return false
		end
		target = math.max(range.start, duration - 1)
	end
	state.dismissed = {start = range.start, target = target}
	if undo then state.undo = undo end
	mp.commandv('seek', format_time(target), 'absolute+exact')
	refresh()
	return true
end

local function stop_undo()
	if state.undo and state.undo.timer then state.undo.timer:kill() end
	state.undo = nil
end

-- "‹ Watch opening": back to the start of the range skipped on its own. It is
-- in auto_done already, so it is not skipped on its own again in this file.
local function watch_again()
	local start = state.undo.start
	stop_undo()
	state.dismissed = nil
	mp.commandv('seek', format_time(start), 'absolute+exact')
	refresh()
	return true
end

-- What the button does: go back while "‹ Watch opening" is up, otherwise skip.
local function press()
	if state.undo then return watch_again() end
	return skip_range()
end

-- The binding and our own button: only while the button can be seen.
local function skip()
	if not is_visible() then return false end
	return press()
end

-- Which range, for auto_done and judged: its kind and start.
local function range_id(range)
	return range.kind.name .. '@' .. format_time(range.start)
end

-- skip_opening -> skip_undo_opening, skip_done_opening...
local function kind_key(kind, prefix)
	return (kind.label:gsub('^skip_', prefix))
end

-- Continue watching's question is open, or has just closed (see PROMPT_GRACE).
local function prompt_waiting()
	return state.prompt_open or state.prompt_timer ~= nil
end

auto_skip_check = function()
	local range = state.current and state.ranges[state.current]
	local id = range and range_id(range)
	if id == state.judged then return end
	-- Not yet: looked at once the question is answered, where it left playback.
	if range and prompt_waiting() then return end
	state.judged = id
	if not range or not is_active() or not AUTO_KINDS[auto_mode()][range.kind.name] or state.auto_done[id] then return end
	-- Nearly the whole file (a chapter list that marks it all): never on its own.
	local duration = state.duration
	if type(duration) == 'number' and duration > 0 and range.finish - range.start > duration * AUTO_MAX_SHARE then return end
	-- Entered by playing (from further back than a keyframe short of it), or
	-- the file started (or was resumed) in it, or our own skip landed on it.
	local flow = state.flow
	if not flow or not (flow.auto or flow.start < range.start - SEEK_MARGIN) then return end
	state.auto_done[id] = true
	msg.verbose('Automatic skip: ' .. range.kind.name .. ' from ' .. format_time(range.start))
	stop_undo()
	local undo = {start = range.start, label = kind_key(range.kind, 'skip_undo_')}
	if not skip_range(undo) then return end
	mp.osd_message(i18n.t(kind_key(range.kind, 'skip_done_')), 2)
	-- Still in this file (not playlist-next): a while to go back, and a range
	-- that starts where it lands is entered by playing (see track_flow).
	if state.undo == undo then
		state.auto_target = state.dismissed and state.dismissed.target
		undo.timer = mp.add_timeout(UNDO_TIME, function()
			if state.undo ~= undo then return end
			state.undo = nil
			refresh()
		end)
	end
end

-- The automatic skip picked in the menu (or by a message): applied at once and
-- saved. The mode comes from outside, so it must be one of AUTO_MODES.
local function set_auto_skip(mode)
	if type(mode) ~= 'string' or not AUTO_KINDS[mode] then
		msg.warn('Ignoring unknown automatic skip: ' .. (tostring(mode):sub(1, 64):gsub('%c', '?')))
		return
	end
	state.auto_saved = mode
	watch_time()
	if save_mode(mode) then
		mp.osd_message(i18n.t('auto_skip_now', {mode = i18n.t(AUTO_LABELS[mode])}), 2)
	end
end

local function menu_data()
	local current = auto_mode()
	local items = {}
	for _, mode in ipairs(AUTO_MODES) do
		local is_current = mode == current
		items[#items + 1] = {
			title = i18n.t(AUTO_LABELS[mode]),
			hint = is_current and i18n.t('current') or nil,
			active = is_current,
			value = {'script-message-to', mp.get_script_name(), MODE_MESSAGE, mode},
		}
	end
	return {type = MENU_TYPE, title = i18n.t('auto_skip_title'), items = items}
end

local function open_menu()
	if not menu then
		msg.warn('The automatic skip menu needs script-modules/hikari-menu.lua (reinstall hikari)')
		return
	end
	menu.open(menu_data())
end

local function stop_guard()
	if state.guard_timer then state.guard_timer:kill() end
	state.guard_until, state.guard_timer = nil, nil
end

-- Keeps the click section for one double-click time after a mouse skip.
local function start_guard()
	stop_guard()
	local delay = (mp.get_property_number('input-doubleclick-time', 300) or 300) / 1000
	delay = math.min(2, math.max(0.05, delay))
	state.guard_until = mp.get_time() + delay
	state.guard_timer = mp.add_timeout(delay, function()
		state.guard_until, state.guard_timer = nil, nil
		refresh()
	end)
end

-- Mouse button handlers of the click section.
local function on_down()
	state.mouse = mp.get_property_native('mouse-pos') or state.mouse
	state.hovered = inside(layout(), state.mouse)
	-- During the guard the press is just swallowed, even if a new button has
	-- already appeared under the pointer (the next chapter is skippable too).
	state.guard_press = guard_active()
	if state.hovered or state.guard_press then state.pressed = true end
end

local function on_up()
	local was_pressed, guard_press = state.pressed, state.guard_press
	state.pressed, state.guard_press = false, false
	state.mouse = mp.get_property_native('mouse-pos') or state.mouse
	if was_pressed and not guard_press and inside(layout(), state.mouse) and skip() then
		start_guard()
	end
	refresh()
end

mp.set_key_bindings({
	{'mbtn_left', on_up, on_down},
	{'mbtn_left_dbl', 'ignore'},
}, MOUSE_SECTION, 'force')

-- 'windows' or not, from mpv when it says (as hikari-update.lua).
local function is_windows()
	local p = mp.get_property_native('platform')
	if type(p) == 'string' and p ~= '' then return p == 'windows' end
	return package.config:sub(1, 1) == '\\'
end

-- Two paths of the same file, as far as a light look tells: one kind of
-- separator, without case on Windows.
local function same_path(a, b)
	if type(a) ~= 'string' or type(b) ~= 'string' then return false end
	local windows = is_windows()
	local function form(path)
		path = path:gsub('\\', '/'):gsub('/+', '/')
		return windows and path:lower() or path
	end
	return form(a) == form(b)
end

-- Is the next entry of the playlist the next episode hikari-resume found for
-- the file playing?
local function next_episode_queued()
	if not opts.next_episode then return false end
	local published = mp.get_property_native(NEXT_PROP)
	if type(published) ~= 'table' or type(published.next) ~= 'string' then return false end
	local path = mp.get_property_native('path')
	if type(path) ~= 'string' or published.path ~= path then return false end
	local pos = mp.get_property_number('playlist-pos', -1)
	local count = mp.get_property_number('playlist-count', 0)
	if not pos or not count or pos < 0 or pos + 1 >= count then return false end
	return same_path(mp.get_property_native('playlist/' .. math.floor(pos + 1) .. '/filename'), published.next)
end

local function update_next()
	local queued = next_episode_queued()
	if queued == state.next_queued then return end
	state.next_queued = queued
	rebuild()
end

-- Forgets everything about the file that just ended. The double-click guard
-- is about input, not the file, so it is left running: after a skip with
-- playlist-next, end-file arrives before the second click does. Its timer
-- (2 s at most) turns it off.
local function reset()
	state.chapters, state.duration, state.time = nil, nil, nil
	state.pressed, state.dismissed = false, nil
	state.file, state.loaded, state.asked, state.results = state.file + 1, false, false, nil
	state.next_queued = false
	stop_undo()
	state.auto_done, state.judged, state.auto_target = {}, nil, nil
	state.last_time, state.played, state.flow, state.seeked = nil, 0, nil, false
	rebuild()
end

-- Asks AniSkip once per file, after it has loaded (its chapters are known
-- then), when it has no opening or ending chapters, a duration, and
-- hikari-title has published a lookable release for this very path.
local function maybe_aniskip()
	if not aniskip or not state.loaded or state.asked then return end
	if not KIND_BY_NAME.openings.enabled and not KIND_BY_NAME.endings.enabled then return end
	if has_skip_chapters(mp.get_property_native('chapter-list')) then return end
	local duration = mp.get_property_number('duration')
	if not duration or duration ~= duration or duration <= 0 or duration == math.huge then return end
	local release = mp.get_property_native(RELEASE_PROP)
	local path = mp.get_property_native('path')
	if type(release) ~= 'table' or type(path) ~= 'string' or release.path ~= path then return end
	local query = aniskip.query(release, duration)
	if not query then return end
	state.asked = true
	local file = state.file
	aniskip.lookup(query, function(results)
		if file ~= state.file then
			msg.verbose('AniSkip: answer for a file that is no longer playing, dropped')
			return
		end
		if not results or #results == 0 then return end
		state.results = results
		local found = {}
		for _, range in ipairs(aniskip_ranges(results, duration)) do
			found[#found + 1] = range.kind.name .. ' ' .. format_time(range.start) .. '-' .. format_time(range.finish)
		end
		msg.verbose('AniSkip ranges for this file: ' .. (#found > 0 and table.concat(found, ', ') or 'none that fit'))
		rebuild()
	end)
end

local function setter(field, transform)
	return function(_, value)
		state[field] = transform(value)
		refresh()
	end
end
local function truthy(value) return value == true end

mp.observe_property('chapter-list', 'native', function(_, value)
	state.chapters = value
	rebuild()
end)
mp.observe_property('duration', 'number', function(_, value)
	state.duration = value
	rebuild()
	-- A stream may only know its duration after file-loaded.
	maybe_aniskip()
end)
mp.observe_property('idle-active', 'bool', setter('idle', truthy))
mp.observe_property('osd-dimensions', 'native', function(_, dims)
	state.osd_w = type(dims) == 'table' and tonumber(dims.w) or 0
	state.osd_h = type(dims) == 'table' and tonumber(dims.h) or 0
	refresh()
end)
mp.observe_property('script-opts', 'native', setter('colors', parse_colors))
mp.observe_property('fullscreen', 'bool', setter('fullscreen', truthy))
mp.observe_property('window-maximized', 'bool', setter('maximized', truthy))
mp.observe_property('display-hidpi-scale', 'number', setter('hidpi', function(v) return tonumber(v) or 1 end))
-- uosc publishes the type of its open menu here, and clears it on close.
mp.observe_property('user-data/uosc/menu/type', 'native', setter('menu_open', function(v)
	return v ~= nil and v ~= ''
end))
mp.observe_property('user-data/suji/menu/type', 'native', setter('suji_menu_open', function(v)
	return v ~= nil and v ~= ''
end))
-- suji's height; anything but a finite number above 0 is no height.
mp.observe_property(SUJI_MARGINS_PROP, 'native', setter('suji_bottom', function(v)
	local bottom = type(v) == 'table' and tonumber(v.bottom) or nil
	if not bottom or bottom ~= bottom or bottom <= 0 then return nil end
	return math.min(bottom, 10000)
end))
-- suji turned on, off or gone. Either way suji holds no action button of
-- ours now (turning it off removed them): one is sent again if wanted.
mp.observe_property(SUJI_ENABLED_PROP, 'native', function(_, v)
	state.suji_on = v == true
	state.action = nil
	refresh()
end)
-- Whether suji understands show-action: the version it publishes, or else the
-- one it announced, is text with major.minor 0.3 or more.
local function update_suji_actions()
	local version = state.suji_published or state.suji_announced
	local major, minor
	if type(version) == 'string' then major, minor = version:match('^(%d+)%.(%d+)') end
	major, minor = tonumber(major), tonumber(minor)
	state.suji_actions = major ~= nil and (major > 0 or minor >= 3)
	-- No longer one that draws it: take ours down there before drawing it here.
	if state.action and not state.suji_actions then
		mp.commandv('script-message-to', 'suji', 'hide-action', ACTION_ID)
	end
	-- A suji that starts now holds no button of ours: send it again if wanted.
	state.action = nil
	refresh()
end
-- suji's version, published as it loads (suji 0.3.1 or newer).
mp.observe_property(SUJI_VERSION_PROP, 'native', function(_, v)
	state.suji_published = v
	update_suji_actions()
end)
-- suji's version, sent when suji starts (only to the scripts already running).
mp.register_script_message('suji-version', function(version)
	state.suji_announced = tostring(version)
	update_suji_actions()
end)
-- A click on suji's action button. suji ignores the second click of a double
-- click, so there is no guard here; a message when no button of ours is up
-- (sent by hand, or late) does nothing.
mp.register_script_message(ACTION_MESSAGE, function()
	if state.action and suji_draws() and button_key() and not covered() then press() end
end)
mp.observe_property('user-data/mpv/console/open', 'bool', setter('console_open', truthy))
-- Continue watching's question opens and closes: in uosc, in suji, or in the
-- selector (mpv's console, where nothing tells it from any other use).
local function prompt_changed()
	local open = state.prompt_uosc or state.prompt_suji or state.console_open
	if open == state.prompt_open then return end
	state.prompt_open = open
	if state.prompt_timer then state.prompt_timer:kill() end
	state.prompt_timer = nil
	if open then return end
	state.prompt_timer = mp.add_timeout(PROMPT_GRACE, function()
		state.prompt_timer = nil
		auto_skip_check()
		refresh()
	end)
end
mp.observe_property('user-data/uosc/menu/type', 'native', function(_, v)
	state.prompt_uosc = v == PROMPT_TYPE
	prompt_changed()
end)
mp.observe_property('user-data/suji/menu/type', 'native', function(_, v)
	state.prompt_suji = v == PROMPT_TYPE
	prompt_changed()
end)
mp.observe_property('user-data/mpv/console/open', 'bool', function() prompt_changed() end)
mp.observe_property('user-data/mpv/context-menu/open', 'bool', setter('context_menu_open', truthy))
mp.register_event('end-file', reset)
-- Any seek, ours too: the next time-pos is a jump, not playback (track_flow).
mp.register_event('seek', function() state.seeked = true end)
mp.register_event('file-loaded', function()
	state.loaded = true
	maybe_aniskip()
end)
-- hikari-title may publish after file-loaded has been handled here.
mp.observe_property(RELEASE_PROP, 'native', function() maybe_aniskip() end)
-- The next episode: what hikari-resume published, and the playlist around it.
if opts.next_episode then
	mp.observe_property(NEXT_PROP, 'native', update_next)
	mp.observe_property('playlist-pos', 'number', update_next)
	mp.observe_property('playlist-count', 'number', update_next)
end
-- A seek that leaves playback far from where the skip went (the user going
-- back into a last-chapter ending with keep-open, say) brings the button back.
mp.register_event('playback-restart', function()
	local dismissed = state.dismissed
	if not dismissed or not dismissed.target then return end
	local time = mp.get_property_number('time-pos')
	if time and math.abs(time - dismissed.target) > 1.5 then
		state.dismissed = nil
		state.time = time
		state.current = nil
		update_current()
	end
end)

mp.add_key_binding(nil, 'skip', skip)
mp.add_key_binding(nil, 'open-menu', open_menu)
mp.register_script_message(MODE_MESSAGE, set_auto_skip)
-- Another language: the button, if it is on screen, is drawn again with it,
-- and so is the menu, if it is open.
i18n.on_change(function()
	refresh()
	if menu and menu.is_open(MENU_TYPE) then menu.update(menu_data()) end
end)

if HIKARI_SKIP_TEST then
	return {
		KINDS = KINDS, opts = opts, state = state, overlay = overlay, MOUSE_SECTION = MOUSE_SECTION,
		classify = classify, build_ranges = build_ranges, range_at = range_at,
		parse_colors = parse_colors, to_bgr = to_bgr, to_alpha = to_alpha, ass_escape = ass_escape,
		layout = layout, text_width = text_width, is_visible = is_visible, skip = skip, format_time = format_time,
		on_down = on_down, on_up = on_up, END_MARGIN = END_MARGIN, guard_active = guard_active,
		has_skip_chapters = has_skip_chapters, aniskip_ranges = aniskip_ranges, aniskip = aniskip,
		RELEASE_PROP = RELEASE_PROP, NEXT_PROP = NEXT_PROP, same_path = same_path,
		SUJI_MARGINS_PROP = SUJI_MARGINS_PROP, SUJI_GAP = SUJI_GAP,
		SUJI_ENABLED_PROP = SUJI_ENABLED_PROP, SUJI_VERSION_PROP = SUJI_VERSION_PROP, ACTION_ID = ACTION_ID, ACTION_MESSAGE = ACTION_MESSAGE,
		AUTO_MODES = AUTO_MODES, MENU_TYPE = MENU_TYPE, MODE_MESSAGE = MODE_MESSAGE, STATE_PATH = STATE_PATH,
		UNDO_TIME = UNDO_TIME, SETTLE = SETTLE, FLOW_STEP = FLOW_STEP, auto_mode = auto_mode,
		menu_data = menu_data, open_menu = open_menu, set_auto_skip = set_auto_skip,
	}
end
