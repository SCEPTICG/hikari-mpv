-- hikari-media-language: audio and subtitles in the language of hikari.
--
-- The language picked in hikari's language menu (Alt+l, or the system's when
-- none is picked) also decides which audio and subtitle tracks mpv selects on
-- its own, with this recipe for anime:
--   alang=<language>,ja                 the dub in your language, else Japanese
--   slang=<language>                    subtitles in your language...
--   subs-with-matching-audio=forced     ...except when the audio already is:
--                                       then only forced subtitles (signs
--                                       and songs), not the dialogue
-- <language> is a list of codes per entry of the language menu
-- (MEDIA_LANGUAGES in script-modules/hikari-i18n.lua, where the matching
-- rules of mpv are explained). Spanish and Portuguese have two entries, one
-- per regional variant: Spain or Latin America, Brazil or Portugal. Their
-- lists put the variant's own region first, and when several tracks share
-- the language, hikari picks the one of your variant by its tag and title;
-- a dub of the other variant alone does not count as a dub in your language
-- (see "Regional variants" below). There is no option to turn it on or off:
-- your own lines are.
--
-- The audio and subtitles picked by hand in an episode of a series are
-- remembered for that series (see "Per series" below).
--
-- mpv turns this file name into the script name `hikari_media_language`. It
-- has no key binding and no menu.
--
-- Decisions:
-- - Your settings win. `alang` is decided on its own: when you set it,
--   hikari leaves it alone and still sets the subtitles. The subtitles go
--   together, all or nothing: `subs-with-matching-audio` only makes sense
--   with hikari's `slang`, so when you set `slang` hikari leaves both alone
--   (even if you did not set `subs-with-matching-audio`), and when you set
--   only `subs-with-matching-audio`, hikari still sets `slang`. With an
--   alang/slang of yours, the choice between variants (below) only picks
--   among tracks your list cannot tell apart. An option counts as yours
--   when, at the moment this script starts:
--     1. mpv says it came from the command line
--        (option-info/<name>/set-from-commandline), or
--     2. its value is not mpv's default (option-info/<name>/default-value).
--        This catches mpv.conf, the files it includes, /etc/mpv/mpv.conf,
--        profiles applied at start (`profile=`), mpv.net's settings and any
--        script that ran earlier: whatever set it, it was not hikari. With
--        one exception, AnimeJaNai's own lines (below), or
--     3. ~~/mpv.conf (that file only, as expand-path gives it: never
--        /etc/mpv/mpv.conf) has a line for it outside the hikari block and
--        outside any [profile] section: `alang=...`,
--        `--slang = ... # comment`, `alang-append=...`,
--        `no-subs-with-matching-audio`... This is for
--        lines that write mpv's default value (`subs-with-matching-audio=yes`,
--        `slang=`), which 2 cannot tell apart from no line at all.
--   Why not option-info alone: mpv 0.40 and 0.41 only mark options from the
--   command line there (M_SETOPT_FROM_CMDLINE); mpv.conf sets another flag
--   that is not exposed, and set-locally only means "per file". The one case
--   left out is a line that writes the default value in a file other than
--   ~~/mpv.conf (an include, /etc/mpv/mpv.conf) or in a profile applied at
--   start: there hikari's value is used. Profiles that apply later (auto
--   profiles) set their values over hikari's while they are active, as they
--   would over any other value. To hand an option to hikari, delete its line.
-- - AnimeJaNai: its ~~/mpv-animejanai.conf (included by its configuration)
--   comes with `alang = 'jpn'` and `slang = 'eng'`. Those are AnimeJaNai's
--   defaults, not a choice of yours, so they do not count as yours by 2.
--   when all of this holds: the option holds exactly that value, and
--   ~~/mpv-animejanai.conf sets that option in one line only, and that line
--   is AnimeJaNai's (`alang` with the value `jpn`, quoted or not; `slang`
--   with `eng`). Older versions write those lines at the top level of the
--   file; newer ones inside its [animejanai] profile, which ~~/mpv.conf
--   applies with `profile = animejanai`. So the lines counted are those of
--   the top level and, when ~~/mpv.conf or ~~/mpv-animejanai.conf applies
--   that profile at the top level (a `profile=` line whose list names
--   `animejanai`), those of [animejanai]; a line in any other section
--   ([upscale-on], [subs-gpu], [extension.gif]...) never counts, and two
--   lines (one at the top, one in [animejanai]) are yours. The profiles that
--   [animejanai] applies in turn (`profile=high-quality`, mpv's own, and
--   `profile=upscale-on`) are not followed: in the known versions they set
--   neither option, and if one did, the value would no longer be
--   AnimeJaNai's (yours) or would still be `jpn`/`eng` (nothing of yours to
--   keep). The files are read as ~~/mpv.conf is (same size limit, comments,
--   profiles) and never written. Change the line to anything else
--   (`alang = 'jpn,eng'`), or set the option in ~~/mpv.conf or on the
--   command line, and it is yours again.
-- - When: once when the script starts, which mpv waits for before it opens
--   the first file (it waits until every script has finished loading), so the
--   first file already gets the recipe. The options are written to no file:
--   they only live while mpv runs (the one file this script writes is the
--   list of tracks per series, below). And again after every language
--   switch (Alt+l).
-- - Never over someone else's change: before setting an option again, hikari
--   checks that it still holds the value hikari set. If it does not (`set
--   alang ...` in the console, another script, an auto profile that is
--   active), that option is skipped this time.
-- - Switching language with a file open picks its tracks again with the new
--   languages, but only the ones mpv chose on its own: when you picked the
--   audio or subtitle track yourself (menu, keys, --aid/--sid, a resumed
--   position that saved them), mpv's `aid`/`sid` option holds that track
--   instead of `auto`, and hikari leaves it. Audio goes first, since the
--   choice of subtitles depends on it. mpv only picks again when `aid`/`sid`
--   changes, and setting `auto` over `auto` changes nothing, so hikari sets
--   the track already playing first (no switch at all, mpv returns at once
--   for the same track) and then `auto`. Skipped with `lavfi-complex`, where
--   tracks are wired into filters. The next files use the new languages in
--   any case.
-- - Regional variants: mpv only compares language tags, and releases often
--   tag both variants alike (Crunchyroll: "Spanish(Latin_America)" and
--   "Spanish", both `es`). So when a file is loaded, hikari looks at the
--   audio track mpv picked on its own (`aid` is `auto`), then the subtitle
--   track (`sid`): if it is in the language of hikari's menu entry and
--   another track of that language and of the same kind (forced or not,
--   external or not) ranks higher, hikari switches to it. Full subtitles
--   rank over a track whose title says it only has signs and songs ("Signs",
--   "Songs", "Carteles", "Forced"... without the forced mark: SIGNS; not
--   when it also says full ones: "Full + Songs", "Dialogue + Signs",
--   "non-forced"...: FULL), then a track of your variant over one that may be
--   either, over one of the other variant. A track's variant comes from the region of its tag (`es-ES`,
--   `es-419`, `es-MX`, `pt-BR`), else from words in its title ("Latin",
--   "Latino", "LATAM", "América", "419" / "España", "Spain", "Castilian",
--   "Castellano", "[ESP]", "European"; "Brazil", "Brasil", "BR" /
--   "Portugal", "European"), else a bare Spanish track counts as Spain's
--   (Crunchyroll only names the Latin American one); see REGIONAL in
--   hikari-i18n.lua.
--   Whose list picked the track matters:
--   - hikari's alang/slang (and still holding hikari's value): any track of
--     the language may be taken, since hikari's list only stands for the
--     menu entry (`es-MX` over `es` "Spanish" for Latin America, though the
--     list ranks `es` first).
--   - Your own alang/slang (or one changed since): only a track with the
--     same language tag as mpv's pick (`es` and `spa` are the same, `es` and
--     `es-419` are not): those are the tracks no list tells apart. A tag
--     your list names wins: with `slang=es-419,en`, an `es-419` track stays
--     even next to a `spa` "CR_Spanish".
--   The dub, with hikari's alang only: a dub of the other variant is not a
--   dub in your language. When mpv picked a dub whose tag or title says it
--   is of the other variant (a bare `spa` says nothing, so it is kept), and
--   every dub of the language in the file says so too, hikari plays the
--   Japanese audio instead (ORIGINAL_AUDIO; the best of mpv's rank, the
--   default mark, the file's order), when there is one, and has mpv pick the
--   subtitles again for it: with subs-with-matching-audio=forced mpv had
--   picked them for the dub (forced ones only, or none), now it picks full
--   ones, and then their variant is checked. With your own alang, the dub is
--   your list's choice and stays. Subtitles are different: with no
--   subtitles of your variant, the other variant's are used (another accent
--   rather than none).
--   Whether to show subtitles at all (only forced ones with a dub in your
--   language) stays mpv's decision with the options in effect. The switch
--   goes through file-local-options, so it lasts for that file only and the
--   next file starts from `auto` again. It never happens over a track you
--   picked or fixed (`--aid`, `--sid`, the menu, a resumed position), nor
--   with `lavfi-complex`. After a language switch the tracks are picked
--   again as above, and then the variant is checked again.
--   A script of your own that sets `aid`/`sid` (such as a sub-castellano.lua)
--   wins: once it has picked a track, `aid`/`sid` is no longer `auto`.
-- - Per series: the audio or subtitles you pick by hand in an episode of a
--   series are used for its next episodes, of any season.
--   - The series: the series name of the release name, as hikari-title reads
--     it (hikari-release's release_for: a local file name, or the `filename`
--     parameter of a stream such as Seanime's), normalised as hikari-resume
--     keys its series but without the season. Read here from mpv's `path`,
--     not from hikari-title's user-data/hikari_title/release, so it does not
--     depend on that script, its options or the order of the events. Not an
--     episode of a series (a film, an OVA, a range): nothing is remembered.
--   - What is saved: not the track number, which changes between releases,
--     but what finds the track again: its language (the first subtag, the
--     codes MEDIA_LANGUAGES and ORIGINAL_AUDIO list as their two-letter one:
--     `jpn` and `ja` are `ja`; any other as it comes), for Spanish and
--     Portuguese its variant (track_variant, as above), its tag as it comes
--     (only to choose between tracks alike) and, for subtitles, full ones or
--     signs and songs only (the forced mark or signs_only, as above), or no
--     subtitles at all. Audio and subtitles are saved apart: picking one
--     leaves what was saved of the other. Nothing else: never the path, the
--     URL or anything in it, only the normalised series name. A track
--     without a language cannot be found again: picking one forgets what was
--     saved for that kind; no audio is no choice to keep.
--   - When it is saved: a change of the track playing after file-loaded
--     whose option (`options/aid`, `options/sid`) now holds a track or `no`
--     that neither mpv nor hikari put there. mpv's own pick leaves the option
--     at `auto`. hikari's own switches (the variant, the series' track,
--     the language switch) go through set_track or reselect, which note what
--     they put there. Whatever the option held when file-loaded ended
--     (`--aid`/`--sid`, a resumed position, a script that ran before) is not
--     a change. The option is read when the observer runs, not taken from
--     it, so reselect's short step through the track already playing is
--     never seen. Picking the track already playing changes nothing, so it
--     is not saved. Not with `lavfi-complex`.
--   - When it is used: when a file of that series is loaded and mpv picked
--     the track on its own (`aid`/`sid` `auto`), before the variant check
--     and instead of it: picked by hand for this series is more precise than
--     hikari's recipe or your alang/slang. The track of the same language,
--     kind and variant (a track whose variant cannot be told is taken when no
--     track of the saved one is there, one of the other variant never), the
--     same tag first, mpv's pick of those that tie, else the first one. None
--     in this release: mpv's pick stays, with no message. Through
--     file-local-options like the variant switch, but it then counts as a
--     track you picked: a language switch leaves it. When the audio changed,
--     mpv picks the subtitles again for it, as for the original audio, unless
--     subtitles are saved too.
--   - Forgetting: picking another track replaces it. There is no menu or
--     key for it; deleting the list forgets every series.
--   - The list: ~~/hikari-tracks.json, {"version":1,"series":[{key, updated
--     (unix time), audio {lang, variant, tag}, subs {kind (full, signs or
--     none), lang, variant, tag}}]}, newest first, at most MAX_SERIES series
--     (the oldest go). Read with a size cap (MAX_SERIES_BYTES) and every
--     field checked: a part that does not check out is left out, an entry
--     with nothing left too. A broken, empty or newer file is an empty list
--     and one warning, written over by the next pick; one that cannot be read
--     at the moment is not written over. Read again before each write, and
--     only the series playing changes, so several mpv windows keep each
--     other's. Written through a temporary file of this mpv
--     (`<list>.<pid>-<n>.tmp`) renamed over it, as hikari-resume does. One
--     list per computer: nothing leaves it.

