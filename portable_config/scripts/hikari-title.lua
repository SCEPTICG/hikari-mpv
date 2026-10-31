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
-- - With suji 0.7.0 or newer turned on, a title with an episode marker also
--   goes to suji in its parts: `script-message-to suji set-title <series>
--   <episode> [<name>]`, the episode being the same label as on screen
--   (`T1 E05`) and the name only when there is one. suji shows them on two
--   lines; force-media-title stays as it is, for uosc, the window and the
--   rest. A title without an episode (a film, a name with no marker, the
--   fallback, pretty=no) is not sent: suji then shows media-title, which is
--   that same title, on one line. Each part is sanitized with the rest of the
--   name and cut to MAX_CHARS (suji cuts at 200), and goes as its own
--   argument of mp.commandv. Whether suji counts is decided as hikari-skip
--   does for show-action: user-data/suji/enabled is true and its version
--   (user-data/suji/version, or else the last `suji-version` message) has
--   major.minor 0.7 or more. It is read live each time, never while this
--   script loads: on start-file suji may not have set it yet, so the
--   observers of both properties (and the message) send it once it is there.
--   suji clears the title on its end-file, which comes before our start-file,
--   so it is sent again for each file. It is sent only while
--   force-media-title is still our title: when the user, the playlist entry
--   or a later hook set another one, or the fallback is withdrawn, nothing is
--   sent, and a title already sent is taken back with `set-title "" ""`
--   (suji goes back to media-title). The same happens when suji is turned
--   off; turned on again, the title is sent again. A new language sends the
--   new labels.
--
-- Options (script-opts/hikari-title.conf): enabled=yes|no, pretty=yes|no
-- (pretty=no: only `filename=` and the fallback, shown as they come).

local msg = require('mp.msg')
local options = require('mp.options')

-- hikari's modules in ~~/script-modules. Single-file scripts get no mpv folder
-- in package.path, so the folder is added for each require and taken out again
-- (see the header of hikari-i18n.lua). An optional one that cannot be loaded
-- is a warning and nil, not an error.
local function load_module(name, optional)
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		if optional then return nil end
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, name)
	package.path = saved
	if not ok then
		local text = 'hikari: cannot load script-modules/' .. name .. '.lua (reinstall hikari): ' .. tostring(module)
		if optional then
			msg.warn(text)
			return nil
		end
		error(text)
	end
	return module
end

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua.
local i18n = load_module('hikari-i18n')

-- Release names: ~~/script-modules/hikari-release.lua (shared with
-- hikari-resume.lua), loaded like the texts above.
local release = load_module('hikari-release')

local OPTIONS_ID = 'hikari-title'
-- suji (0.7.0 or newer) shows a title in parts: whether it is on, and its version.
local SUJI_ENABLED_PROP = 'user-data/suji/enabled'
local SUJI_VERSION_PROP = 'user-data/suji/version'
-- Series, season and episode of the file playing, for hikari-skip (AniSkip).
local RELEASE_PROP = 'user-data/hikari_title/release'
local MAX_CHARS, MAX_RAW = release.MAX_CHARS, release.MAX_RAW
local url_decode, sanitize, truncate = release.url_decode, release.sanitize, release.truncate
local strip_extension, pretty_title = release.strip_extension, release.pretty_title
local video_file_name, release_for = release.video_file_name, release.release_for

-- ----------------------------------------------------------------------------

-- Sanitized and cut text; with `pretty`, tidied by pretty_title. Returns the
-- title (nil when nothing is left), whether it looked like a release and, for
-- a release with an episode marker, its parts for suji, each one cut too.
local function clean(text, pretty)
	local title = sanitize(text)
	local is_release, parts = false, nil
	if pretty and title ~= '' then
		local _
		title, is_release, _, parts = pretty_title(title)
	end
	title = truncate(title)
	if title == '' then return nil, false end
	if parts then
		parts = {series = truncate(parts.series), episode = truncate(parts.episode),
			name = parts.name and truncate(parts.name)}
	end
	return title, is_release, parts
end

local opts = {enabled = true, pretty = true}
options.read_options(opts, OPTIONS_ID)

-- Title for a video file name, only when it looks like a release, and its
-- parts (see clean).
local function release_title(name)
	if not name or not opts.pretty then return nil end
	local title, is_release, parts = clean(name, true)
	if title and is_release then return title, parts end
	return nil
end

