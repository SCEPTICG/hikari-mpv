-- Run from the repository root: lua tests/test_skip.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/sosc-skip.lua'
local SCRIPT_NAME = 'sosc_skip'

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. '\n     ' .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error((what or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
end

-- Loads the script with fresh mocks; `opts` are the script-opts mpv would pass.
local function load(opts)
	mock.install(SCRIPT_NAME)
	mock.script_opts = opts or {}
	SOSC_SKIP_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function chapters(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = {time = c[1], title = c[2]} end
	return out
end

-- A typical episode: cold open, OP, part A, ED, preview.
local EPISODE = chapters({
	{0, 'Prologue'}, {90, 'Opening'}, {180, 'Part A'}, {1300, 'Ending'}, {1390, 'Preview'},
})

-- Loads the script with a 1280x720 OSD and an episode loaded at `time`.
local function play(time, list, opts)
	local s = load(opts)
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('duration', 1420)
	mock.set('chapter-list', list or EPISODE)
	mock.set('time-pos', time)
	return s
end

local function overlay(s) return s.overlay end
local function section(s) return mock.sections[s.MOUSE_SECTION] end
local function center(rect) return {x = (rect.x0 + rect.x1) / 2, y = (rect.y0 + rect.y1) / 2, hover = true} end

-- Classification ----------------------------------------------------------------

test('openings and endings are recognised like uosc (plus Japanese)', function()
	local s = load()
	for _, title in ipairs({'OP', 'op', 'Opening', '  OPENING  ', 'OP Theme', 'Episode 1 OP',
		'Main Opening', 'オープニング', 'オープニングテーマ'}) do
		local kind = s.classify(title)
		eq(kind and kind.name, 'openings', title)
	end
	for _, title in ipairs({'ED', 'ed', 'Ending', 'ENDING', 'Ending Theme', 'ED 1', 'Episode 1 ED',
		'Main Ending', 'エンディング'}) do
		local kind = s.classify(title)
		eq(kind and kind.name, 'endings', title)
	end
end)

test('lookalike titles are not openings or endings', function()
	local s = load()
	for _, title in ipairs({'Operation', 'Opening Night Part', 'Openings', 'OP1', 'Top', 'Edward',
		'Edge', 'Bed', 'Endings', 'Pending', 'The End', 'Part A', '', 'Chapter 1'}) do
		eq(s.classify(title), nil, title)
	end
	eq(s.classify(nil), nil, 'nil title')
	eq(s.classify(42), nil, 'number title')
end)

test('intros and outros are off by default', function()
	local s = load()
	for _, title in ipairs({'Intro', 'Avant', 'Prologue', 'Outro', 'Closing', 'Preview', 'PV'}) do
		eq(s.classify(title), nil, title)
	end
end)

test('intros and outros can be enabled, openings and endings disabled', function()
	local s = load({['sosc-skip-intros'] = 'yes', ['sosc-skip-outros'] = 'yes',
		['sosc-skip-openings'] = 'no', ['sosc-skip-endings'] = 'no'})
	for _, title in ipairs({'Intro', 'Cold intro', 'Avant', 'Prologue'}) do
		eq(s.classify(title).name, 'intros', title)
	end
	for _, title in ipairs({'Outro', 'Closing', 'Closing Credits', 'Preview', 'PV'}) do
		eq(s.classify(title).name, 'outros', title)
	end
	eq(s.classify('OP'), nil, 'openings disabled')
	eq(s.classify('Ending'), nil, 'endings disabled')
	eq(s.classify('Intro').label, 'Saltar intro ›')
	eq(s.classify('Preview').label, 'Saltar avance ›')
end)

test('extra patterns are added; malformed ones are ignored safely', function()
	local s = load({['sosc-skip-extra_openings'] = '^op%d+$|^opening %d+$|[',
		['sosc-skip-extra_endings'] = '^credits$'})
	eq(s.classify('OP1').name, 'openings')
	eq(s.classify('Opening 2').name, 'openings')
	eq(s.classify('Credits').name, 'endings')
	eq(s.classify('Part A'), nil, 'malformed pattern does not match or crash')
end)

test('very long titles are cut before matching', function()
	local s = load()
	eq(s.classify(string.rep('a', 500) .. ' op'), nil, 'match past the cut')
	eq(s.classify('OP ' .. string.rep('x', 500)).name, 'openings')
end)

-- Ranges ------------------------------------------------------------------------

test('ranges: opening to next chapter, ending to next chapter', function()
	local s = load()
	local ranges = s.build_ranges(EPISODE, 1420)
	eq(#ranges, 2)
	eq(ranges[1].kind.name, 'openings'); eq(ranges[1].start, 90); eq(ranges[1].finish, 180)
	eq(ranges[1].next_time, 180)
	eq(ranges[2].kind.name, 'endings'); eq(ranges[2].start, 1300); eq(ranges[2].finish, 1390)
end)

test('an opening as last chapter does not count; an ending does', function()
	local s = load()
	eq(#s.build_ranges(chapters({{0, 'Part A'}, {500, 'OP'}}), 600), 0, 'last opening')
	local ranges = s.build_ranges(chapters({{0, 'Part A'}, {500, 'ED'}}), 600)
	eq(#ranges, 1)
	eq(ranges[1].finish, 600, 'ends at duration'); eq(ranges[1].next_time, nil)
	eq(s.build_ranges(chapters({{0, 'Part A'}, {500, 'ED'}}), nil)[1].finish, math.huge, 'unknown duration')
end)

test('chapters out of order are sorted; junk entries are skipped', function()
	local s = load()
	local list = {{time = 180, title = 'Part A'}, {time = 90, title = 'OP'}, {title = 'no time'},
		'junk', {time = 0 / 0, title = 'NaN'}, {time = 0, title = 'Cold open'}}
	local ranges = s.build_ranges(list, 1000)
	eq(#ranges, 1); eq(ranges[1].start, 90); eq(ranges[1].finish, 180)
	eq(#s.build_ranges(nil, 100), 0); eq(#s.build_ranges('x', 100), 0)
end)

test('current range by time, with its edges', function()
	local s = load()
	local ranges = s.build_ranges(EPISODE, 1420)
	eq(s.range_at(ranges, 89.9), nil, 'before')
	eq(s.range_at(ranges, 90), 1, 'start edge')
	eq(s.range_at(ranges, 150), 1, 'inside')
	eq(s.range_at(ranges, 180 - s.END_MARGIN - 0.01), 1, 'just before the end margin')
	eq(s.range_at(ranges, 180 - s.END_MARGIN), nil, 'end margin')
	eq(s.range_at(ranges, 180), nil, 'next chapter')
	eq(s.range_at(ranges, 1350), 2, 'ending')
	eq(s.range_at(ranges, nil), nil, 'no time')
end)

-- Visibility and drawing --------------------------------------------------------

test('without chapters nothing is drawn and time-pos is not observed', function()
	local s = load()
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('chapter-list', {})
	eq(mock.observers['time-pos'] == nil or #mock.observers['time-pos'] == 0, true, 'no time-pos observer')
	mock.set('chapter-list', chapters({{0, 'A'}, {100, 'B'}}))
	eq(mock.observers['time-pos'] == nil or #mock.observers['time-pos'] == 0, true, 'none either')
	eq(overlay(s).updates, 0)
end)

test('the button is visible only inside the range', function()
	local s = play(10)
	eq(s.is_visible(), false, 'before'); eq(overlay(s).updates, 0)
	mock.set('time-pos', 95)
	eq(s.is_visible(), true, 'inside'); eq(overlay(s).visible, true)
	assert(overlay(s).data:find('Saltar opening ›', 1, true), 'opening label')
	eq(overlay(s).res_x, 1280); eq(overlay(s).res_y, 720)
	mock.set('time-pos', 200)
	eq(s.is_visible(), false, 'after'); eq(overlay(s).visible, false)
	mock.set('time-pos', 1310)
	assert(overlay(s).data:find('Saltar ending ›', 1, true), 'ending label')
end)

test('no redraw on every time-pos inside the range', function()
	local s = play(95)
	local updates = overlay(s).updates
	for t = 96, 170 do mock.set('time-pos', t) end
	eq(overlay(s).updates, updates, 'same range, no redraw')
	mock.set('time-pos', 300)
	mock.set('time-pos', 301)
	eq(overlay(s).removes, 1, 'removed once')
end)

test('stays visible when paused, hides when idle or a menu is open', function()
	local s = play(95)
	mock.set('pause', true)
	eq(s.is_visible(), true, 'paused')
	mock.set('user-data/uosc/menu/type', 'sosc-speed')
	eq(s.is_visible(), false, 'uosc menu'); eq(overlay(s).visible, false)
	mock.set('user-data/uosc/menu/type', nil)
	eq(s.is_visible(), true, 'menu closed'); eq(overlay(s).visible, true)
	mock.set('user-data/mpv/console/open', true)
	eq(s.is_visible(), false, 'console')
	mock.set('user-data/mpv/console/open', false)
	mock.set('idle-active', true)
	eq(s.is_visible(), false, 'idle')
end)

test('layout sits above uosc bar at the bottom right and scales', function()
	local s = play(95)
	local r = s.layout()
	eq(r.x1, 1280 - 16); eq(r.y1, 720 - 96)
	assert(r.x0 < r.x1 and r.y0 < r.y1, 'non-empty')
	assert(720 - r.y1 > 81, 'clears uosc default timeline + controls (81 px)')
	mock.set('fullscreen', true)
	local f = s.layout()
	eq(f.x1, 1280 - math.floor(16 * 1.3 + 0.5)); eq(f.y1, 720 - math.floor(96 * 1.3 + 0.5))
	assert(f.font_size > r.font_size, 'bigger in fullscreen')
	mock.set('fullscreen', false)
	mock.set('display-hidpi-scale', 2)
	eq(s.layout().y1, 720 - 192, 'hidpi')
	mock.set('osd-dimensions', {w = 1920, h = 1080})
	eq(overlay(s).res_x, 1920, 'redrawn for new size')
end)

test('margins are configurable', function()
	local s = play(95, nil, {['sosc-skip-margin_bottom'] = '150', ['sosc-skip-margin_right'] = '40'})
	local r = s.layout()
	eq(r.x1, 1280 - 40); eq(r.y1, 720 - 150)
end)

-- Colours -----------------------------------------------------------------------

test('colours come from uosc-color in BGR, with defaults', function()
	local s = load()
	local c = s.parse_colors({['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12,background=112233,background_text=e6edf3'})
	eq(c.foreground, '5ad4e6'); eq(c.background, '112233')
	eq(s.to_bgr('112233'), '332211'); eq(s.to_bgr('5ad4e6'), 'E6D45A')
	local d = s.parse_colors({})
	eq(d.foreground, 'ffffff'); eq(d.background, '000000')
	local bad = s.parse_colors({['uosc-color'] = 'foreground=zzzzzz,background=#ABCDEF,evil=000000'})
	eq(bad.foreground, 'ffffff', 'malformed ignored'); eq(bad.background, 'abcdef'); eq(bad.evil, nil)
	eq(s.parse_colors(nil).foreground, 'ffffff')
	eq(s.to_alpha(1), '00'); eq(s.to_alpha(0), 'FF'); eq(s.to_alpha(0.85), '26')
end)

test('drawing uses the active palette and changes it on the fly', function()
	local s = play(95)
	mock.set('script-opts', {['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12,background=112233,background_text=e6edf3'})
	local data = overlay(s).data
	assert(data:find('\\1c&H332211&', 1, true), 'background fill in BGR')
	assert(data:find('\\3c&HE6D45A&', 1, true), 'foreground border in BGR')
	assert(data:find('\\1c&HF3EDE6&', 1, true), 'background_text label')
	assert(data:find('\\1a&H26&', 1, true), 'background opacity 0.85')
	mock.set('script-opts', {['uosc-color'] = 'background=000000'})
	assert(overlay(s).data:find('\\1c&H000000&', 1, true), 'repainted')
end)

test('hover fills with foreground and uses foreground_text', function()
	local s = play(95)
	mock.set('script-opts', {['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12'})
	mock.set('mouse-pos', center(s.layout()))
	local data = overlay(s).data
	assert(data:find('\\1c&HE6D45A&\\1a&H00&', 1, true), 'foreground fill, opaque')
	assert(data:find('\\1c&H120D0B&', 1, true), 'foreground_text label')
end)

test('ASS text is escaped', function()
	local s = load()
	eq(s.ass_escape('a{\\b1}b'), 'a\\{\\\239\187\191b1\\}b')
	eq(s.ass_escape('x\ny'), 'x y')
end)

-- Mouse and keyboard ------------------------------------------------------------

test('the click section is enabled only over the visible button', function()
	local s = play(95)
	local sec = section(s)
	eq(sec.flags, 'force')
	eq(sec.enabled, false, 'not hovering')
	local r = s.layout()
	mock.set('mouse-pos', {x = 10, y = 10, hover = true})
	eq(sec.enabled, false, 'elsewhere')
	mock.set('mouse-pos', center(r))
	eq(sec.enabled, true, 'over the button')
	eq(sec.enable_flags, '', 'no window dragging')
	mock.set('mouse-pos', {x = r.x0 - 1, y = r.y0, hover = true})
	eq(sec.enabled, false, 'left the button')
	mock.set('mouse-pos', center(r))
	mock.set('mouse-pos', {x = center(r).x, y = center(r).y, hover = false})
	eq(sec.enabled, false, 'pointer left the window')
end)

test('the section is released when the button hides or the file ends', function()
	local s = play(95)
	mock.set('mouse-pos', center(s.layout()))
	eq(section(s).enabled, true)
	mock.set('time-pos', 200)
	eq(section(s).enabled, false, 'hidden')
	eq(#mock.observers['mouse-pos'], 0, 'mouse-pos no longer observed')
	mock.set('time-pos', 95)
	mock.set('mouse-pos', center(s.layout()))
	eq(section(s).enabled, true)
	mock.events['end-file']()
	eq(section(s).enabled, false, 'end of file')
	eq(overlay(s).visible, false, 'overlay removed')
	mock.set('time-pos', 95)
	eq(s.is_visible(), false, 'no chapters after end-file')
end)

test('mouse bindings: release on the button skips, double click is swallowed', function()
	local s = play(95)
	local sec = section(s)
	eq(sec.bindings[1][1], 'mbtn_left')
	eq(sec.bindings[2][1], 'mbtn_left_dbl'); eq(sec.bindings[2][2], 'ignore')
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	mock.set('mouse-pos', center(s.layout()))
	on_down()
	eq(#mock.commands, 0, 'nothing on press')
	on_up()
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[1], 'seek'); eq(c[2], '180.000'); eq(c[3], 'absolute+exact')
	eq(s.is_visible(), false, 'hidden right after skipping')
	eq(sec.enabled, false, 'section released')
end)

test('press on the button and release outside does not skip', function()
	local s = play(95)
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	local r = s.layout()
	mock.set('mouse-pos', center(r))
	on_down()
	mock.set('mouse-pos', {x = 5, y = 5, hover = true})
	eq(sec.enabled, true, 'kept until release')
	on_up()
	eq(#mock.commands, 0, 'no skip')
	eq(sec.enabled, false, 'released')
end)

test('section held while pressed even if the button hides, then released', function()
	local s = play(95)
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	mock.set('mouse-pos', center(s.layout()))
	on_down()
	mock.set('time-pos', 200)
	eq(sec.enabled, true, 'up event still ours')
	on_up()
	eq(#mock.commands, 0, 'no skip once hidden')
	eq(sec.enabled, false)
end)

test('keyboard binding skips only while visible', function()
	local s = play(10)
	assert(mock.bindings.skip, 'skip binding')
	mock.bindings.skip()
	eq(#mock.commands, 0, 'outside the range')
	mock.set('time-pos', 1300.5)
	mock.bindings.skip()
	eq(#mock.commands, 1)
	eq(mock.commands[1][2], '1390.000')
	mock.bindings.skip()
	eq(#mock.commands, 1, 'dismissed: second press ignored')
end)

test('dismissed range comes back after leaving and re-entering it', function()
	local s = play(95)
	mock.bindings.skip()
	mock.set('time-pos', 170) -- seek landed short of the next chapter
	eq(s.is_visible(), false, 'still dismissed')
	mock.set('time-pos', 181)
	mock.set('time-pos', 100) -- user seeks back into the opening
	eq(s.is_visible(), true, 'shown again')
end)

test('ending as last chapter: next playlist entry if there is one', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 3
	mock.bindings.skip()
	eq(#mock.commands, 1); eq(mock.commands[1][1], 'playlist-next')
	eq(s.is_visible(), false)
end)

test('ending as last chapter with nothing next: seek near the end', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 1
	mock.bindings.skip()
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[1], 'seek'); eq(c[2], '1419.000'); eq(c[3], 'absolute+exact')
	eq(s.is_visible(), false, 'button gone while the last second plays')
end)

test('times are formatted with a dot whatever the locale', function()
	local s = load()
	eq(s.format_time(90), '90.000'); eq(s.format_time(1.2345), '1.235'); eq(s.format_time(-3), '0.000')
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