local msg = require('mp.msg')
local utils = require('mp.utils')

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

-- Texts and languages of hikari: ~~/script-modules/hikari-i18n.lua.
local i18n = load_module('hikari-i18n')
-- Release names (series, season, episode): ~~/script-modules/hikari-release.lua,
-- as hikari-title and hikari-resume read them. Without it, no series is known
-- and nothing is remembered per series; the rest works.
local release = load_module('hikari-release', true)

-- The options hikari may set, in the order it sets them.
local OPTIONS = {'alang', 'slang', 'subs-with-matching-audio'}
-- How mpv.conf may name each of them: the option itself, the actions of a
-- list option (`alang-append`...), and `no-` for the choice that has `no`.
local CONF_NAMES = {
	['subs-with-matching-audio'] = 'subs-with-matching-audio',
	['no-subs-with-matching-audio'] = 'subs-with-matching-audio',
}
for _, name in ipairs({'alang', 'slang'}) do
	CONF_NAMES[name] = name
	for _, action in ipairs({'set', 'add', 'append', 'pre', 'clr', 'del', 'remove', 'toggle'}) do
		CONF_NAMES[name .. '-' .. action] = name
	end
end
-- The hikari block of mpv.conf, as the installers write it.
local BLOCK_BEGIN = '# >>> hikari'
local BLOCK_END = '# <<< hikari'
-- Bound on what is read from mpv.conf (mpv itself reads up to 1 GB).
local MAX_CONF_BYTES = 1024 * 1024
-- AnimeJaNai's own options file and the values it comes with (see the header).
local ANIMEJANAI_CONF = '~~/mpv-animejanai.conf'
local ANIMEJANAI_DEFAULTS = {alang = 'jpn', slang = 'eng'}
-- The profile of that file that holds them in newer versions, and how a
-- line that applies a profile is named (see applies_profile).
local ANIMEJANAI_PROFILE = 'animejanai'
local PROFILE_NAMES = {profile = 'profile'}
-- The track properties hikari may switch, in order (audio first: mpv picks
-- the subtitles by the audio), and the type of their tracks in track-list.
local TRACKS = {'aid', 'sid'}
local TRACK_TYPES = {aid = 'audio', sid = 'sub'}
-- Bound on the title of a track that is looked at.
local MAX_TITLE = 256
-- The tracks picked by hand per series (see "Per series" in the header): the
-- list, its format, how many series it keeps, and bounds on what is read.
local SERIES_PATH = '~~/hikari-tracks.json'
local SERIES_VERSION = 1
local MAX_SERIES = 200
local MAX_SERIES_BYTES = 256 * 1024
local MAX_KEY = 200
local MAX_TAG = 32

