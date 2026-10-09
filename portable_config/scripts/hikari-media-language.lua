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
--   ~~/mpv-animejanai.conf sets that option in one line only, outside any
--   [profile] section, and that line is AnimeJaNai's (`alang` with the value
--   `jpn`, quoted or not; `slang` with `eng`). The file is read as ~~/mpv.conf
--   is (same size limit, comments, profiles) and never written. Change the
--   line to anything else (`alang = 'jpn,eng'`), or set the option in
--   ~~/mpv.conf or on the command line, and it is yours again.
-- - When: once when the script starts, which mpv waits for before it opens
--   the first file (it waits until every script has finished loading), so the
--   first file already gets the recipe. Nothing is written to any file: the
--   options only live while mpv runs, and uninstalling hikari leaves nothing
--   behind. And again after every language switch (Alt+l).
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

local msg = require('mp.msg')
local utils = require('mp.utils')

-- Texts and languages of hikari: ~~/script-modules/hikari-i18n.lua. Single-file
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
-- The track properties hikari may switch, in order (audio first: mpv picks
-- the subtitles by the audio), and the type of their tracks in track-list.
local TRACKS = {'aid', 'sid'}
local TRACK_TYPES = {aid = 'audio', sid = 'sub'}
-- Bound on the title of a track that is looked at.
local MAX_TITLE = 256

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
local function conf_lines(text)
	local found = {}
	if type(text) ~= 'string' then return found end
	text = text:gsub('^\239\187\191', '')
	local top, in_block = true, false
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', ''):gsub('^%s+', '')
		if line:sub(1, #BLOCK_BEGIN) == BLOCK_BEGIN then
			in_block = true
		elseif line:sub(1, #BLOCK_END) == BLOCK_END then
			in_block = false
		elseif line ~= '' and line:sub(1, 1) ~= '#' then
			local section = line:match('^%[([^%]]*)%]')
			if section then
				top = section == 'default'
			elseif top and not in_block then
				local name, rest = line:gsub('^%-%-', ''):match('^([%w_%-]+)(.*)$')
				local option = name and CONF_NAMES[name]
				if option then found[#found + 1] = {option = option, name = name, value = conf_value(rest)} end
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

-- The options of ANIMEJANAI_DEFAULTS that `text` (an mpv-animejanai.conf)
-- sets with AnimeJaNai's line and nothing else (see the header), as a set.
local function animejanai_defaults(text)
	local lines = {}
	for _, line in ipairs(conf_lines(text)) do
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

-- The same for ~~/mpv-animejanai.conf; an empty set without that file.
local function animejanai_conf_defaults()
	return animejanai_defaults(read_config(ANIMEJANAI_CONF))
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
	if not set_option('file-local-options/' .. property, tostring(id)) then return false end
	switched[property] = id
	return result
end

local reselect

-- The audio first; when it went from a dub to Japanese, mpv picks the
-- subtitles again for it (it picked them for the dub: forced ones only, with
-- subs-with-matching-audio=forced), and then the subtitles' variant.
local function on_file_loaded()
	playing = true
	switched = {}
	if complex_filters() then return end
	if prefer_variant('aid') == 'original' then reselect('sid') end
	prefer_variant('sid')
end

-- Lets mpv pick the `property` track (aid, sid) again, when mpv picked it on
-- its own (or hikari switched it for the variant). Returns true when it asked
-- mpv to.
function reselect(property)
	local option = mp.get_property_native('options/' .. property)
	if option ~= 'auto' and (switched[property] == nil or option ~= switched[property]) then return false end
	local current = mp.get_property(property)
	if not current or current == '' then return false end
	switched[property] = nil
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

mp.register_event('start-file', function() playing, switched = false, {} end)
mp.register_event('file-loaded', on_file_loaded)
mp.register_event('end-file', function() playing, switched = false, {} end)
i18n.on_change(on_language)

if HIKARI_MEDIA_LANGUAGE_TEST then
	return {
		i18n = i18n, OPTIONS = OPTIONS, recipe = recipe, value_text = value_text, same_value = same_value,
		conf_value = conf_value, conf_lines = conf_lines, conf_options = conf_options,
		user_conf_options = user_conf_options, set_by_user = set_by_user,
		animejanai_defaults = animejanai_defaults, animejanai_conf_defaults = animejanai_conf_defaults,
		apply = apply, reselect = reselect, reselect_tracks = reselect_tracks,
		fold = fold, in_language = in_language, track_variant = track_variant,
		preferred_track = preferred_track, prefer_variant = prefer_variant, original_audio = original_audio,
		signs_only = signs_only, lang_rank = lang_rank, same_tag = same_tag,
		managed = managed, applied = applied,
		get_switched = function() return switched end,
		is_playing = function() return playing end,
	}
end
