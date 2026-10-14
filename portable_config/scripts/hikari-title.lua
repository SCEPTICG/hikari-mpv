-- hikari-title: readable titles for anime (and other) releases, local or streamed.
--
-- mpv shows a file's `title` tag, or else its file name. For releases neither
-- reads well: `[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv`, a
-- tag that is just the release group, or, for streaming servers such as
-- Seanime, a whole URL with its token:
--   https://host/<uuid>?token=<secret>&filename=Show.S01E01.1080p.mkv
-- This script sets `force-media-title` to a tidy title instead:
--   Sousou no Frieren · E05        Show · S1 E01 (`T1 E01` in Spanish)
--   Show (2024) · S1 E05 · Episode Title
--
-- Which files get a title:
-- - Local files (plain paths and file:// URLs) with a video extension: the
--   file name, tidied by pretty_title(), but only when it really looks like a
--   release (an episode marker, a technical tail such as `1080p.WEB-DL`, or
--   [group] / (1080p) brackets to drop). Then it wins over the file's `title`
--   tag. Any other name (`Holiday video.mkv`) is left to mpv, which shows the
--   tag or the name.
-- - http(s) URLs with a `filename` query parameter (Seanime and the like): that
--   parameter, decoded, always (it is what names the file there).
-- - http(s) URLs whose last path segment is a video file name that looks like
--   a release (`https://host/files/[SubsPlease] Show - 05 (1080p).mkv`): that
--   segment, as for local files.
-- - Other http(s) URLs with a query: the last path segment without the query
--   (the fallback), so the token never shows; it gives way to a `title` tag.
--   URLs whose only path is `/` but that carry `user:password@` get the bare
--   host. Any other URL (ytdl://, rtsp://, YouTube pages...) is left alone.
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
-- - The `filename` parameter and release-like file names win over the file's
--   `title` tag: they are known before the file opens, they name show and
--   episode, and the tag in these releases is often missing or just the
--   release group.
-- - The fallback is weaker (`stream`, `master.m3u8`, `watch`): if the file
--   turns out to have a `title` tag, it is cleared on `file-loaded` so the tag
--   shows. It still matters until then and for files without a tag, because
--   mpv would otherwise show the basename with its query (`stream?api_key=...`).
-- - The release name rules (tokenizer, markers, pretty_title, release_for)
--   live in script-modules/hikari-release.lua, shared with hikari-resume.lua
--   (continue watching by series), so both read names the same way. What
--   follows describes them.
-- - Release names are recognised token by token (see pretty_title): episode
--   markers (`S01E05`, `E05`, `EP05`, `- 05`, `- 05v2`, `- 12.5`, `Episode 5`,
--   `SP01`, `Special 1`, `OVA`), a season written before the marker (`S2`,
--   `Season 2`, `2nd Season`, `(Season 2)`), the release group in front, the
--   technical tail (resolution, source, codecs, services, CRC) and, when it is
--   clearly there, an episode title after the marker (`- S01E05 - Title`,
--   `S01E05.Title.1080p`). The season and episode labels follow hikari's
--   language (hikari-i18n: `S1 E05`, `T1 E05`, `第1季 第05集`), and the title of
--   the file playing is redone when the language changes. The fallback and
--   playlist titles are never touched: they are not release names.
-- - Every pattern is anchored to a token and input is cut to MAX_RAW before
--   any work, so hostile names cost linear time.
-- - For hikari-skip's AniSkip lookup, the series, season and episode of a
--   release name with one plain episode (`Show - 05`, `Show S2 - 05`,
--   `Show.S02E05`), and whether it looks like anime (a [Group] in front, an
--   anime-only service such as CR after the episode number, or the `- 05`
--   marker with two of resolution, source and CRC after it; only inside
--   brackets or in the technical tail, never in loose words; see
--   looks_like_anime), go to
--   user-data/hikari_title/release on start-file, with the path they are for
--   (`{}` for anything else and after end-file). This does not depend on the
--   options below: they are about the title on screen.
--
-- Options (script-opts/hikari-title.conf): enabled=yes|no, pretty=yes|no
-- (pretty=no: only `filename=` and the fallback, shown as they come).

local msg = require('mp.msg')
local options = require('mp.options')

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

-- Release names: ~~/script-modules/hikari-release.lua (shared with
-- hikari-resume.lua), loaded like the texts above.
local release = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-release')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-release.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

local OPTIONS_ID = 'hikari-title'
-- Series, season and episode of the file playing, for hikari-skip (AniSkip).
local RELEASE_PROP = 'user-data/hikari_title/release'
local MAX_CHARS, MAX_RAW = release.MAX_CHARS, release.MAX_RAW
local url_decode, sanitize, truncate = release.url_decode, release.sanitize, release.truncate
local strip_extension, pretty_title = release.strip_extension, release.pretty_title
local video_file_name, release_for = release.video_file_name, release.release_for

-- ----------------------------------------------------------------------------

-- Sanitized and cut text; with `pretty`, tidied by pretty_title. Returns the
-- title (nil when nothing is left) and whether it looked like a release.
local function clean(text, pretty)
	local title = sanitize(text)
	local is_release = false
	if pretty and title ~= '' then title, is_release = pretty_title(title) end
	title = truncate(title)
	if title == '' then return nil, false end
	return title, is_release
end

local opts = {enabled = true, pretty = true}
options.read_options(opts, OPTIONS_ID)

-- Title for a video file name, only when it looks like a release.
local function release_title(name)
	if not name or not opts.pretty then return nil end
	local title, is_release = clean(name, true)
	if title and is_release then return title end
	return nil
end

-- Title for `path` and where it came from ('filename', 'file' or 'fallback'),
-- or nil when the path should keep mpv's own title.
local function title_for(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme then
		-- A local path (`/x/a.mkv`, `C:\x\a.mkv`, `a.mkv`).
		local title = release_title(video_file_name(path:sub(-MAX_RAW * 4)))
		if title then return title, 'file' end
		return nil
	end
	scheme = scheme:lower()
	if scheme == 'file' then
		local location = path:sub(#scheme + 4):sub(-MAX_RAW * 4)
		local title = release_title(video_file_name(url_decode(location, false)))
		if title then return title, 'file' end
		return nil
	end
	if scheme ~= 'http' and scheme ~= 'https' then return nil end
	local rest = path:sub(#scheme + 4):gsub('#.*$', '')
	local location, query = rest:match('^([^?]*)%?(.*)$')
	location = location or rest
	local authority, route = location:match('^([^/]*)(.*)$')
	local host = authority:gsub('^.*@', '')
	local has_userinfo = host ~= authority

	-- Last path segment, if any. Anchored so the match stays linear on long routes.
	local segment = route:match('^.*/([^/]+)/*$')
	local segment_title = segment and release_title(video_file_name(url_decode(segment:sub(1, MAX_RAW * 4), false)))

	if not query then
		if segment_title then return segment_title, 'file' end
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
			local title = clean(strip_extension(url_decode(value:sub(1, MAX_RAW), true)), opts.pretty)
			if title then return title, 'filename' end
		end
	end
	if segment_title then return segment_title, 'file' end

	-- No usable filename: last path segment, or the host if the path is empty.
	if segment then
		local title = clean(url_decode(segment:sub(1, MAX_RAW), false))
		if title then return title, 'fallback' end
	end
	local title = clean(host:sub(1, MAX_RAW))
	if title then return title, 'fallback' end
	return nil
end

-- Publishes release_for(path) for hikari-skip, with the path it is for: a
-- late reader can tell it apart from the previous file's. `{}` when nothing.
local function publish_release(path)
	local info = path and release_for(path)
	if info then info.path = path end
	mp.set_property_native(RELEASE_PROP, info or {})
end

-- What we set for the current file: the title, and whether it is the weak
-- fallback (file-loaded withdraws it when the file has a title tag).
local current = nil

local function playlist_entry_title()
	local pos = mp.get_property_number('playlist-playing-pos', -1)
	if not pos or pos < 0 then return '' end
	return mp.get_property('playlist/' .. pos .. '/title', '') or ''
end

local function on_start_file()
	current = nil
	local path = mp.get_property_native('path')
	publish_release(type(path) == 'string' and path or nil)
	if not opts.enabled then return end
	local title, source = title_for(path)
	if not title then return end
	local existing = mp.get_property('force-media-title', '')
	if existing ~= nil and existing ~= '' then
		msg.verbose('force-media-title already set, leaving it alone')
		return
	end
	if playlist_entry_title() ~= '' then
		msg.verbose('playlist entry has its own title, leaving it alone')
		return
	end
	mp.set_property('file-local-options/force-media-title', title)
	current = {title = title, fallback = source == 'fallback'}
end

-- A container title beats our fallback. The file-local backup is already taken,
-- so mpv still restores the original value when the file ends.
local function on_file_loaded()
	if not current or not current.fallback then return end
	local tag = mp.get_property('metadata/by-key/title', '')
	if tag ~= nil and tag ~= '' and mp.get_property('force-media-title', '') == current.title then
		mp.set_property('file-local-options/force-media-title', '')
		current = nil
	end
end

-- Another language: the season and episode labels of the title on screen
-- change with it, as long as nothing else has replaced our title meanwhile.
local function on_language_change()
	if not current or current.fallback then return end
	if mp.get_property('force-media-title', '') ~= current.title then return end
	local title = title_for(mp.get_property('path'))
	if title and title ~= current.title then
		mp.set_property('file-local-options/force-media-title', title)
		current.title = title
	end
end

mp.register_event('start-file', on_start_file)
mp.register_event('file-loaded', on_file_loaded)
mp.register_event('end-file', function()
	current = nil
	publish_release(nil)
end)
i18n.on_change(on_language_change)

if HIKARI_TITLE_TEST then
	return {
		title_for = title_for, url_decode = url_decode, sanitize = sanitize,
		truncate = truncate, strip_extension = strip_extension, pretty_title = pretty_title,
		on_start_file = on_start_file, on_file_loaded = on_file_loaded, release_for = release_for,
		RELEASE_PROP = RELEASE_PROP,
		MAX_CHARS = MAX_CHARS, MAX_RAW = MAX_RAW, opts = opts, i18n = i18n,
	}
end