-- Title for `path`, where it came from ('filename', 'file' or 'fallback') and
-- its parts for suji (nil without an episode marker), or nil when the path
-- should keep mpv's own title.
local function title_for(path)
	if type(path) ~= 'string' then return nil end
	local scheme = path:match('^(%a[%w+.-]*)://')
	if not scheme then
		-- A local path (`/x/a.mkv`, `C:\x\a.mkv`, `a.mkv`).
		local title, parts = release_title(video_file_name(path:sub(-MAX_RAW * 4)))
		if title then return title, 'file', parts end
		return nil
	end
	scheme = scheme:lower()
	if scheme == 'file' then
		local location = path:sub(#scheme + 4):sub(-MAX_RAW * 4)
		local title, parts = release_title(video_file_name(url_decode(location, false)))
		if title then return title, 'file', parts end
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
	-- Path parameters (`;jsessionid=...`) can carry a session: never in the title.
	local had_params = false
	if segment then
		local cut = segment:gsub(';.*$', '')
		had_params = cut ~= segment
		segment = cut ~= '' and cut or nil
	end
	local segment_title, segment_parts
	if segment then
		segment_title, segment_parts = release_title(video_file_name(url_decode(segment:sub(1, MAX_RAW * 4), false)))
	end

	if not query then
		if segment_title then return segment_title, 'file', segment_parts end
		-- mpv's own title would be the whole segment, parameters included.
		if had_params and segment then
			local title = clean(url_decode(segment:sub(1, MAX_RAW), false))
			if title then return title, 'fallback' end
		end
		-- Credentials or path parameters in the URL, and no path to show
		-- instead: the bare host.
		if (has_userinfo and route:match('^/*$')) or had_params then
			local title = clean(host:sub(1, MAX_RAW))
			if title then return title, 'fallback' end
		end
		return nil
	end

	for pair in query:gmatch('[^&;]+') do
		local key, value = pair:match('^([^=]*)=(.*)$')
		if key and url_decode(key:sub(1, MAX_RAW), true) == 'filename' then
			local title, _, parts = clean(strip_extension(url_decode(value:sub(1, MAX_RAW), true)), opts.pretty)
			if title then return title, 'filename', parts end
		end
	end
	if segment_title then return segment_title, 'file', segment_parts end

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

-- What we set for the current file: the title, whether it is the weak
-- fallback (file-loaded withdraws it when the file has a title tag) and its
-- parts for suji (nil without an episode).
local current = nil

-- suji's version from its last `suji-version` message (suji 0.3.0 does not
-- publish the property), and the parts sent to suji for this file, as one
-- text (nil: suji holds no title of ours).
local suji_announced = nil
local suji_sent = nil

-- suji is on and understands set-title with parts (0.7.0 or newer). The
-- property wins over the message when it is there, as in hikari-skip.
local function suji_titles()
	if mp.get_property_native(SUJI_ENABLED_PROP) ~= true then return false end
	local version = mp.get_property_native(SUJI_VERSION_PROP)
	if version == nil then version = suji_announced end
	local major, minor
	if type(version) == 'string' then major, minor = version:match('^(%d+)%.(%d+)') end
	major, minor = tonumber(major), tonumber(minor)
	return major ~= nil and (major > 0 or minor >= 7)
end

-- Brings suji's title in line: our parts while suji counts and our title is
-- still the one on screen, otherwise none of ours (`set-title "" ""` takes
-- back one sent before). Sends nothing when nothing changes.
local function sync_suji()
	local parts = current and current.parts
	if parts and suji_titles() and mp.get_property('force-media-title', '') == current.title then
		local key = parts.series .. '\0' .. parts.episode .. '\0' .. (parts.name or '')
		if key == suji_sent then return end
		if parts.name then
			mp.commandv('script-message-to', 'suji', 'set-title', parts.series, parts.episode, parts.name)
		else
			mp.commandv('script-message-to', 'suji', 'set-title', parts.series, parts.episode)
		end
		suji_sent = key
	elseif suji_sent then
		mp.commandv('script-message-to', 'suji', 'set-title', '', '')
		suji_sent = nil
	end
end

local function playlist_entry_title()
	local pos = mp.get_property_number('playlist-playing-pos', -1)
	if not pos or pos < 0 then return '' end
	return mp.get_property('playlist/' .. pos .. '/title', '') or ''
end

local function on_start_file()
	current = nil
	-- suji cleared its title on end-file.
	suji_sent = nil
	local path = mp.get_property_native('path')
	publish_release(type(path) == 'string' and path or nil)
	if not opts.enabled then return end
	local title, source, parts = title_for(path)
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
	current = {title = title, fallback = source == 'fallback', parts = parts}
	sync_suji()
end

-- A container title beats our fallback. The file-local backup is already taken,
-- so mpv still restores the original value when the file ends.
local function on_file_loaded()
	if current and current.fallback then
		local tag = mp.get_property('metadata/by-key/title', '')
		if tag ~= nil and tag ~= '' and mp.get_property('force-media-title', '') == current.title then
			mp.set_property('file-local-options/force-media-title', '')
			current = nil
		end
	end
	-- A hook may have replaced our title, or suji may be ready only now.
	sync_suji()
end

-- Another language: the season and episode labels of the title on screen
-- change with it, as long as nothing else has replaced our title meanwhile.
local function on_language_change()
	if current and not current.fallback and mp.get_property('force-media-title', '') == current.title then
		local title, _, parts = title_for(mp.get_property('path'))
		if title and title ~= current.title then
			mp.set_property('file-local-options/force-media-title', title)
			current.title, current.parts = title, parts
		end
	end
	sync_suji()
end

mp.register_event('start-file', on_start_file)
mp.register_event('file-loaded', on_file_loaded)
mp.register_event('end-file', function()
	current = nil
	-- suji clears its own title on end-file: nothing to take back.
	suji_sent = nil
	publish_release(nil)
end)
i18n.on_change(on_language_change)
-- suji turned on, off or gone, or its version known only now; our title
-- replaced by someone else. Observers run after loading, never while it.
mp.observe_property(SUJI_ENABLED_PROP, 'native', sync_suji)
mp.observe_property(SUJI_VERSION_PROP, 'native', sync_suji)
mp.observe_property('force-media-title', 'string', sync_suji)
-- suji started (or started again): it holds no title of ours.
mp.register_script_message('suji-version', function(version)
	suji_announced = tostring(version)
	suji_sent = nil
	sync_suji()
end)

if HIKARI_TITLE_TEST then
	return {
		title_for = title_for, url_decode = url_decode, sanitize = sanitize,
		truncate = truncate, strip_extension = strip_extension, pretty_title = pretty_title,
		on_start_file = on_start_file, on_file_loaded = on_file_loaded, release_for = release_for,
		RELEASE_PROP = RELEASE_PROP,
		MAX_CHARS = MAX_CHARS, MAX_RAW = MAX_RAW, opts = opts, i18n = i18n,
	}
end
