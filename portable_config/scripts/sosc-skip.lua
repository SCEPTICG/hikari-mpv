-- sosc-skip: "skip opening / ending" button for uosc.
--
-- While playback is inside a chapter that looks like an opening or an ending,
-- a rounded button is drawn at the bottom right, above uosc's controls and
-- timeline. Clicking it (or the `skip` binding) jumps to the start of the next
-- chapter. Outside those chapters, and in files without chapters, nothing is
-- drawn and no input is taken.
--
-- mpv turns this file name into the script name `sosc_skip`, so:
--   input.conf:  <key> script-binding sosc_skip/skip
--
-- Decisions:
-- - Chapters are classified with the same title patterns uosc uses for its
--   chapter ranges (lib/utils.lua, serialize_chapter_ranges), plus the Japanese
--   words. An opening or intro only counts when another chapter follows it.
-- - Layout is in real OSD pixels times a scale factor, like uosc does
--   (hidpi * scale, or scale_fullscreen when fullscreen or maximized), so the
--   button keeps its place above uosc's bar in any window size. The default
--   margin_bottom clears uosc's default bottom stack: timeline 40 + timeline
--   border 1 + controls margin 8 + controls 32 = 81, plus a 15 px gap.
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
-- - Chapter titles come from the file: they are only cut to MAX_TITLE bytes and
--   compared with patterns, never shown.
--
-- Options (script-opts/sosc-skip.conf): see that file.

local msg = require('mp.msg')
local options = require('mp.options')

local OPTIONS_ID = 'sosc-skip'
-- Input section names are global to mpv, so ours carries the script name.
local MOUSE_SECTION = mp.get_script_name() .. '_button'
local MAX_TITLE = 200
-- The button hides this many seconds before the next chapter starts, so a
-- frame that lands just short of the boundary does not keep it on screen.
local END_MARGIN = 0.25
-- Average glyph width as a fraction of the font size, to size the box.
local CHAR_WIDTH = 0.52

local opts = {
	openings = true,
	endings = true,
	intros = false,
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
}
options.read_options(opts, OPTIONS_ID)

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

-- Order matters: the first kind whose patterns match wins.
local KINDS = {
	{
		name = 'openings', label = 'Saltar opening ›', requires_next = true,
		patterns = {'^op ', '^op$', ' op$', '^opening$', ' opening$'},
		words = {'オープニング'},
	},
	{
		name = 'intros', label = 'Saltar intro ›', requires_next = true,
		patterns = {'^intro$', ' intro$', '^avant$', '^prologue$'},
		words = {},
	},
	{
		name = 'endings', label = 'Saltar ending ›',
		patterns = {'^ed ', '^ed$', ' ed$', '^ending ', '^ending$', ' ending$'},
		words = {'エンディング'},
	},
	{
		name = 'outros', label = 'Saltar avance ›',
		patterns = {'^outro$', ' outro$', '^closing$', '^closing ', '^preview$', '^pv$'},
		words = {},
	},
}

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

-- Kind for a chapter title, or nil. Lower-case, trimmed, cut to MAX_TITLE.
local function classify(title)
	if type(title) ~= 'string' then return nil end
	local text = title:sub(1, MAX_TITLE):lower():gsub('^%s+', ''):gsub('%s+$', '')
	for _, kind in ipairs(KINDS) do
		if kind.enabled then
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

local function utf8_length(text)
	local _, count = text:gsub('[^\128-\191]', '')
	return count
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

-- State -------------------------------------------------------------------------

local state = {
	chapters = nil, duration = nil, ranges = {},
	-- dismissed: {start, target} of the range skipped last; `target` is where
	-- the skip seeked to (nil for playlist-next).
	time = nil, current = nil, dismissed = nil,
	guard_until = nil, guard_timer = nil, -- double-click guard after a mouse skip
	idle = false, menu_open = false, console_open = false, context_menu_open = false,
	osd_w = 0, osd_h = 0,
	fullscreen = false, maximized = false, hidpi = 1,
	colors = parse_colors(nil),
	mouse = nil, hovered = false, pressed = false, guard_press = false, section_enabled = false,
	drawn = nil, -- last data sent to the overlay, nil when nothing is drawn
}

