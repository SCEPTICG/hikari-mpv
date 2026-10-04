-- sosc-title: readable titles for streamed files.
--
-- Streaming servers such as Seanime hand mpv URLs like
--   https://host/<uuid>?token=<secret>&filename=Show.S01E01.1080p.mkv
-- and with no title of its own mpv (and uosc's top bar) shows the whole URL,
-- token included. For http(s) URLs with a query this script sets
-- `force-media-title` to the decoded `filename` parameter without its video
-- extension or, when there is none, to the last path segment without the query
-- (the fallback). URLs whose only path is `/` but that carry `user:password@`
-- get the bare host. Other local files and URLs are left alone.
--
-- Decisions:
-- - Runs on `start-file`, not `file-loaded`, so the title is replaced before
--   the network open instead of after the stream has buffered. mpv assigns
--   `path` before sending the event, so reading it there is reliable. The
--   event is asynchronous, though: the raw URL may still flash for an instant.
--   Hooks that run later (ytdl_hook's on_load, per-file options from a
--   playlist) can still override the title.
-- - Sets `file-local-options/force-media-title`, so mpv itself restores the
--   previous value when the file ends: the title never sticks to the next
--   playlist entry.
-- - Nothing is set if `force-media-title` is already non-empty (set by the
--   user) or the playlist entry has its own title (M3U #EXTINF, IPTV lists).
-- - The `filename` parameter wins over the file's `title` metadata tag: it is
--   known before the file opens, it names show and episode, and the tag in
--   these releases is often missing or just the release group.
-- - The fallback is weaker (`stream`, `master.m3u8`, `watch`): if the file
--   turns out to have a `title` tag, it is cleared on `file-loaded` so the tag
--   shows. It still matters until then and for files without a tag, because
--   mpv would otherwise show the basename with its query (`stream?api_key=...`).
--
-- Options (script-opts/sosc-title.conf): enabled=yes|no

local msg = require('mp.msg')
local options = require('mp.options')

local OPTIONS_ID = 'sosc-title'
local MAX_CHARS = 150
-- Raw input kept before decoding: enough for MAX_CHARS 4-byte characters
-- written as %XX%XX%XX%XX, and a bound on the work done per title.
local MAX_RAW = MAX_CHARS * 12
local ELLIPSIS = '…'

-- Extensions stripped from the end of `filename` (case-insensitive).
local VIDEO_EXTENSIONS = {
	'mkv', 'mp4', 'm4v', 'webm', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'mts',
	'mpg', 'mpeg', 'ogv', '3gp',
}
local VIDEO_EXTENSION_SET = {}
for _, ext in ipairs(VIDEO_EXTENSIONS) do VIDEO_EXTENSION_SET[ext] = true end

-- Decodes %XX sequences; malformed ones are kept as they are. With `plus`, '+'
-- becomes a space (query strings only; in a path '+' is literal).
local function url_decode(text, plus)
	if plus then text = text:gsub('%+', ' ') end
	return (text:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Keeps only valid UTF-8 and drops control and invisible characters: C0, DEL,
-- C1, zero-width and direction marks, line and paragraph separators, bidi
-- overrides and isolates, BOM. Newlines and tabs become spaces.
local function sanitize(text)
	local out = {}
	local i, len = 1, #text
	while i <= len do
		local c = text:byte(i)
		local size, min
		if c < 0x80 then size, min = 1, 0
		elseif c >= 0xC2 and c <= 0xDF then size, min = 2, 0x80
		elseif c >= 0xE0 and c <= 0xEF then size, min = 3, 0x800
		elseif c >= 0xF0 and c <= 0xF4 then size, min = 4, 0x10000
		end
		local code
		if size and i + size - 1 <= len then
			code = size == 1 and c or c % (2 ^ (7 - size))
			for j = i + 1, i + size - 1 do
				local b = text:byte(j)
				if b < 0x80 or b > 0xBF then code = nil break end
				code = code * 64 + b % 64
			end
			if code and (code < min or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF)) then code = nil end
		end
		if not code then
			i = i + 1 -- invalid byte: drop it
		else
			if code == 9 or code == 10 or code == 13 then
				out[#out + 1] = ' '
			elseif not (code < 32 or code == 127 or (code >= 0x80 and code <= 0x9F)
				or code == 0x061C or (code >= 0x200B and code <= 0x200F) or code == 0xFEFF
				or code == 0x2028 or code == 0x2029
				or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069)) then
				out[#out + 1] = text:sub(i, i + size - 1)
			end
			i = i + size
		end
	end
	return (table.concat(out):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

-- Cuts to MAX_CHARS characters (not bytes), never inside a UTF-8 sequence.
-- Expects sanitized (valid UTF-8) input.
local function truncate(text)
	local count, i = 0, 1
	while i <= #text do
		count = count + 1
		if count > MAX_CHARS then
			return text:sub(1, i - 1):gsub(' $', '') .. ELLIPSIS
		end
		local c = text:byte(i)
		i = i + (c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4)
	end
	return text
end

local function strip_extension(name)
	local base, ext = name:match('^(.+)%.([%w]+)$')
	if base and VIDEO_EXTENSION_SET[ext:lower()] then return base end
	return name
end

local function clean(text)
	local title = truncate(sanitize(text))
	return title ~= '' and title or nil
end

-- Title for `path` and where it came from ('filename' or 'fallback'), or nil
-- when the path should keep mpv's own title.
local function title_for(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme or (scheme:lower() ~= 'http' and scheme:lower() ~= 'https') then return nil end
	local rest = path:sub(#scheme + 4):gsub('#.*$', '')
	local location, query = rest:match('^([^?]*)%?(.*)$')
	location = location or rest
	local authority, route = location:match('^([^/]*)(.*)$')
	local host = authority:gsub('^.*@', '')
	local has_userinfo = host ~= authority

	if not query then
		-- Credentials in the URL and no path to show instead: the bare host.
		if has_userinfo and route:match('^/*$') then
			local title = clean(host:sub(1, MAX_RAW))
			if title then return title, 'fallback' end
		end
		return nil
	end

	for pair in query:gmatch('[^&;]+') do
		local key, value = pair:match('^([^=]*)=(.*)$')
		if key and url_decode(key:sub(1, MAX_RAW), true) == 'filename' then
			local title = clean(strip_extension(url_decode(value:sub(1, MAX_RAW), true)))
			if title then return title, 'filename' end
		end
	end

	-- No usable filename: last path segment, or the host if the path is empty.
	-- Anchored so the match stays linear on long routes.
	local segment = route:match('^.*/([^/]+)/*$')
	if segment then
		local title = clean(url_decode(segment:sub(1, MAX_RAW), false))
		if title then return title, 'fallback' end
	end
	local title = clean(host:sub(1, MAX_RAW))
	if title then return title, 'fallback' end
	return nil
end

local opts = {enabled = true}
options.read_options(opts, OPTIONS_ID)

-- Fallback title we set for the current file, so file-loaded can withdraw it.
local fallback_title = nil

local function playlist_entry_title()
	local pos = mp.get_property_number('playlist-playing-pos', -1)
	if not pos or pos < 0 then return '' end
	return mp.get_property('playlist/' .. pos .. '/title', '') or ''
end

local function on_start_file()
	fallback_title = nil
	if not opts.enabled then return end
	local title, source = title_for(mp.get_property('path'))
	if not title then return end
	local current = mp.get_property('force-media-title', '')
	if current ~= nil and current ~= '' then
		msg.verbose('force-media-title already set, leaving it alone')
		return
	end
	if playlist_entry_title() ~= '' then
		msg.verbose('playlist entry has its own title, leaving it alone')
		return
	end
	mp.set_property('file-local-options/force-media-title', title)
	if source == 'fallback' then fallback_title = title end
end

-- A container title beats our fallback. The file-local backup is already taken,
-- so mpv still restores the original value when the file ends.
local function on_file_loaded()
	if not fallback_title then return end
	local tag = mp.get_property('metadata/by-key/title', '')
	if tag ~= nil and tag ~= '' and mp.get_property('force-media-title', '') == fallback_title then
		mp.set_property('file-local-options/force-media-title', '')
	end
	fallback_title = nil
end

mp.register_event('start-file', on_start_file)
mp.register_event('file-loaded', on_file_loaded)

if SOSC_TITLE_TEST then
	return {
		title_for = title_for, url_decode = url_decode, sanitize = sanitize,
		truncate = truncate, strip_extension = strip_extension,
		on_start_file = on_start_file, on_file_loaded = on_file_loaded,
		MAX_CHARS = MAX_CHARS, MAX_RAW = MAX_RAW, opts = opts,
	}
end