-- The recipe for an entry of the language menu: option name -> value.
local function recipe(variant)
	local codes = i18n.MEDIA_LANGUAGES[variant] or i18n.MEDIA_LANGUAGES[i18n.DEFAULT]
	local alang = {}
	for _, code in ipairs(codes) do alang[#alang + 1] = code end
	for _, code in ipairs(i18n.ORIGINAL_AUDIO) do alang[#alang + 1] = code end
	local slang = {}
	for _, code in ipairs(codes) do slang[#slang + 1] = code end
	return {alang = alang, slang = slang, ['subs-with-matching-audio'] = 'forced'}
end

-- One form for any value of the three options, to compare them: a string
-- list as written in mpv.conf, and `subs-with-matching-audio`, which mpv
-- gives as a flag for yes/no but as a string for `forced`, as its name.
local function value_text(value)
	if type(value) == 'table' then return table.concat(value, ',') end
	if value == true then return 'yes' end
	if value == false then return 'no' end
	return tostring(value)
end

local function same_value(a, b)
	if type(a) == 'table' and type(b) == 'table' and #a ~= #b then return false end
	return value_text(a) == value_text(b)
end

-- mpv.conf -----------------------------------------------------------------

-- The value of a line after the option name, as mpv reads it: `= value`
-- up to a `#` comment and without the blanks around it, or `= "value"` /
-- `= 'value'` (and nothing but a comment after it). nil for a line without
-- `=`, false for one hikari does not read (`%5%value` quoting, a missing
-- quote, something after the quotes).
local function conf_value(rest)
	rest = rest:gsub('^%s+', '')
	if rest:sub(1, 1) ~= '=' then return nil end
	rest = rest:sub(2):gsub('^%s+', '')
	local quote = rest:sub(1, 1)
	if quote == '"' or quote == "'" then
		local value, after = rest:sub(2):match('^([^' .. quote .. ']*)' .. quote .. '(.*)$')
		if not value or not (after:match('^%s*$') or after:match('^%s*#')) then return false end
		return value
	end
	if quote == '%' then return false end
	-- Trailing blanks cut with one match: gsub('%s+$') retries at every blank.
	return rest:match('^([^#]*)'):match('^(.*%S)') or ''
end

-- The lines of `text` (an mpv.conf) for the options of OPTIONS outside the
-- hikari block and outside any [profile] section, in order, as
-- {option = 'alang', name = 'alang-append', value = 'ja'} (value as
-- conf_value gives it). The lines are read the way mpv reads them
-- (options/parse_configfile.c): blanks before the name, an optional `--`,
-- the name made of letters, digits, `_` and `-`, then `=`, a blank or the
-- end; `#` starts a comment; `[name]` starts a profile, and `[default]` goes
-- back to the top level.
-- `section`, when given, names one profile whose lines are read too, marked
-- with `section = <its name>`; `names`, when given, replaces CONF_NAMES (the
-- names looked for, each with its option).
local function conf_lines(text, section, names)
	local found = {}
	if type(text) ~= 'string' then return found end
	names = names or CONF_NAMES
	text = text:gsub('^\239\187\191', '')
	local current, in_block = nil, false
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', ''):gsub('^%s+', '')
		if line:sub(1, #BLOCK_BEGIN) == BLOCK_BEGIN then
			in_block = true
		elseif line:sub(1, #BLOCK_END) == BLOCK_END then
			in_block = false
		elseif line ~= '' and line:sub(1, 1) ~= '#' then
			local header = line:match('^%[([^%]]*)%]')
			if header then
				if header == 'default' then current = nil else current = header end
			elseif not in_block and (current == nil or current == section) then
				local name, rest = line:gsub('^%-%-', ''):match('^([%w_%-]+)(.*)$')
				local option = name and names[name]
				if option then
					found[#found + 1] = {option = option, name = name, value = conf_value(rest), section = current}
				end
			end
		end
	end
	return found
end

-- The options of OPTIONS that `text` (an mpv.conf) sets (see conf_lines), as a set.
local function conf_options(text)
	local found = {}
	for _, line in ipairs(conf_lines(text)) do found[line.option] = true end
	return found
end

-- The text of a file of mpv's config folder (`~~/...`), up to
-- MAX_CONF_BYTES; nil when there is no such file or it cannot be read.
local function read_config(name)
	local path = mp.command_native({'expand-path', name})
	if type(path) ~= 'string' or path == '' then return nil end
	local info = utils.file_info(path)
	if not info or not info.is_file then return nil end
	local file = io.open(path, 'rb')
	if not file then return nil end
	local text = file:read(MAX_CONF_BYTES)
	file:close()
	return text
end

-- The options ~~/mpv.conf sets (see conf_options); an empty set when there is
-- no such file or it cannot be read. Only that file: not /etc/mpv/mpv.conf,
-- which mp.find_config_file would fall back to (see the header).
local function user_conf_options()
	return conf_options(read_config('~~/mpv.conf'))
end

-- Whether `text` (an mpv.conf) applies the profile `profile` at the top
-- level: a `profile=` line outside the hikari block and outside any
-- [profile] section whose list names it as is (`profile = animejanai`,
-- `profile="a,animejanai"`). mpv does not trim the items of a list, so
-- `a, animejanai` does not name it.
local function applies_profile(text, profile)
	for _, line in ipairs(conf_lines(text, nil, PROFILE_NAMES)) do
		if type(line.value) == 'string' then
			for item in (line.value .. ','):gmatch('([^,]*),') do
				if item == profile then return true end
			end
		end
	end
	return false
end

-- The options of ANIMEJANAI_DEFAULTS that `text` (an mpv-animejanai.conf)
-- sets with AnimeJaNai's line and nothing else (see the header), as a set.
-- `applied`: whether the [animejanai] profile is applied at the top level;
-- only then do its lines count, together with those of the top level.
local function animejanai_defaults(text, applied)
	local lines = {}
	for _, line in ipairs(conf_lines(text, applied and ANIMEJANAI_PROFILE or nil)) do
		lines[line.option] = lines[line.option] or {}
		table.insert(lines[line.option], line)
	end
	local found = {}
	for option, value in pairs(ANIMEJANAI_DEFAULTS) do
		local list = lines[option]
		if list and #list == 1 and list[1].name == option and list[1].value == value then found[option] = true end
	end
	return found
end

-- The same for ~~/mpv-animejanai.conf, with its [animejanai] profile when
-- ~~/mpv.conf or that file applies it; an empty set without that file.
local function animejanai_conf_defaults()
	local text = read_config(ANIMEJANAI_CONF)
	if text == nil then return {} end
	local applied = applies_profile(read_config('~~/mpv.conf'), ANIMEJANAI_PROFILE)
		or applies_profile(text, ANIMEJANAI_PROFILE)
	return animejanai_defaults(text, applied)
end

-- Whether the user set `name` (see the header), and why, for the log.
-- `in_conf`: the options ~~/mpv.conf sets; `animejanai`: the options that
-- ~~/mpv-animejanai.conf sets as it comes. Unknown answers count as "yes":
-- better to leave an option alone than to overwrite a choice.
local function set_by_user(name, in_conf, animejanai)
	if mp.get_property_native('option-info/' .. name .. '/set-from-commandline') ~= false then
		return true, 'set on the command line, or unknown to this mpv'
	end
	local default = mp.get_property_native('option-info/' .. name .. '/default-value')
	local current = mp.get_property_native(name)
	if default == nil or current == nil then return true, 'its value cannot be read' end
	if not same_value(current, default) then
		if not ((animejanai or {})[name] and same_value(current, {ANIMEJANAI_DEFAULTS[name]})) then
			return true, 'already set (' .. (value_text(current):sub(1, 80):gsub('%c', '?')) .. ')'
		end
		msg.verbose(name .. ' holds what mpv-animejanai.conf comes with: taken as not yours')
	end
	if in_conf[name] then return true, 'set in mpv.conf' end
	return false
end

-- State ----------------------------------------------------------------------

-- name -> true for the options hikari takes care of (decided once, at start).
local managed = {}
-- name -> the value hikari last set (or found already right).
local applied = {}
-- A file is loaded and its tracks were selected.
local playing = false
-- property (aid, sid) -> the track hikari switched to in this file for the
-- regional variant (see the header).
local switched = {}
-- The series of the file playing (see series_key), when its track changes
-- are watched: set at the end of file-loaded, nil from start-file on.
local watched_series = nil
-- property (aid, sid) -> its option as last seen (`auto`, `no`, `3`), and the
-- value hikari itself put there in this file while it still holds it (see
-- "Per series" in the header).
local seen, ours = {}, {}

local function set_option(name, value)
	local ok, err
	if type(value) == 'table' then
		ok, err = mp.set_property_native(name, value)
	else
		ok, err = mp.set_property(name, value)
	end
	if not ok then msg.warn('Could not set ' .. name .. ': ' .. tostring(err)) end
	return ok
end

-- Switches the `property` track (aid, sid) to `value` (a track id or `no`)
-- for this file only, as hikari's own change (not one to remember).
local function set_track(property, value)
	ours[property] = tostring(value)
	return set_option('file-local-options/' .. property, tostring(value))
end

-- Sets the recipe for `lang` on the options hikari takes care of. Returns a
-- set of the options whose value changed.
local function apply(lang)
	local want = recipe(lang)
	local changed = {}
	for _, name in ipairs(OPTIONS) do
		if managed[name] then
			local current = mp.get_property_native(name)
			if applied[name] ~= nil and not same_value(current, applied[name]) then
				msg.verbose(name .. ' was changed by someone else: left as it is')
			elseif same_value(current, want[name]) then
				applied[name] = want[name]
			elseif set_option(name, want[name]) then
				applied[name] = want[name]
				changed[name] = true
			end
		end
	end
	return changed
end

-- Regional variants -------------------------------------------------------------

-- Lower case for titles: ASCII, and the capitals of Latin-1 (À to Þ, not ×)
-- in UTF-8, so that `ESPAÑA` and `AMÉRICA` read `españa` and `américa`.
local function fold(text)
	return (text:lower():gsub('\195([\128-\158])', function(c)
		if c == '\151' then return nil end
		return '\195' .. string.char(c:byte() + 32)
	end))
end

-- language of the texts -> set of the first subtags its tracks carry, from
-- the lists of its variants in MEDIA_LANGUAGES (`es`, `spa`).
local TRACK_CODES = {}
for language in pairs(i18n.REGIONAL) do
	local codes = {}
	for _, variant in ipairs(i18n.VARIANTS) do
		if variant.language == language then
			for _, code in ipairs(i18n.MEDIA_LANGUAGES[variant.code] or {}) do
				codes[code:lower():match('^(%a+)')] = true
			end
		end
	end
	TRACK_CODES[language] = codes
end

-- Whether a track (an entry of track-list) is in `language`, one of REGIONAL.
local function in_language(track, language)
	if type(track.lang) ~= 'string' then return false end
	local first = track.lang:sub(1, 64):lower():match('^%s*(%a+)')
	return first ~= nil and TRACK_CODES[language][first] == true
end

-- Whether a (folded) title has a word of a variant (REGIONAL).
local function title_says(title, variant)
	for _, word in ipairs(variant.words or {}) do
		if title:find(word, 1, true) then return true end
	end
	for _, token in ipairs(variant.tokens or {}) do
		if title:find('%f[%w]' .. token .. '%f[%W]') then return true end
	end
	return false
end

-- The regional variant of a track of `language` (an entry of VARIANTS), or
-- nil when it cannot tell: the region of its tag first, then the words of
-- its title (words of both variants tell nothing), then `untagged` (unless
-- `strict`: only what its tag or title says).
local function track_variant(track, language, strict)
	local region = i18n.region_of(track.lang)
	if region then return i18n.region_variant(language, region) end
	local regional = i18n.REGIONAL[language]
	local title = type(track.title) == 'string' and fold(track.title:sub(1, MAX_TITLE)) or ''
	local found = nil
	for code, variant in pairs(regional.variants) do
		if title_says(title, variant) then
			if found then return nil end
			found = code
		end
	end
	if found or strict then return found end
	return regional.untagged
end

-- Words in the title of a subtitle track that only translates signs and
-- songs, for the tracks that lack the forced mark (whole words, folded).
local SIGNS = {'signs?', 'songs?', 'carteles', 'cartel', 'letreros?', 'letreiros?', 'forced', 'forzad[oa]s?',
	'for\195\167ad[oa]s?'}

-- Words that say the subtitles are full ones, though the title also names
-- signs or songs ("Full + Songs", "Dialogue + Signs", "Spanish (non-forced)",
-- "Completos", "Não forçadas"): those are never taken for signs only
-- (whole words, folded; "non-forced" before "forced" in SIGNS).
local FULL = {'full', 'dialogs?', 'dialogues?', 'di\195\161logos?', 'dialogos?', 'complete',
	'complet[oa]s?', 'non[%- ]?forced', 'not forced', 'no forzad[oa]s?', 'n\195\163o for\195\167ad[oa]s?',
	'nao forcad[oa]s?'}

-- Whether a track is subtitles whose title says they only cover signs and songs.
local function signs_only(track)
	if track.type ~= 'sub' or type(track.title) ~= 'string' then return false end
	local title = fold(track.title:sub(1, MAX_TITLE))
	for _, word in ipairs(FULL) do
		if title:find('%f[%w]' .. word .. '%f[%W]') then return false end
	end
	for _, word in ipairs(SIGNS) do
		if title:find('%f[%w]' .. word .. '%f[%W]') then return true end
	end
	return false
end

-- mpv's language tags, as mpv 0.40 and 0.41 read them (misc/language.c):
-- subtags split at `-`, the first one through mpv's table of ISO 639 codes.
-- Of that table only the codes hikari compares are needed: tracks of a
-- language with variants and Japanese. same_tag and lang_rank use them.
-- lang_rank is mpv's rank of a track tag against a list of `alang`/`slang`
-- (mp_match_lang), used only to choose among the Japanese tracks of
-- ORIGINAL_AUDIO: an entry whose first subtag is the track's scores INT_MAX
-- minus its position, minus 1000 per later subtag of the track that differs
-- from the entry's or that the entry lacks; the best entry counts, 0 for none.
local INT_MAX = 2147483647
local SAME_CODE = {es = 'spa', pt = 'por', ja = 'jpn'}

local function subtags(text)
	local parts, rest = {}, text
	while rest ~= '' do
		local at = rest:find('-', 1, true)
		if at then
			parts[#parts + 1], rest = rest:sub(1, at - 1):lower(), rest:sub(at + 1)
		else
			parts[#parts + 1], rest = rest:lower(), ''
		end
	end
	return parts
end

-- Whether two language tags are the same for mpv: the same subtags, in any
-- case, with the first one through mpv's table (`es` and `spa` are the same,
-- `es` and `es-419` are not).
local function same_tag(a, b)
	if type(a) ~= 'string' or type(b) ~= 'string' or #a > 64 or #b > 64 then return false end
	local pa, pb = subtags(a), subtags(b)
	if #pa ~= #pb or #pa == 0 then return false end
	if (SAME_CODE[pa[1]] or pa[1]) ~= (SAME_CODE[pb[1]] or pb[1]) then return false end
	for i = 2, #pa do
		if pa[i] ~= pb[i] then return false end
	end
	return true
end

local function lang_rank(list, tag)
	if type(tag) ~= 'string' or #tag > 64 or type(list) ~= 'table' then return 0 end
	local parts = subtags(tag)
	if #parts == 0 then return 0 end
	local first = SAME_CODE[parts[1]] or parts[1]
	local best = 0
	for index, entry in ipairs(list) do
		local score, part = 0, 0
		if type(entry) == 'string' then
			for _, s in ipairs(subtags(entry)) do
				if part == 0 then
					if (SAME_CODE[s] or s) ~= first then break end
					score, part = INT_MAX - (index - 1), 1
				else
					if part >= #parts then break end
					if parts[part + 1] ~= s then score = score - 1000 end
					part = part + 1
				end
			end
		end
		score = score - (#parts - part) * 1000
		if score > best then best = score end
	end
	return best
end

-- The id of the track to use instead of the `current` one (an id) of
-- `track_type` for the entry `want` of VARIANTS, nil to keep it (see the
-- header): only when the current one is in that language and another track
-- of the same language and kind ranks higher. Full subtitles rank over a
-- track titled as signs and songs only; then a track of `want`'s variant over
-- one that may be either, over one of the other variant. The first such
-- track in the file's order. With `same_only` (the user's own `alang` or
-- `slang`), only tracks with the same language tag as the current one are
-- taken: those no list can tell apart, so whatever the user's list says
-- about tags (`es-419` before `spa`) stays.
local function preferred_track(tracks, track_type, current, want, same_only)
	local language = i18n.language_of(want)
	if not i18n.REGIONAL[language] then return nil end
	local picked = nil
	for _, track in ipairs(tracks) do
		if track.type == track_type and track.id == current then picked = track end
	end
	if not picked or not in_language(picked, language) then return nil end
	local function score(track)
		local variant = track_variant(track, language)
		local points = variant == want and 2 or (variant == nil and 1 or 0)
		if not signs_only(track) then points = points + 3 end
		return points
	end
	local best, best_score = picked, score(picked)
	for _, track in ipairs(tracks) do
		if track ~= picked and track.type == track_type and in_language(track, language)
			and (track.forced == true) == (picked.forced == true)
			and (track.external == true) == (picked.external == true)
			and not track.albumart and not track.image
			and (not same_only or same_tag(track.lang, picked.lang)) then
			local track_score = score(track)
			if track_score > best_score then best, best_score = track, track_score end
		end
	end
	if best == picked or type(best.id) ~= 'number' then return nil end
	return best.id
end

-- The id of the original audio (Japanese, ORIGINAL_AUDIO) to play instead of
-- the `current` audio track when that one is a dub of the other variant of
-- `want`'s language (by its tag or title, see track_variant) and so is every
-- other dub of that language in the file: a dub of the other variant is not
-- a dub in your language (see the header). nil to keep it, also when the
-- file has no Japanese track. Among Japanese tracks, mpv's rank with
-- ORIGINAL_AUDIO, then the default mark, then the file's order.
local function original_audio(tracks, current, want)
	local language = i18n.language_of(want)
	if not i18n.REGIONAL[language] then return nil end
	local picked, best, best_rank = nil, nil, 0
	for _, track in ipairs(tracks) do
		if track.type == 'audio' and not track.albumart and not track.image then
			if track.id == current then picked = track end
			if in_language(track, language) then
				local variant = track_variant(track, language, true)
				if variant == nil or variant == want then return nil end
			else
				local rank = lang_rank(i18n.ORIGINAL_AUDIO, track.lang)
				if rank > 0 and type(track.id) == 'number' and (rank > best_rank
					or (rank == best_rank and track.default == true and best.default ~= true)) then
					best, best_rank = track, rank
				end
			end
		end
	end
	if not picked or not in_language(picked, language) or not best then return nil end
	return best.id
end

local function complex_filters()
	local complex = mp.get_property_native('lavfi-complex')
	return type(complex) == 'string' and complex ~= ''
end

-- The option mpv picks each track property by.
local TRACK_OPTIONS = {aid = 'alang', sid = 'slang'}

-- Whether hikari takes care of `name` and it still holds hikari's value.
local function hikari_holds(name)
	return managed[name] == true and applied[name] ~= nil and same_value(mp.get_property_native(name), applied[name])
end

-- When mpv picked the `property` track (aid, sid) on its own, switches it to
-- the track of hikari's regional variant, for this file only (see the
-- header): any track of the language when hikari's alang/slang picked it,
-- only one with the same language tag when the option is yours. For the audio,
-- with hikari's alang, a dub of the other variant gives way to Japanese.
-- Returns true when it switched, 'original' when it switched to Japanese.
local function prefer_variant(property)
	if mp.get_property_native('options/' .. property) ~= 'auto' then return false end
	local current = mp.get_property_native(property)
	local tracks = mp.get_property_native('track-list')
	if type(current) ~= 'number' or type(tracks) ~= 'table' then return false end
	local want = i18n.variant()
	local option = TRACK_OPTIONS[property]
	local ours = hikari_holds(option)
	local result, why = true, 'for ' .. want
	local id = preferred_track(tracks, TRACK_TYPES[property], current, want, not ours)
	if not id and property == 'aid' and ours then
		id = original_audio(tracks, current, want)
		result, why = 'original', 'the original audio: no dub of ' .. want
	end
	if not id then return false end
	msg.verbose(property .. ': track ' .. id .. ' instead of ' .. current .. ', ' .. why)
	if not set_track(property, id) then return false end
	switched[property] = id
	return result
end

-- Per series ---------------------------------------------------------------------

-- Replaceable in tests.
local clock = {now = os.time}

local function finite(value)
	return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

-- 'windows' or not, from mpv when it says (as hikari-resume.lua).
local function is_windows()
	local p = mp.get_property_native('platform')
	if type(p) == 'string' and p ~= '' then return p == 'windows' end
	return package.config:sub(1, 1) == '\\'
end

-- First subtag -> the code a language is saved as: for the languages of
-- MEDIA_LANGUAGES and Japanese (ORIGINAL_AUDIO), the two-letter code of
-- their list (`eng`, `ger`, `deu`, `spa`, `jpn`: `en`, `de`, `de`, `es`,
-- `ja`). Any other language is saved as its tag gives it.
local SAVED_CODE = {}
do
	local lists = {i18n.ORIGINAL_AUDIO}
	for _, list in pairs(i18n.MEDIA_LANGUAGES) do lists[#lists + 1] = list end
	for _, list in ipairs(lists) do
		local firsts, two = {}, nil
		for _, code in ipairs(list) do
			local first = code:lower():match('^(%a+)')
			firsts[#firsts + 1] = first
			if #first == 2 then two = two or first end
		end
		for _, first in ipairs(firsts) do SAVED_CODE[first] = SAVED_CODE[first] or two end
	end
end
-- Tags that name no language.
local NO_LANGUAGE = {und = true, mul = true, mis = true, zxx = true}

-- The language of a track tag as it is saved: its first subtag (two or three
-- letters), lower case, through SAVED_CODE; nil when it names none.
local function saved_language(lang)
	if type(lang) ~= 'string' then return nil end
	local first = lang:sub(1, 64):lower():match('^%s*(%a+)')
	if not first or #first < 2 or #first > 3 or NO_LANGUAGE[first] then return nil end
	return SAVED_CODE[first] or first
end

-- What a subtitle track is: `signs` (the forced mark, or a title of signs and
-- songs only, see signs_only) or `full`.
local function sub_kind(track)
	if track.forced == true or signs_only(track) then return 'signs' end
	return 'full'
end

-- What is saved of a track (an entry of track-list) to find it again in
-- another release: {lang (see saved_language), variant (for Spanish and
-- Portuguese, see track_variant; nil when it cannot tell), tag (its tag as it
-- comes, lower case, to choose between tracks alike), kind (subtitles only,
-- see sub_kind)}. nil for a track without a language.
local function describe(track)
	local lang = saved_language(track.lang)
	if not lang then return nil end
	local choice = {lang = lang}
	if i18n.REGIONAL[lang] then choice.variant = track_variant(track, lang) end
	local tag = track.lang:sub(1, 64):lower():match('^%s*([%w%-]+)')
	if tag and #tag <= MAX_TAG then choice.tag = tag end
	if track.type == 'sub' then choice.kind = sub_kind(track) end
	return choice
end

-- The id of the track of `track_type` in `tracks` that `choice` (see
-- describe) stands for, nil when this file has none: the same language and,
-- for subtitles, the same kind; with a variant saved, a track of that variant
-- over one that may be either (never one of the other variant); then the
-- same tag. Of equal ones, mpv's pick (`current`), else the first in the
-- file's order.
local function remembered_track(tracks, track_type, choice, current)
	local best, best_score = nil, -1
	for _, track in ipairs(tracks) do
		if track.type == track_type and type(track.id) == 'number' and not track.albumart and not track.image
			and saved_language(track.lang) == choice.lang
			and (track_type ~= 'sub' or sub_kind(track) == choice.kind) then
			local score = 0
			if choice.variant then
				local variant = track_variant(track, choice.lang)
				score = variant == choice.variant and 2 or (variant == nil and 1 or nil)
			end
			if score then
				score = score * 2 + ((choice.tag and same_tag(track.lang, choice.tag)) and 1 or 0)
				if score > best_score or (score == best_score and track.id == current) then
					best, best_score = track, score
				end
			end
		end
	end
	return best and best.id or nil
end

-- The series of `path` (mpv's `path`), as the list keys it: the series name of
-- its release name (hikari-release: a local file, or a stream's `filename`
-- parameter, as hikari-title reads them), normalised and without the season,
-- so all seasons share it. nil when it is no episode of a series.
local function series_key(path)
	if not release or type(path) ~= 'string' then return nil end
	local info = release.release_for(path)
	if type(info) ~= 'table' or type(info.series) ~= 'string' then return nil end
	local key = release.normalize(info.series)
	-- Cut whole characters only: a broken one would not survive the JSON.
	if #key > MAX_KEY then key = key:sub(1, MAX_KEY):gsub('[\192-\255][\128-\191]*$', '') end
	if key == '' then return nil end
	return key
end

local SUB_KINDS = {full = true, signs = true}

-- A choice read from the list, checked (see describe), or nil. `sub`: one for
-- subtitles, which may also be {kind = 'none'} (no subtitles).
local function check_choice(raw, sub)
	if type(raw) ~= 'table' then return nil end
	if sub and raw.kind == 'none' then return {kind = 'none'} end
	if sub and not SUB_KINDS[raw.kind] then return nil end
	if type(raw.lang) ~= 'string' or not raw.lang:match('^%a%a%a?$') or saved_language(raw.lang) ~= raw.lang then
		return nil
	end
	local choice = {lang = raw.lang, kind = sub and raw.kind or nil}
	if raw.variant ~= nil then
		local regional = i18n.REGIONAL[raw.lang]
		if not regional or type(raw.variant) ~= 'string' or not regional.variants[raw.variant] then return nil end
		choice.variant = raw.variant
	end
	if raw.tag ~= nil then
		if type(raw.tag) ~= 'string' or #raw.tag > MAX_TAG or not raw.tag:match('^[%w%-]+$') then return nil end
		choice.tag = raw.tag:lower()
	end
	return choice
end

-- An entry read from the list, checked, or nil: {key, updated (unix time),
-- audio, subs}, a part that does not check out left out, and nil when none
-- is left.
local function check_entry(raw)
	if type(raw) ~= 'table' or type(raw.key) ~= 'string' or raw.key == '' or #raw.key > MAX_KEY
		or raw.key:find('%c') then
		return nil
	end
	if not finite(raw.updated) or raw.updated < 0 or raw.updated > 1e11 then return nil end
	local entry = {key = raw.key, updated = math.floor(raw.updated),
		audio = check_choice(raw.audio, false), subs = check_choice(raw.subs, true)}
	if not entry.audio and not entry.subs then return nil end
	return entry
end

local function series_path()
	local path = mp.command_native({'expand-path', SERIES_PATH})
	if type(path) ~= 'string' or path == '' or path == SERIES_PATH then return nil end
	return path
end

-- Warned once until the list can be read again, not on every file.
local warned_series = false

local function warn_series(why)
	if warned_series then return end
	warned_series = true
	msg.warn('Ignoring ' .. SERIES_PATH .. ' (' .. why .. '): no tracks remembered per series until it is written again')
end

-- The entries of the list, checked, newest first, one per series, at most
-- MAX_SERIES. Missing file: empty. Broken (too big, damaged, empty, of a newer
-- hikari): empty and a warning, and written over on the next save.
-- Unreadable (held by another program for a moment): empty, a warning, and
-- true, so it is not written over.
local function read_series()
	local path = series_path()
	if not path then return {} end
	local file = io.open(path, 'rb')
	if not file then
		if not utils.file_info(path) then return {} end
		warn_series('cannot be read')
		return {}, true
	end
	local content = file:read(MAX_SERIES_BYTES + 1)
	file:close()
	if type(content) ~= 'string' then
		warn_series('empty')
		return {}
	end
	if #content > MAX_SERIES_BYTES then
		warn_series('too big')
		return {}
	end
	local ok, value = pcall(utils.parse_json, content)
	if not ok or type(value) ~= 'table' or type(value.series) ~= 'table' or value.version ~= SERIES_VERSION then
		warn_series(ok and type(value) == 'table' and finite(value.version) and value.version > SERIES_VERSION
			and 'written by a newer hikari' or 'damaged')
		return {}
	end
	warned_series = false
	local checked = {}
	-- pairs, not ipairs: a null in the array leaves a hole.
	for _, raw in pairs(value.series) do checked[#checked + 1] = check_entry(raw) end
	-- Newest first; the same time, by key, so the order never depends on Lua.
	table.sort(checked, function(a, b)
		if a.updated ~= b.updated then return a.updated > b.updated end
		return a.key < b.key
	end)
	local entries, seen_keys = {}, {}
	for _, entry in ipairs(checked) do
		if #entries >= MAX_SERIES then break end
		if not seen_keys[entry.key] then
			seen_keys[entry.key] = true
			entries[#entries + 1] = entry
		end
	end
	return entries
end

-- A name for the temporary file of this mpv: two windows writing at once
-- must not share one. mpv's pid; a counter for writes within one mpv.
local tmp_count = 0
local function tmp_name(path)
	tmp_count = tmp_count + 1
	local pid = mp.get_property_number('pid')
	if not finite(pid) or pid < 1 or pid > 2 ^ 31 or pid % 1 ~= 0 then pid = math.random(1, 2 ^ 30) end
	return string.format('%s.%d-%d.tmp', path, pid, tmp_count)
end

-- Puts `tmp` in place of `path`, as hikari-resume.lua does: rename() replaces
-- a link at `path` itself, never what it points to. On Windows it does not
-- replace at all: the old file goes aside first, and back if the second
-- rename fails.
local function replace(tmp, path)
	local renamed, err = os.rename(tmp, path)
	if renamed or not is_windows() then return renamed, err end
	local old = tmp_name(path)
	if not os.rename(path, old) then return false, err end
	renamed, err = os.rename(tmp, path)
	if not renamed then
		os.rename(old, path)
		return false, err
	end
	os.remove(old)
	return true
end

local function write_series(entries)
	local path = series_path()
	if not path then return false end
	local json, err = utils.format_json({version = SERIES_VERSION, series = entries})
	local ok = false
	if json then
		local tmp = tmp_name(path)
		-- A leftover (or a link planted there) goes first, so io.open creates the file.
		os.remove(tmp)
		local file
		file, err = io.open(tmp, 'wb')
		if file then
			local written, write_err = file:write(json .. '\n')
			local closed, close_err = file:close()
			if written and closed then
				ok, err = replace(tmp, path)
			else
				err = write_err or close_err
			end
			if not ok then os.remove(tmp) end
		end
	end
	if not ok then msg.warn('Could not save ' .. SERIES_PATH .. ': ' .. tostring(err)) end
	return ok
end

-- The entry of the series `key` in the list, or nil.
local function remembered(key)
	if not key then return nil end
	for _, entry in ipairs(read_series()) do
		if entry.key == key then return entry end
	end
	return nil
end

-- Saves `choice` (see describe; nil forgets it) as the `part` (audio, subs)
-- of the series `key`. The list is read again first and only that series
-- changes, so two mpv windows keep each other's: it goes first, and the
-- oldest beyond MAX_SERIES go.
local function remember(key, part, choice)
	local entries, unreadable = read_series()
	if unreadable then return end
	local entry
	for i, e in ipairs(entries) do
		if e.key == key then
			entry = table.remove(entries, i)
			break
		end
	end
	if not entry and not choice then return end
	entry = entry or {key = key}
	entry[part] = choice
	entry.updated = math.floor(clock.now())
	if entry.audio or entry.subs then table.insert(entries, 1, entry) end
	for i = #entries, MAX_SERIES + 1, -1 do entries[i] = nil end
	if write_series(entries) then msg.verbose('Remembered the ' .. part .. ' picked for this series') end
end

-- The part of an entry for each track property.
local PARTS = {aid = 'audio', sid = 'subs'}

-- When mpv picked the `property` track (aid, sid) on its own, switches it to
-- the one remembered for the series (`entry`), for this file only. Returns
-- 'kept' when mpv's pick already is that one, 'switched', or nil when nothing
-- is remembered or this file has no such track (mpv's pick stays). Not with
-- track-auto-selection=no: then mpv picks nothing, as asked.
local function apply_remembered(property, entry)
	local choice = entry and entry[PARTS[property]]
	if not choice or mp.get_property_native('options/' .. property) ~= 'auto' then return nil end
	if mp.get_property_native('track-auto-selection') == false then return nil end
	local current = mp.get_property_native(property)
	local id = 'no'
	if choice.kind == 'none' then
		if type(current) ~= 'number' then return 'kept' end
	else
		local tracks = mp.get_property_native('track-list')
		if type(tracks) ~= 'table' then return nil end
		id = remembered_track(tracks, TRACK_TYPES[property], choice, current)
		if not id then return nil end
		if id == current then return 'kept' end
	end
	msg.verbose(property .. ': track ' .. id .. ' instead of ' .. tostring(current) .. ', as picked for this series')
	if not set_track(property, id) then return nil end
	return 'switched'
end

-- The `property` track (aid, sid) changed. While an episode of a known series
-- plays, an option that now holds a track (or `no` subtitles) that neither
-- mpv (`auto`) nor hikari (see set_track) put there is the user's choice, and
-- it is remembered for the series. A track without a language cannot be found
-- again: it forgets what was saved. No audio is no choice to keep.
local function on_track_change(property)
	if not watched_series then return end
	local value = mp.get_property('options/' .. property)
	if value == nil or value == seen[property] then return end
	seen[property] = value
	if value == 'auto' or value == ours[property] then return end
	ours[property] = nil
	local choice
	if value == 'no' then
		if property ~= 'sid' then return end
		choice = {kind = 'none'}
	else
		local id, track = tonumber(value), nil
		local tracks = mp.get_property_native('track-list')
		for _, t in ipairs(type(tracks) == 'table' and tracks or {}) do
			if type(t) == 'table' and t.type == TRACK_TYPES[property] and t.id == id then track = t end
		end
		if not track then return end
		choice = describe(track)
	end
	remember(watched_series, PARTS[property], choice)
end

local reselect

-- The audio first: the one remembered for the series, otherwise the variant
-- check, which may go from a dub to Japanese. When the audio changed, mpv
-- picks the subtitles again for it (it picked them for the other audio:
-- forced ones only for a dub in your language, with
-- subs-with-matching-audio=forced). Then the subtitles remembered for the
-- series, otherwise the subtitles' variant. Then the track changes of an
-- episode of a series are watched (see on_track_change).
local function on_file_loaded()
	playing = true
	switched, ours, watched_series = {}, {}, nil
	if complex_filters() then return end
	local key = series_key(mp.get_property_native('path'))
	local entry = remembered(key)
	local audio = apply_remembered('aid', entry)
	if not audio and prefer_variant('aid') == 'original' then audio = 'switched' end
	if not apply_remembered('sid', entry) then
		if audio == 'switched' then reselect('sid') end
		prefer_variant('sid')
	end
	for _, property in ipairs(TRACKS) do seen[property] = mp.get_property('options/' .. property) end
	watched_series = key
end

-- Lets mpv pick the `property` track (aid, sid) again, when mpv picked it on
-- its own (or hikari switched it for the variant). Returns true when it asked
-- mpv to.
function reselect(property)
	local option = mp.get_property_native('options/' .. property)
	if option ~= 'auto' and (switched[property] == nil or option ~= switched[property]) then return false end
	local current = mp.get_property(property)
	if not current or current == '' then return false end
	switched[property], ours[property] = nil, nil
	mp.set_property(property, current)
	mp.set_property(property, 'auto')
	return true
end

-- After a language switch: the tracks of the file playing, see the header.
-- A track is picked again when an option it depends on changed, when hikari
-- had switched it for a variant, or when the new entry has variants; then the
-- variant is checked again.
local function reselect_tracks(changed, variant)
	if not playing or complex_filters() then return end
	local regional = i18n.REGIONAL[i18n.language_of(variant)] ~= nil
	local original = false
	for _, property in ipairs(TRACKS) do
		local depends = property == 'aid' and changed.alang or (property == 'sid' and (next(changed) ~= nil or original))
		if depends or regional or switched[property] ~= nil then
			reselect(property)
			if prefer_variant(property) == 'original' then original = true end
		end
	end
end

local function on_language(_, variant)
	reselect_tracks(apply(variant), variant)
end

-- Start ------------------------------------------------------------------------

local in_conf = user_conf_options()
local animejanai = animejanai_conf_defaults()
for _, name in ipairs(OPTIONS) do
	local mine, why = set_by_user(name, in_conf, animejanai)
	-- All or nothing for the subtitles: see the header.
	if not mine and name == 'subs-with-matching-audio' and not managed.slang then
		mine, why = true, 'slang is yours, so the subtitles are'
	end
	managed[name] = not mine
	if mine then msg.verbose(name .. ' left to you: ' .. why) end
end
apply(i18n.variant())

local function on_file_gone()
	playing, switched, ours, watched_series = false, {}, {}, nil
end

mp.register_event('start-file', on_file_gone)
mp.register_event('file-loaded', on_file_loaded)
mp.register_event('end-file', on_file_gone)
i18n.on_change(on_language)
-- `aid`/`sid` change with the track playing: on_track_change reads the option.
for _, property in ipairs(TRACKS) do
	mp.observe_property(property, 'string', function() on_track_change(property) end)
end

if HIKARI_MEDIA_LANGUAGE_TEST then
	return {
		i18n = i18n, OPTIONS = OPTIONS, recipe = recipe, value_text = value_text, same_value = same_value,
		conf_value = conf_value, conf_lines = conf_lines, conf_options = conf_options,
		user_conf_options = user_conf_options, set_by_user = set_by_user,
		animejanai_defaults = animejanai_defaults, animejanai_conf_defaults = animejanai_conf_defaults,
		applies_profile = applies_profile,
		apply = apply, reselect = reselect, reselect_tracks = reselect_tracks,
		fold = fold, in_language = in_language, track_variant = track_variant,
		preferred_track = preferred_track, prefer_variant = prefer_variant, original_audio = original_audio,
		signs_only = signs_only, lang_rank = lang_rank, same_tag = same_tag,
		managed = managed, applied = applied,
		clock = clock, SERIES_PATH = SERIES_PATH, MAX_SERIES = MAX_SERIES, MAX_SERIES_BYTES = MAX_SERIES_BYTES,
		saved_language = saved_language, describe = describe, remembered_track = remembered_track,
		series_key = series_key, read_series = read_series, on_track_change = on_track_change,
		get_switched = function() return switched end,
		is_playing = function() return playing end,
	}
end