local overlay = mp.create_osd_overlay('ass-events')

local function is_dismissed(index)
	local range = index and state.ranges[index]
	return range ~= nil and state.dismissed ~= nil and state.dismissed.start == range.start
end

local function is_visible()
	return state.current ~= nil and not is_dismissed(state.current)
		and not state.idle and not state.menu_open and not state.console_open and not state.context_menu_open
		and state.osd_w > 0 and state.osd_h > 0
end

local function current_scale()
	local base = (state.fullscreen or state.maximized) and opts.scale_fullscreen or opts.scale
	return (state.hidpi > 0 and state.hidpi or 1) * base
end

-- Button rectangle in OSD pixels, or nil when hidden.
local function layout()
	if not is_visible() then return nil end
	local label = state.ranges[state.current].kind.label
	local s = current_scale()
	local fs = round(opts.font_size * s)
	local pad_x, pad_y = round(fs * 0.8), round(fs * 0.5)
	local w = round(utf8_length(label) * fs * CHAR_WIDTH) + pad_x * 2
	local h = fs + pad_y * 2
	local x1 = state.osd_w - round(opts.margin_right * s)
	local y1 = state.osd_h - round(opts.margin_bottom * s)
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

-- Brings overlay, hover state and click section in line with the state.
local function refresh()
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

-- Recomputes which range we are in; redraws only when that changes.
local function update_current()
	local index = range_at(state.ranges, state.time)
	local dismissed = state.dismissed
	-- Back before the skipped range's start (or out of it): it shows again.
	if dismissed and (not is_dismissed(index) or (state.time and state.time < dismissed.start)) then
		state.dismissed = nil
	end
	if index == state.current and state.dismissed == dismissed then return end
	state.current = index
	refresh()
end

local function on_time(_, time)
	state.time = time
	update_current()
end

local time_watched = false

local function rebuild()
	state.ranges = build_ranges(state.chapters, state.duration)
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
	-- No skippable chapters: do not even listen to time-pos.
	if #state.ranges > 0 and not time_watched then
		mp.observe_property('time-pos', 'number', on_time)
		time_watched = true
		state.time = mp.get_property_number('time-pos')
	elseif #state.ranges == 0 and time_watched then
		mp.unobserve_property(on_time)
		time_watched = false
	end
	state.current = range_at(state.ranges, state.time)
	refresh()
end

-- Seconds as `12.345`, built from integers so the decimal separator never
-- depends on the C locale.
local function format_time(seconds)
	local ms = math.max(0, round(seconds * 1000))
	return string.format('%d.%03d', math.floor(ms / 1000), ms % 1000)
end

-- Skips the current range. Returns true if it did something.
local function skip()
	if not is_visible() then return false end
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
	mp.commandv('seek', format_time(target), 'absolute+exact')
	refresh()
	return true
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

-- Forgets everything about the file that just ended. The double-click guard
-- is about input, not the file, so it is left running: after a skip with
-- playlist-next, end-file arrives before the second click does. Its timer
-- (2 s at most) turns it off.
local function reset()
	state.chapters, state.duration, state.time = nil, nil, nil
	state.pressed, state.dismissed = false, nil
	rebuild()
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
mp.observe_property('user-data/mpv/console/open', 'bool', setter('console_open', truthy))
mp.observe_property('user-data/mpv/context-menu/open', 'bool', setter('context_menu_open', truthy))
mp.register_event('end-file', reset)
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

if SOSC_SKIP_TEST then
	return {
		KINDS = KINDS, opts = opts, state = state, overlay = overlay, MOUSE_SECTION = MOUSE_SECTION,
		classify = classify, build_ranges = build_ranges, range_at = range_at,
		parse_colors = parse_colors, to_bgr = to_bgr, to_alpha = to_alpha, ass_escape = ass_escape,
		layout = layout, is_visible = is_visible, skip = skip, format_time = format_time,
		on_down = on_down, on_up = on_up, END_MARGIN = END_MARGIN, guard_active = guard_active,
	}
end
