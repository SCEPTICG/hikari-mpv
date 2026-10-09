-- hikari-i18n: every text hikari shows, in the 13 languages of uosc 5.13, and
-- the language in use. Shared by all hikari scripts; not a script itself.
--
-- Languages: English (the base) and de es fr it pl pt ro ru tr uk zh-HK zh-hans,
-- the same as uosc 5.13 (src/uosc/intl/), so hikari and uosc can always speak
-- the same one. Palette names are proper names and are not translated.
--
-- Usage (see the loader at the top of each hikari script):
--   i18n.t('skip_opening')                      -> 'Saltar opening ›'
--   i18n.t('update_notice', {version = '0.5.0'}) -> 'hikari 0.5.0 disponible · Alt+u'
--   i18n.on_change(function(lang) ... end)       -> after a language switch
--
-- Decisions:
-- - Why ~~/script-modules and a loader in each script: single-file mpv scripts
--   do not get any mpv folder in Lua's package.path (mpv 0.32+, checked with
--   mpv 0.40), so a plain require('hikari-i18n') would fail. Each script puts
--   the expanded `~~/script-modules` in front of package.path for this one
--   require and restores it right after. `~~` is mpv's config folder, also
--   for mpv.net and AnimeJaNai (portable_config). The folder is not scripts/:
--   mpv would load every .lua there as a script of its own.
-- - The language is the `hikari-language` script option (`script-opts`), set by
--   ~~/hikari-language.conf (included from mpv.conf; written by the installer
--   and by hikari-language.lua). Every script sees it from its very first line,
--   so nothing starts in the wrong language. A switch at run time changes the
--   option (`change-list script-opts append`), every script observes
--   `options/script-opts` and on_change callbacks run when the language they
--   resolve to changes.
-- - No option, or `auto`: the system language from LC_ALL, LC_MESSAGES or LANG
--   (the first one set, as the C library does). On Windows and for apps
--   started from the macOS Finder those are usually unset: English. The
--   installers write the real system language into hikari-language.conf, so
--   this only matters for copies made by hand.
-- - Fallbacks: a text missing in a language is the English one; an unknown
--   language is English; an unknown key is the key itself (and a warning).
-- - Placeholders are `{name}`, replaced from a table, never through
--   string.format: a translation can move them around, and a value with `%`
--   in it stays as it is.

local msg = require('mp.msg')

local M = {}

M.OPTION = 'hikari-language'
M.DEFAULT = 'en'

-- Menu order, with each name in its own language.
M.LANGUAGES = {
	{code = 'en', name = 'English'},
	{code = 'es', name = 'Español'},
	{code = 'de', name = 'Deutsch'},
	{code = 'fr', name = 'Français'},
	{code = 'it', name = 'Italiano'},
	{code = 'pl', name = 'Polski'},
	{code = 'pt', name = 'Português'},
	{code = 'ro', name = 'Română'},
	{code = 'ru', name = 'Русский'},
	{code = 'tr', name = 'Türkçe'},
	{code = 'uk', name = 'Українська'},
	{code = 'zh-HK', name = '中文（香港）'},
	{code = 'zh-hans', name = '简体中文'},
}
local BY_CODE = {}
for _, language in ipairs(M.LANGUAGES) do BY_CODE[language.code] = language end

-- key -> {language code -> text}. `en` must be there for every key (the tests
-- check it). Keep tooltip_* free of `,` and `?`: uosc's `controls` option uses
-- them as separators.
local STRINGS = {
	-- Shared ---------------------------------------------------------------
	active = {
		en = 'active', es = 'activa', de = 'aktiv', fr = 'active', it = 'attiva', pl = 'aktywna',
		pt = 'ativa', ro = 'activă', ru = 'активна', tr = 'etkin', uk = 'активна',
		['zh-HK'] = '使用中', ['zh-hans'] = '使用中',
	},
	current = {
		en = 'current', es = 'actual', de = 'aktuell', fr = 'actuelle', it = 'attuale', pl = 'bieżąca',
		pt = 'atual', ro = 'curentă', ru = 'текущая', tr = 'geçerli', uk = 'поточна',
		['zh-HK'] = '目前', ['zh-hans'] = '当前',
	},
	-- Decimal separator for numbers shown in menus (speeds).
	decimal_separator = {
		en = '.', es = ',', de = ',', fr = ',', it = ',', pl = ',', pt = ',', ro = ',', ru = ',',
		tr = ',', uk = ',', ['zh-HK'] = '.', ['zh-hans'] = '.',
	},

	-- Tooltips of hikari's buttons in uosc's controls bar (hikari-language.lua)
	tooltip_subs = {
		en = 'Subtitle style', es = 'Subtítulos', de = 'Untertitelstil', fr = 'Style des sous-titres',
		it = 'Stile sottotitoli', pl = 'Styl napisów', pt = 'Estilo das legendas', ro = 'Stil subtitrări',
		ru = 'Стиль субтитров', tr = 'Altyazı stili', uk = 'Стиль субтитрів',
		['zh-HK'] = '字幕樣式', ['zh-hans'] = '字幕样式',
	},
	tooltip_upscale = {
		en = 'Upscaling', es = 'Escalado', de = 'Hochskalierung', fr = 'Mise à l’échelle', it = 'Upscaling',
		pl = 'Skalowanie', pt = 'Ampliação', ro = 'Scalare', ru = 'Масштабирование', tr = 'Ölçekleme',
		uk = 'Масштабування', ['zh-HK'] = '畫質增強', ['zh-hans'] = '画质增强',
	},
	tooltip_speed = {
		en = 'Speed', es = 'Velocidad', de = 'Geschwindigkeit', fr = 'Vitesse', it = 'Velocità', pl = 'Prędkość',
		pt = 'Velocidade', ro = 'Viteză', ru = 'Скорость', tr = 'Hız', uk = 'Швидкість',
		['zh-HK'] = '播放速度', ['zh-hans'] = '播放速度',
	},
	tooltip_palettes = {
		en = 'Palettes', es = 'Paletas', de = 'Farbpaletten', fr = 'Palettes', it = 'Palette', pl = 'Palety',
		pt = 'Paletas', ro = 'Palete', ru = 'Палитры', tr = 'Paletler', uk = 'Палітри',
		['zh-HK'] = '配色方案', ['zh-hans'] = '配色方案',
	},
	tooltip_update = {
		en = 'Update hikari', es = 'Actualizar hikari', de = 'hikari aktualisieren', fr = 'Mettre à jour hikari',
		it = 'Aggiorna hikari', pl = 'Aktualizuj hikari', pt = 'Atualizar hikari', ro = 'Actualizează hikari',
		ru = 'Обновить hikari', tr = 'hikari’yi güncelle', uk = 'Оновити hikari',
		['zh-HK'] = '更新 hikari', ['zh-hans'] = '更新 hikari',
	},

	-- Language menu (hikari-language.lua) ------------------------------------
	language_title = {
		en = 'Language', es = 'Idioma', de = 'Sprache', fr = 'Langue', it = 'Lingua', pl = 'Język',
		pt = 'Idioma', ro = 'Limbă', ru = 'Язык', tr = 'Dil', uk = 'Мова',
		['zh-HK'] = '語言', ['zh-hans'] = '语言',
	},
	language_restart = {
		en = 'Restart mpv to translate the uosc menus too',
		es = 'Reinicia mpv para traducir también los menús de uosc',
		de = 'mpv neu starten, um auch die uosc-Menüs zu übersetzen',
		fr = 'Redémarrez mpv pour traduire aussi les menus d’uosc',
		it = 'Riavvia mpv per tradurre anche i menu di uosc',
		pl = 'Uruchom ponownie mpv, aby przetłumaczyć też menu uosc',
		pt = 'Reinicie o mpv para traduzir também os menus do uosc',
		ro = 'Repornește mpv pentru a traduce și meniurile uosc',
		ru = 'Перезапустите mpv, чтобы перевести и меню uosc',
		tr = 'uosc menülerini de çevirmek için mpv’yi yeniden başlatın',
		uk = 'Перезапустіть mpv, щоб перекласти й меню uosc',
		['zh-HK'] = '重新啟動 mpv 後，uosc 的選單也會切換語言',
		['zh-hans'] = '重启 mpv 后，uosc 的菜单也会切换语言',
	},
	language_save_failed = {
		en = 'hikari: could not save the language', es = 'hikari: no se pudo guardar el idioma',
		de = 'hikari: Sprache konnte nicht gespeichert werden', fr = 'hikari : impossible d’enregistrer la langue',
		it = 'hikari: impossibile salvare la lingua', pl = 'hikari: nie udało się zapisać języka',
		pt = 'hikari: não foi possível salvar o idioma', ro = 'hikari: limba nu a putut fi salvată',
		ru = 'hikari: не удалось сохранить язык', tr = 'hikari: dil kaydedilemedi',
		uk = 'hikari: не вдалося зберегти мову', ['zh-HK'] = 'hikari：無法儲存語言',
		['zh-hans'] = 'hikari：无法保存语言',
	},

	-- Palettes (hikari-palettes.lua) -----------------------------------------
	palettes_title = {
		en = 'Palettes', es = 'Paletas', de = 'Farbpaletten', fr = 'Palettes', it = 'Palette', pl = 'Palety',
		pt = 'Paletas', ro = 'Palete', ru = 'Палитры', tr = 'Paletler', uk = 'Палітри',
		['zh-HK'] = '配色方案', ['zh-hans'] = '配色方案',
	},
	palettes_group_dark = {
		en = 'Dark', es = 'Oscuras', de = 'Dunkel', fr = 'Sombres', it = 'Scure', pl = 'Ciemne', pt = 'Escuras',
		ro = 'Întunecate', ru = 'Тёмные', tr = 'Koyu', uk = 'Темні', ['zh-HK'] = '深色', ['zh-hans'] = '深色',
	},
	palettes_group_light = {
		en = 'Light', es = 'Claras', de = 'Hell', fr = 'Claires', it = 'Chiare', pl = 'Jasne', pt = 'Claras',
		ro = 'Luminoase', ru = 'Светлые', tr = 'Açık', uk = 'Світлі', ['zh-HK'] = '淺色', ['zh-hans'] = '浅色',
	},
	palettes_group_custom = {
		en = 'Custom', es = 'Propia', de = 'Eigene', fr = 'Personnelle', it = 'Personale', pl = 'Własna',
		pt = 'Própria', ro = 'Proprie', ru = 'Своя', tr = 'Kişisel', uk = 'Власна',
		['zh-HK'] = '自訂', ['zh-hans'] = '自定义',
	},
	-- The light variants of two palettes: the name stays, "light" is translated.
	palette_gruvbox_light = {
		en = 'Gruvbox Light', es = 'Gruvbox claro', de = 'Gruvbox hell', fr = 'Gruvbox clair', it = 'Gruvbox chiaro',
		pl = 'Gruvbox jasny', pt = 'Gruvbox claro', ro = 'Gruvbox luminos', ru = 'Gruvbox светлая',
		tr = 'Gruvbox açık', uk = 'Gruvbox світла', ['zh-HK'] = 'Gruvbox 淺色', ['zh-hans'] = 'Gruvbox 浅色',
	},
	palette_solarized_light = {
		en = 'Solarized Light', es = 'Solarized claro', de = 'Solarized hell', fr = 'Solarized clair',
		it = 'Solarized chiaro', pl = 'Solarized jasny', pt = 'Solarized claro', ro = 'Solarized luminos',
		ru = 'Solarized светлая', tr = 'Solarized açık', uk = 'Solarized світла',
		['zh-HK'] = 'Solarized 淺色', ['zh-hans'] = 'Solarized 浅色',
	},
	palettes_save_failed = {
		en = 'hikari: could not save the palette', es = 'hikari: no se pudo guardar la paleta',
		de = 'hikari: Palette konnte nicht gespeichert werden', fr = 'hikari : impossible d’enregistrer la palette',
		it = 'hikari: impossibile salvare la palette', pl = 'hikari: nie udało się zapisać palety',
		pt = 'hikari: não foi possível salvar a paleta', ro = 'hikari: paleta nu a putut fi salvată',
		ru = 'hikari: не удалось сохранить палитру', tr = 'hikari: palet kaydedilemedi',
		uk = 'hikari: не вдалося зберегти палітру', ['zh-HK'] = 'hikari：無法儲存配色方案',
		['zh-hans'] = 'hikari：无法保存配色方案',
	},

	-- Subtitles (hikari-subs.lua) --------------------------------------------
	subs_title = {
		en = 'Subtitle style', es = 'Subtítulos', de = 'Untertitelstil', fr = 'Style des sous-titres',
		it = 'Stile sottotitoli', pl = 'Styl napisów', pt = 'Estilo das legendas', ro = 'Stil subtitrări',
		ru = 'Стиль субтитров', tr = 'Altyazı stili', uk = 'Стиль субтитрів',
		['zh-HK'] = '字幕樣式', ['zh-hans'] = '字幕样式',
	},
	subs_group_style = {
		en = 'Style', es = 'Estilo', de = 'Stil', fr = 'Style', it = 'Stile', pl = 'Styl', pt = 'Estilo',
		ro = 'Stil', ru = 'Стиль', tr = 'Stil', uk = 'Стиль', ['zh-HK'] = '樣式', ['zh-hans'] = '样式',
	},
	subs_group_size = {
		en = 'Size', es = 'Tamaño', de = 'Größe', fr = 'Taille', it = 'Dimensione', pl = 'Rozmiar', pt = 'Tamanho',
		ro = 'Mărime', ru = 'Размер', tr = 'Boyut', uk = 'Розмір', ['zh-HK'] = '大小', ['zh-hans'] = '大小',
	},
	subs_group_height = {
		en = 'Height', es = 'Altura', de = 'Höhe', fr = 'Hauteur', it = 'Altezza', pl = 'Wysokość', pt = 'Altura',
		ro = 'Înălțime', ru = 'Высота', tr = 'Yükseklik', uk = 'Висота', ['zh-HK'] = '高度', ['zh-hans'] = '高度',
	},
	subs_style_original = {
		en = 'Original', es = 'Original', de = 'Original', fr = 'Original', it = 'Originale', pl = 'Oryginalny',
		pt = 'Original', ro = 'Original', ru = 'Оригинальный', tr = 'Orijinal', uk = 'Оригінальний',
		['zh-HK'] = '原始', ['zh-hans'] = '原始',
	},
	subs_style_dark_box = {
		en = 'Dark box', es = 'Caja oscura', de = 'Dunkle Box', fr = 'Boîte sombre', it = 'Riquadro scuro',
		pl = 'Ciemne tło', pt = 'Caixa escura', ro = 'Casetă întunecată', ru = 'Тёмная подложка',
		tr = 'Koyu kutu', uk = 'Темна підкладка', ['zh-HK'] = '深色底框', ['zh-hans'] = '深色底框',
	},
	subs_style_thick_outline = {
		en = 'Thick outline', es = 'Borde grueso', de = 'Dicker Rand', fr = 'Contour épais', it = 'Bordo spesso',
		pl = 'Gruby kontur', pt = 'Contorno grosso', ro = 'Contur gros', ru = 'Толстый контур',
		tr = 'Kalın kenar', uk = 'Товстий контур', ['zh-HK'] = '粗邊框', ['zh-hans'] = '粗描边',
	},
	subs_style_yellow = {
		en = 'Classic yellow', es = 'Amarillo clásico', de = 'Klassisches Gelb', fr = 'Jaune classique',
		it = 'Giallo classico', pl = 'Klasyczny żółty', pt = 'Amarelo clássico', ro = 'Galben clasic',
		ru = 'Классический жёлтый', tr = 'Klasik sarı', uk = 'Класичний жовтий',
		['zh-HK'] = '經典黃色', ['zh-hans'] = '经典黄色',
	},
	subs_size_small = {
		en = 'Small', es = 'Pequeño', de = 'Klein', fr = 'Petite', it = 'Piccola', pl = 'Mały', pt = 'Pequeno',
		ro = 'Mică', ru = 'Маленький', tr = 'Küçük', uk = 'Малий', ['zh-HK'] = '小', ['zh-hans'] = '小',
	},
	subs_size_normal = {
		en = 'Normal', es = 'Normal', de = 'Normal', fr = 'Normale', it = 'Normale', pl = 'Normalny',
		pt = 'Normal', ro = 'Normală', ru = 'Обычный', tr = 'Normal', uk = 'Звичайний',
		['zh-HK'] = '正常', ['zh-hans'] = '正常',
	},
	subs_size_large = {
		en = 'Large', es = 'Grande', de = 'Groß', fr = 'Grande', it = 'Grande', pl = 'Duży', pt = 'Grande',
		ro = 'Mare', ru = 'Большой', tr = 'Büyük', uk = 'Великий', ['zh-HK'] = '大', ['zh-hans'] = '大',
	},
	subs_size_xlarge = {
		en = 'Extra large', es = 'Muy grande', de = 'Sehr groß', fr = 'Très grande', it = 'Molto grande',
		pl = 'Bardzo duży', pt = 'Muito grande', ro = 'Foarte mare', ru = 'Очень большой', tr = 'Çok büyük',
		uk = 'Дуже великий', ['zh-HK'] = '特大', ['zh-hans'] = '特大',
	},
	subs_height_normal = {
		en = 'Normal', es = 'Normal', de = 'Normal', fr = 'Normale', it = 'Normale', pl = 'Normalna',
		pt = 'Normal', ro = 'Normală', ru = 'Обычная', tr = 'Normal', uk = 'Звичайна',
		['zh-HK'] = '正常', ['zh-hans'] = '正常',
	},
	subs_height_raised = {
		en = 'A little higher', es = 'Un poco más arriba', de = 'Etwas höher', fr = 'Un peu plus haut',
		it = 'Un po’ più in alto', pl = 'Trochę wyżej', pt = 'Um pouco mais acima', ro = 'Puțin mai sus',
		ru = 'Чуть выше', tr = 'Biraz daha yukarı', uk = 'Трохи вище',
		['zh-HK'] = '稍微靠上', ['zh-hans'] = '稍微靠上',
	},
	subs_height_high = {
		en = 'Higher', es = 'Más arriba', de = 'Höher', fr = 'Plus haut', it = 'Più in alto', pl = 'Wyżej',
		pt = 'Mais acima', ro = 'Mai sus', ru = 'Выше', tr = 'Daha yukarı', uk = 'Вище',
		['zh-HK'] = '更靠上', ['zh-hans'] = '更靠上',
	},
	subs_note = {
		en = 'Styles only change SRT; ASS keeps its own',
		es = 'Los estilos solo cambian SRT; los ASS conservan el suyo',
		de = 'Stile ändern nur SRT; ASS behält seinen eigenen',
		fr = 'Les styles ne changent que les SRT ; les ASS gardent le leur',
		it = 'Gli stili cambiano solo gli SRT; gli ASS mantengono il proprio',
		pl = 'Style zmieniają tylko SRT; ASS zachowują własny',
		pt = 'Os estilos só mudam SRT; ASS mantém o seu',
		ro = 'Stilurile schimbă doar SRT; ASS își păstrează stilul',
		ru = 'Стили меняют только SRT; ASS сохраняют свой',
		tr = 'Stiller yalnızca SRT’yi değiştirir; ASS kendi stilini korur',
		uk = 'Стилі змінюють лише SRT; ASS зберігають свій',
		['zh-HK'] = '樣式只會更改 SRT；ASS 保留自身樣式',
		['zh-hans'] = '样式仅更改 SRT；ASS 保留自身样式',
	},
	subs_save_failed = {
		en = 'hikari: could not save the subtitle style', es = 'hikari: no se pudo guardar el estilo de subtítulos',
		de = 'hikari: Untertitelstil konnte nicht gespeichert werden',
		fr = 'hikari : impossible d’enregistrer le style des sous-titres',
		it = 'hikari: impossibile salvare lo stile dei sottotitoli',
		pl = 'hikari: nie udało się zapisać stylu napisów',
		pt = 'hikari: não foi possível salvar o estilo das legendas',
		ro = 'hikari: stilul subtitrărilor nu a putut fi salvat',
		ru = 'hikari: не удалось сохранить стиль субтитров', tr = 'hikari: altyazı stili kaydedilemedi',
		uk = 'hikari: не вдалося зберегти стиль субтитрів', ['zh-HK'] = 'hikari：無法儲存字幕樣式',
		['zh-hans'] = 'hikari：无法保存字幕样式',
	},

	-- Speed (hikari-speed.lua) -----------------------------------------------
	speed_title = {
		en = 'Speed', es = 'Velocidad', de = 'Geschwindigkeit', fr = 'Vitesse', it = 'Velocità', pl = 'Prędkość',
		pt = 'Velocidade', ro = 'Viteză', ru = 'Скорость', tr = 'Hız', uk = 'Швидкість',
		['zh-HK'] = '播放速度', ['zh-hans'] = '播放速度',
	},
	speed_normal = {
		en = '{speed} (normal)', es = '{speed} (normal)', de = '{speed} (normal)', fr = '{speed} (normale)',
		it = '{speed} (normale)', pl = '{speed} (normalna)', pt = '{speed} (normal)', ro = '{speed} (normală)',
		ru = '{speed} (обычная)', tr = '{speed} (normal)', uk = '{speed} (звичайна)',
		['zh-HK'] = '{speed}（正常）', ['zh-hans'] = '{speed}（正常）',
	},

	-- Upscaling (hikari-upscale.lua) -----------------------------------------
	upscale_title = {
		en = 'Upscaling (Anime4K)', es = 'Escalado (Anime4K)', de = 'Hochskalierung (Anime4K)',
		fr = 'Mise à l’échelle (Anime4K)', it = 'Upscaling (Anime4K)', pl = 'Skalowanie (Anime4K)',
		pt = 'Ampliação (Anime4K)', ro = 'Scalare (Anime4K)', ru = 'Масштабирование (Anime4K)',
		tr = 'Ölçekleme (Anime4K)', uk = 'Масштабування (Anime4K)',
		['zh-HK'] = '畫質增強 (Anime4K)', ['zh-hans'] = '画质增强 (Anime4K)',
	},
	upscale_group_mode = {
		en = 'Mode', es = 'Modo', de = 'Modus', fr = 'Mode', it = 'Modalità', pl = 'Tryb', pt = 'Modo',
		ro = 'Mod', ru = 'Режим', tr = 'Mod', uk = 'Режим', ['zh-HK'] = '模式', ['zh-hans'] = '模式',
	},
	upscale_group_quality = {
		en = 'Quality', es = 'Calidad', de = 'Qualität', fr = 'Qualité', it = 'Qualità', pl = 'Jakość',
		pt = 'Qualidade', ro = 'Calitate', ru = 'Качество', tr = 'Kalite', uk = 'Якість',
		['zh-HK'] = '質素', ['zh-hans'] = '质量',
	},
	upscale_mode_off = {
		en = 'Off', es = 'Apagado', de = 'Aus', fr = 'Désactivé', it = 'Spento', pl = 'Wyłączone',
		pt = 'Desligado', ro = 'Oprit', ru = 'Выключено', tr = 'Kapalı', uk = 'Вимкнено',
		['zh-HK'] = '關閉', ['zh-hans'] = '关闭',
	},
	upscale_mode_auto = {
		en = 'Automatic', es = 'Automático', de = 'Automatisch', fr = 'Automatique', it = 'Automatico',
		pl = 'Automatyczny', pt = 'Automático', ro = 'Automat', ru = 'Автоматически', tr = 'Otomatik',
		uk = 'Автоматично', ['zh-HK'] = '自動', ['zh-hans'] = '自动',
	},
	-- {name}: A, B, C, A+A, B+B or C+A.
	upscale_mode_named = {
		en = 'Mode {name}', es = 'Modo {name}', de = 'Modus {name}', fr = 'Mode {name}', it = 'Modalità {name}',
		pl = 'Tryb {name}', pt = 'Modo {name}', ro = 'Mod {name}', ru = 'Режим {name}', tr = 'Mod {name}',
		uk = 'Режим {name}', ['zh-HK'] = '模式 {name}', ['zh-hans'] = '模式 {name}',
	},
	upscale_hint_off = {
		en = 'no Anime4K', es = 'sin Anime4K', de = 'ohne Anime4K', fr = 'sans Anime4K', it = 'senza Anime4K',
		pl = 'bez Anime4K', pt = 'sem Anime4K', ro = 'fără Anime4K', ru = 'без Anime4K', tr = 'Anime4K yok',
		uk = 'без Anime4K', ['zh-HK'] = '不使用 Anime4K', ['zh-hans'] = '不使用 Anime4K',
	},
	upscale_hint_auto = {
		en = 'C, B or A+A by resolution', es = 'C, B o A+A según la resolución',
		de = 'C, B oder A+A je nach Auflösung', fr = 'C, B ou A+A selon la résolution',
		it = 'C, B o A+A in base alla risoluzione', pl = 'C, B lub A+A zależnie od rozdzielczości',
		pt = 'C, B ou A+A conforme a resolução', ro = 'C, B sau A+A după rezoluție',
		ru = 'C, B или A+A по разрешению', tr = 'çözünürlüğe göre C, B veya A+A',
		uk = 'C, B або A+A залежно від роздільності', ['zh-HK'] = '按解像度選擇 C、B 或 A+A',
		['zh-hans'] = '根据分辨率选择 C、B 或 A+A',
	},
	upscale_hint_a = {
		en = '1080p blurry or compressed', es = '1080p borroso o comprimido', de = '1080p unscharf oder komprimiert',
		fr = '1080p flou ou compressé', it = '1080p sfocato o compresso', pl = '1080p rozmyte lub skompresowane',
		pt = '1080p desfocado ou comprimido', ro = '1080p neclar sau comprimat', ru = '1080p размытое или сжатое',
		tr = '1080p bulanık veya sıkıştırılmış', uk = '1080p розмите або стиснене',
		['zh-HK'] = '模糊或壓縮的 1080p', ['zh-hans'] = '模糊或压缩的 1080p',
	},
	upscale_hint_b = {
		en = '720p, jagged edges', es = '720p, bordes dentados', de = '720p, gezackte Kanten',
		fr = '720p, bords crénelés', it = '720p, bordi seghettati', pl = '720p, poszarpane krawędzie',
		pt = '720p, bordas serrilhadas', ro = '720p, margini zimțate', ru = '720p, зубчатые края',
		tr = '720p, tırtıklı kenarlar', uk = '720p, зубчасті краї',
		['zh-HK'] = '720p，邊緣鋸齒', ['zh-hans'] = '720p，边缘锯齿',
	},
	upscale_hint_c = {
		en = 'clean SD (480p), images', es = 'SD (480p) limpio, imágenes', de = 'sauberes SD (480p), Bilder',
		fr = 'SD (480p) propre, images', it = 'SD (480p) pulito, immagini', pl = 'czyste SD (480p), obrazy',
		pt = 'SD (480p) limpo, imagens', ro = 'SD (480p) curat, imagini', ru = 'чистое SD (480p), изображения',
		tr = 'temiz SD (480p), görseller', uk = 'чисте SD (480p), зображення',
		['zh-HK'] = '乾淨的 SD (480p)，圖片', ['zh-hans'] = '干净的 SD (480p)，图片',
	},
	-- {mode}: A, B or C.
	upscale_hint_double = {
		en = 'like {mode}, sharper, slower', es = 'como {mode}, más nítido, más lento',
		de = 'wie {mode}, schärfer, langsamer', fr = 'comme {mode}, plus net, plus lent',
		it = 'come {mode}, più nitido, più lento', pl = 'jak {mode}, ostrzej, wolniej',
		pt = 'como {mode}, mais nítido, mais lento', ro = 'ca {mode}, mai clar, mai lent',
		ru = 'как {mode}, чётче, медленнее', tr = '{mode} gibi, daha keskin, daha yavaş',
		uk = 'як {mode}, чіткіше, повільніше', ['zh-HK'] = '同 {mode}，更銳利，更慢',
		['zh-hans'] = '同 {mode}，更锐利，更慢',
	},
	upscale_quality_hq = {
		en = 'High', es = 'Alta', de = 'Hoch', fr = 'Haute', it = 'Alta', pl = 'Wysoka', pt = 'Alta',
		ro = 'Înaltă', ru = 'Высокое', tr = 'Yüksek', uk = 'Висока', ['zh-HK'] = '高', ['zh-hans'] = '高',
	},
	upscale_quality_hq_hint = {
		en = 'powerful graphics cards', es = 'gráficas potentes', de = 'starke Grafikkarten',
		fr = 'cartes graphiques puissantes', it = 'schede video potenti', pl = 'mocne karty graficzne',
		pt = 'placas de vídeo potentes', ro = 'plăci video puternice', ru = 'мощные видеокарты',
		tr = 'güçlü ekran kartları', uk = 'потужні відеокарти',
		['zh-HK'] = '效能強的顯示卡', ['zh-hans'] = '性能强的显卡',
	},
	upscale_quality_hq_osd = {
		en = 'High quality', es = 'Alta calidad', de = 'Hohe Qualität', fr = 'Haute qualité', it = 'Alta qualità',
		pl = 'Wysoka jakość', pt = 'Alta qualidade', ro = 'Calitate înaltă', ru = 'Высокое качество',
		tr = 'Yüksek kalite', uk = 'Висока якість', ['zh-HK'] = '高質素', ['zh-hans'] = '高质量',
	},
	upscale_quality_fast = {
		en = 'Fast', es = 'Rápida', de = 'Schnell', fr = 'Rapide', it = 'Veloce', pl = 'Szybka', pt = 'Rápida',
		ro = 'Rapidă', ru = 'Быстрое', tr = 'Hızlı', uk = 'Швидка', ['zh-HK'] = '快速', ['zh-hans'] = '快速',
	},
	upscale_quality_fast_hint = {
		en = 'modest graphics cards', es = 'gráficas modestas', de = 'einfache Grafikkarten',
		fr = 'cartes graphiques modestes', it = 'schede video modeste', pl = 'słabsze karty graficzne',
		pt = 'placas de vídeo modestas', ro = 'plăci video modeste', ru = 'слабые видеокарты',
		tr = 'mütevazı ekran kartları', uk = 'слабші відеокарти',
		['zh-HK'] = '效能一般的顯示卡', ['zh-hans'] = '性能一般的显卡',
	},
	upscale_quality_fast_osd = {
		en = 'Fast', es = 'Rápido', de = 'Schnell', fr = 'Rapide', it = 'Veloce', pl = 'Szybka', pt = 'Rápido',
		ro = 'Rapid', ru = 'Быстро', tr = 'Hızlı', uk = 'Швидко', ['zh-HK'] = '快速', ['zh-hans'] = '快速',
	},
	upscale_no_video = {
		en = 'no video', es = 'sin vídeo', de = 'kein Video', fr = 'pas de vidéo', it = 'nessun video',
		pl = 'brak wideo', pt = 'sem vídeo', ro = 'fără video', ru = 'нет видео', tr = 'video yok',
		uk = 'немає відео', ['zh-HK'] = '沒有影片', ['zh-hans'] = '无视频',
	},
	upscale_no_shaders = {
		en = 'no shaders', es = 'sin shaders', de = 'keine Shader', fr = 'pas de shaders', it = 'nessuno shader',
		pl = 'bez shaderów', pt = 'sem shaders', ro = 'fără shadere', ru = 'без шейдеров', tr = 'shader yok',
		uk = 'без шейдерів', ['zh-HK'] = '不使用著色器', ['zh-hans'] = '不使用着色器',
	},
	-- {detail}: what "Automatic" picked, e.g. "B, 720p".
	upscale_auto_now = {
		en = 'now: {detail}', es = 'ahora: {detail}', de = 'jetzt: {detail}', fr = 'maintenant : {detail}',
		it = 'ora: {detail}', pl = 'teraz: {detail}', pt = 'agora: {detail}', ro = 'acum: {detail}',
		ru = 'сейчас: {detail}', tr = 'şimdi: {detail}', uk = 'зараз: {detail}',
		['zh-HK'] = '目前：{detail}', ['zh-hans'] = '当前：{detail}',
	},
	upscale_osd_off = {
		en = 'Anime4K: off', es = 'Anime4K: apagado', de = 'Anime4K: aus', fr = 'Anime4K : désactivé',
		it = 'Anime4K: spento', pl = 'Anime4K: wyłączone', pt = 'Anime4K: desligado', ro = 'Anime4K: oprit',
		ru = 'Anime4K: выключено', tr = 'Anime4K: kapalı', uk = 'Anime4K: вимкнено',
		['zh-HK'] = 'Anime4K：已關閉', ['zh-hans'] = 'Anime4K：已关闭',
	},
	upscale_not_installed_menu = {
		en = 'Anime4K is not installed: run the installer',
		es = 'Anime4K no está instalado: ejecuta el instalador',
		de = 'Anime4K ist nicht installiert: Installer ausführen',
		fr = 'Anime4K n’est pas installé : lancez l’installateur',
		it = 'Anime4K non è installato: esegui il programma di installazione',
		pl = 'Anime4K nie jest zainstalowany: uruchom instalator',
		pt = 'Anime4K não está instalado: execute o instalador',
		ro = 'Anime4K nu este instalat: rulează programul de instalare',
		ru = 'Anime4K не установлен: запустите установщик',
		tr = 'Anime4K kurulu değil: yükleyiciyi çalıştırın',
		uk = 'Anime4K не встановлено: запустіть інсталятор',
		['zh-HK'] = '未安裝 Anime4K：請執行安裝程式',
		['zh-hans'] = '未安装 Anime4K：请运行安装程序',
	},
	upscale_not_installed_osd = {
		en = 'Anime4K is not installed: run the hikari installer',
		es = 'Anime4K no está instalado: ejecuta el instalador de hikari',
		de = 'Anime4K ist nicht installiert: hikari-Installer ausführen',
		fr = 'Anime4K n’est pas installé : lancez l’installateur de hikari',
		it = 'Anime4K non è installato: esegui il programma di installazione di hikari',
		pl = 'Anime4K nie jest zainstalowany: uruchom instalator hikari',
		pt = 'Anime4K não está instalado: execute o instalador do hikari',
		ro = 'Anime4K nu este instalat: rulează programul de instalare hikari',
		ru = 'Anime4K не установлен: запустите установщик hikari',
		tr = 'Anime4K kurulu değil: hikari yükleyicisini çalıştırın',
		uk = 'Anime4K не встановлено: запустіть інсталятор hikari',
		['zh-HK'] = '未安裝 Anime4K：請執行 hikari 安裝程式',
		['zh-hans'] = '未安装 Anime4K：请运行 hikari 安装程序',
	},
	upscale_save_failed = {
		en = 'hikari: could not save the upscaling', es = 'hikari: no se pudo guardar el escalado',
		de = 'hikari: Hochskalierung konnte nicht gespeichert werden',
		fr = 'hikari : impossible d’enregistrer la mise à l’échelle',
		it = 'hikari: impossibile salvare l’upscaling', pl = 'hikari: nie udało się zapisać skalowania',
		pt = 'hikari: não foi possível salvar a ampliação', ro = 'hikari: scalarea nu a putut fi salvată',
		ru = 'hikari: не удалось сохранить масштабирование', tr = 'hikari: ölçekleme kaydedilemedi',
		uk = 'hikari: не вдалося зберегти масштабування', ['zh-HK'] = 'hikari：無法儲存畫質增強設定',
		['zh-hans'] = 'hikari：无法保存画质增强设置',
	},

	-- Update check (hikari-update.lua) ---------------------------------------
	update_notice = {
		en = 'hikari {version} is out · Alt+u', es = 'hikari {version} disponible · Alt+u',
		de = 'hikari {version} verfügbar · Alt+u', fr = 'hikari {version} disponible · Alt+u',
		it = 'hikari {version} disponibile · Alt+u', pl = 'hikari {version} dostępne · Alt+u',
		pt = 'hikari {version} disponível · Alt+u', ro = 'hikari {version} disponibil · Alt+u',
		ru = 'Доступна hikari {version} · Alt+u', tr = 'hikari {version} çıktı · Alt+u',
		uk = 'Доступна hikari {version} · Alt+u', ['zh-HK'] = 'hikari {version} 已推出 · Alt+u',
		['zh-hans'] = 'hikari {version} 已发布 · Alt+u',
	},
	update_title = {
		en = 'hikari {version} is out', es = 'hikari {version} disponible', de = 'hikari {version} verfügbar',
		fr = 'hikari {version} disponible', it = 'hikari {version} disponibile', pl = 'hikari {version} dostępne',
		pt = 'hikari {version} disponível', ro = 'hikari {version} disponibil', ru = 'Доступна hikari {version}',
		tr = 'hikari {version} çıktı', uk = 'Доступна hikari {version}', ['zh-HK'] = 'hikari {version} 已推出',
		['zh-hans'] = 'hikari {version} 已发布',
	},
	update_notes = {
		en = 'What’s new in {version}', es = 'Ver novedades de la {version}', de = 'Neuerungen in {version} ansehen',
		fr = 'Voir les nouveautés de la {version}', it = 'Novità della {version}', pl = 'Co nowego w {version}',
		pt = 'Ver novidades da {version}', ro = 'Noutățile versiunii {version}', ru = 'Что нового в {version}',
		tr = '{version} yeniliklerine bak', uk = 'Що нового в {version}',
		['zh-HK'] = '查看 {version} 的更新內容', ['zh-hans'] = '查看 {version} 的更新内容',
	},
	update_notes_hint = {
		en = 'browser', es = 'navegador', de = 'Browser', fr = 'navigateur', it = 'browser', pl = 'przeglądarka',
		pt = 'navegador', ro = 'browser', ru = 'браузер', tr = 'tarayıcı', uk = 'браузер',
		['zh-HK'] = '瀏覽器', ['zh-hans'] = '浏览器',
	},
	update_copy = {
		en = 'Copy the update command', es = 'Copiar comando de actualización', de = 'Update-Befehl kopieren',
		fr = 'Copier la commande de mise à jour', it = 'Copia il comando di aggiornamento',
		pl = 'Kopiuj polecenie aktualizacji', pt = 'Copiar comando de atualização',
		ro = 'Copiază comanda de actualizare', ru = 'Скопировать команду обновления',
		tr = 'Güncelleme komutunu kopyala', uk = 'Скопіювати команду оновлення',
		['zh-HK'] = '複製更新指令', ['zh-hans'] = '复制更新命令',
	},
	update_copy_hint_terminal = {
		en = 'terminal', es = 'terminal', de = 'Terminal', fr = 'terminal', it = 'terminale', pl = 'terminal',
		pt = 'terminal', ro = 'terminal', ru = 'терминал', tr = 'terminal', uk = 'термінал',
		['zh-HK'] = '終端機', ['zh-hans'] = '终端',
	},
	update_dismiss = {
		en = 'Don’t remind me of this version', es = 'No avisar de esta versión',
		de = 'Für diese Version nicht mehr erinnern', fr = 'Ne plus signaler cette version',
		it = 'Non avvisare per questa versione', pl = 'Nie przypominaj o tej wersji',
		pt = 'Não avisar sobre esta versão', ro = 'Nu mai anunța această versiune',
		ru = 'Не напоминать об этой версии', tr = 'Bu sürüm için uyarma', uk = 'Не нагадувати про цю версію',
		['zh-HK'] = '不再提醒此版本', ['zh-hans'] = '不再提醒此版本',
	},
	update_dismissed_hint = {
		en = 'no more reminders', es = 'ya no se avisa', de = 'keine Erinnerung mehr', fr = 'n’est plus signalée',
		it = 'non più avvisato', pl = 'bez przypomnień', pt = 'não será avisado', ro = 'nu se mai anunță',
		ru = 'напоминания отключены', tr = 'artık uyarılmayacak', uk = 'нагадування вимкнено',
		['zh-HK'] = '已不再提醒', ['zh-hans'] = '已不再提醒',
	},
	update_disabled = {
		en = 'hikari: the new version notice is off', es = 'hikari: el aviso de versiones está desactivado',
		de = 'hikari: Versionshinweis ist ausgeschaltet', fr = 'hikari : l’avis de nouvelles versions est désactivé',
		it = 'hikari: l’avviso delle versioni è disattivato', pl = 'hikari: powiadomienia o wersjach są wyłączone',
		pt = 'hikari: o aviso de versões está desativado', ro = 'hikari: anunțul de versiuni este dezactivat',
		ru = 'hikari: проверка версий отключена', tr = 'hikari: sürüm uyarısı kapalı',
		uk = 'hikari: перевірку версій вимкнено', ['zh-HK'] = 'hikari：版本提醒已關閉',
		['zh-hans'] = 'hikari：版本提醒已关闭',
	},
	update_unknown = {
		en = 'hikari: installed version unknown, versions are not checked',
		es = 'hikari: versión instalada desconocida, no se comprueban versiones',
		de = 'hikari: installierte Version unbekannt, Versionen werden nicht geprüft',
		fr = 'hikari : version installée inconnue, les versions ne sont pas vérifiées',
		it = 'hikari: versione installata sconosciuta, le versioni non vengono controllate',
		pl = 'hikari: nieznana zainstalowana wersja, wersje nie są sprawdzane',
		pt = 'hikari: versão instalada desconhecida, as versões não são verificadas',
		ro = 'hikari: versiune instalată necunoscută, versiunile nu sunt verificate',
		ru = 'hikari: установленная версия неизвестна, версии не проверяются',
		tr = 'hikari: kurulu sürüm bilinmiyor, sürümler denetlenmiyor',
		uk = 'hikari: встановлена версія невідома, версії не перевіряються',
		['zh-HK'] = 'hikari：已安裝版本不明，不會檢查版本',
		['zh-hans'] = 'hikari：已安装版本未知，不检查版本',
	},
	update_none = {
		en = 'hikari {version}: there is no new version', es = 'hikari {version}: no hay ninguna versión nueva',
		de = 'hikari {version}: keine neue Version', fr = 'hikari {version} : aucune nouvelle version',
		it = 'hikari {version}: nessuna nuova versione', pl = 'hikari {version}: brak nowej wersji',
		pt = 'hikari {version}: não há nenhuma versão nova', ro = 'hikari {version}: nu există nicio versiune nouă',
		ru = 'hikari {version}: новых версий нет', tr = 'hikari {version}: yeni sürüm yok',
		uk = 'hikari {version}: нових версій немає', ['zh-HK'] = 'hikari {version}：沒有新版本',
		['zh-hans'] = 'hikari {version}：没有新版本',
	},
	update_browser_failed = {
		en = 'Could not open the browser. The release notes are at:\n{url}',
		es = 'No se pudo abrir el navegador. Las novedades están en:\n{url}',
		de = 'Browser konnte nicht geöffnet werden. Die Neuerungen stehen unter:\n{url}',
		fr = 'Impossible d’ouvrir le navigateur. Les nouveautés sont ici :\n{url}',
		it = 'Impossibile aprire il browser. Le novità sono qui:\n{url}',
		pl = 'Nie udało się otworzyć przeglądarki. Nowości są tutaj:\n{url}',
		pt = 'Não foi possível abrir o navegador. As novidades estão em:\n{url}',
		ro = 'Browserul nu a putut fi deschis. Noutățile sunt la:\n{url}',
		ru = 'Не удалось открыть браузер. Новинки здесь:\n{url}',
		tr = 'Tarayıcı açılamadı. Yenilikler burada:\n{url}',
		uk = 'Не вдалося відкрити браузер. Новинки тут:\n{url}',
		['zh-HK'] = '無法開啟瀏覽器。更新內容見：\n{url}',
		['zh-hans'] = '无法打开浏览器。更新内容见：\n{url}',
	},
	update_opening = {
		en = 'Opening the {version} release notes in the browser',
		es = 'Abriendo las novedades de la {version} en el navegador',
		de = 'Neuerungen von {version} werden im Browser geöffnet',
		fr = 'Ouverture des nouveautés de la {version} dans le navigateur',
		it = 'Apertura delle novità della {version} nel browser',
		pl = 'Otwieranie nowości {version} w przeglądarce',
		pt = 'Abrindo as novidades da {version} no navegador',
		ro = 'Se deschid noutățile versiunii {version} în browser',
		ru = 'Открываю новинки {version} в браузере',
		tr = '{version} yenilikleri tarayıcıda açılıyor',
		uk = 'Відкриваю новинки {version} у браузері',
		['zh-HK'] = '正在瀏覽器中開啟 {version} 的更新內容',
		['zh-hans'] = '正在浏览器中打开 {version} 的更新内容',
	},
	update_copied_powershell = {
		en = 'Command copied: paste it in PowerShell', es = 'Comando copiado: pégalo en PowerShell',
		de = 'Befehl kopiert: in PowerShell einfügen', fr = 'Commande copiée : collez-la dans PowerShell',
		it = 'Comando copiato: incollalo in PowerShell', pl = 'Polecenie skopiowane: wklej je w PowerShell',
		pt = 'Comando copiado: cole-o no PowerShell', ro = 'Comandă copiată: lipește-o în PowerShell',
		ru = 'Команда скопирована: вставьте её в PowerShell', tr = 'Komut kopyalandı: PowerShell’e yapıştırın',
		uk = 'Команду скопійовано: вставте її в PowerShell', ['zh-HK'] = '指令已複製：請貼上到 PowerShell',
		['zh-hans'] = '命令已复制：请粘贴到 PowerShell',
	},
	update_copied_terminal = {
		en = 'Command copied: paste it in a terminal', es = 'Comando copiado: pégalo en un terminal',
		de = 'Befehl kopiert: in einem Terminal einfügen', fr = 'Commande copiée : collez-la dans un terminal',
		it = 'Comando copiato: incollalo in un terminale', pl = 'Polecenie skopiowane: wklej je w terminalu',
		pt = 'Comando copiado: cole-o em um terminal', ro = 'Comandă copiată: lipește-o într-un terminal',
		ru = 'Команда скопирована: вставьте её в терминал', tr = 'Komut kopyalandı: bir terminale yapıştırın',
		uk = 'Команду скопійовано: вставте її в термінал', ['zh-HK'] = '指令已複製：請貼上到終端機',
		['zh-hans'] = '命令已复制：请粘贴到终端',
	},
	update_copy_failed_powershell = {
		en = 'Could not copy. Type in PowerShell:\n{command}', es = 'No se pudo copiar. Escribe en PowerShell:\n{command}',
		de = 'Kopieren fehlgeschlagen. In PowerShell eingeben:\n{command}',
		fr = 'Copie impossible. Tapez dans PowerShell :\n{command}',
		it = 'Impossibile copiare. Scrivi in PowerShell:\n{command}',
		pl = 'Nie udało się skopiować. Wpisz w PowerShell:\n{command}',
		pt = 'Não foi possível copiar. Digite no PowerShell:\n{command}',
		ro = 'Copierea a eșuat. Scrie în PowerShell:\n{command}',
		ru = 'Не удалось скопировать. Введите в PowerShell:\n{command}',
		tr = 'Kopyalanamadı. PowerShell’e yazın:\n{command}',
		uk = 'Не вдалося скопіювати. Введіть у PowerShell:\n{command}',
		['zh-HK'] = '無法複製。請在 PowerShell 中輸入：\n{command}',
		['zh-hans'] = '无法复制。请在 PowerShell 中输入：\n{command}',
	},
	update_copy_failed_terminal = {
		en = 'Could not copy. Type in a terminal:\n{command}', es = 'No se pudo copiar. Escribe en un terminal:\n{command}',
		de = 'Kopieren fehlgeschlagen. In einem Terminal eingeben:\n{command}',
		fr = 'Copie impossible. Tapez dans un terminal :\n{command}',
		it = 'Impossibile copiare. Scrivi in un terminale:\n{command}',
		pl = 'Nie udało się skopiować. Wpisz w terminalu:\n{command}',
		pt = 'Não foi possível copiar. Digite em um terminal:\n{command}',
		ro = 'Copierea a eșuat. Scrie într-un terminal:\n{command}',
		ru = 'Не удалось скопировать. Введите в терминале:\n{command}',
		tr = 'Kopyalanamadı. Bir terminale yazın:\n{command}',
		uk = 'Не вдалося скопіювати. Введіть у терміналі:\n{command}',
		['zh-HK'] = '無法複製。請在終端機中輸入：\n{command}',
		['zh-hans'] = '无法复制。请在终端中输入：\n{command}',
	},
	update_dismissed = {
		en = 'hikari {version}: no more reminders', es = 'hikari {version}: no se volverá a avisar',
		de = 'hikari {version}: keine Erinnerung mehr', fr = 'hikari {version} : cette version ne sera plus signalée',
		it = 'hikari {version}: non verrà più segnalata', pl = 'hikari {version}: bez dalszych przypomnień',
		pt = 'hikari {version}: não será mais avisado', ro = 'hikari {version}: nu se va mai anunța',
		ru = 'hikari {version}: напоминаний больше не будет', tr = 'hikari {version}: artık uyarılmayacak',
		uk = 'hikari {version}: нагадувань більше не буде', ['zh-HK'] = 'hikari {version}：不再提醒',
		['zh-hans'] = 'hikari {version}：不再提醒',
	},

	-- Skip button (hikari-skip.lua). "Opening" and "ending" are what anime fans
	-- call them in most of these languages; Portuguese and Chinese use their own words.
	skip_opening = {
		en = 'Skip opening ›', es = 'Saltar opening ›', de = 'Opening überspringen ›', fr = 'Passer l’opening ›',
		it = 'Salta opening ›', pl = 'Pomiń opening ›', pt = 'Pular abertura ›', ro = 'Sari peste opening ›',
		ru = 'Пропустить опенинг ›', tr = 'Opening’i atla ›', uk = 'Пропустити опенінг ›',
		['zh-HK'] = '跳過片頭 ›', ['zh-hans'] = '跳过片头 ›',
	},
	skip_intro = {
		en = 'Skip intro ›', es = 'Saltar intro ›', de = 'Intro überspringen ›', fr = 'Passer l’intro ›',
		it = 'Salta intro ›', pl = 'Pomiń intro ›', pt = 'Pular introdução ›', ro = 'Sari peste intro ›',
		ru = 'Пропустить интро ›', tr = 'İntro’yu atla ›', uk = 'Пропустити інтро ›',
		['zh-HK'] = '跳過序幕 ›', ['zh-hans'] = '跳过序幕 ›',
	},
	skip_ending = {
		en = 'Skip ending ›', es = 'Saltar ending ›', de = 'Ending überspringen ›', fr = 'Passer l’ending ›',
		it = 'Salta ending ›', pl = 'Pomiń ending ›', pt = 'Pular encerramento ›', ro = 'Sari peste ending ›',
		ru = 'Пропустить эндинг ›', tr = 'Ending’i atla ›', uk = 'Пропустити ендінг ›',
		['zh-HK'] = '跳過片尾 ›', ['zh-hans'] = '跳过片尾 ›',
	},
	skip_outro = {
		en = 'Skip preview ›', es = 'Saltar avance ›', de = 'Vorschau überspringen ›', fr = 'Passer l’aperçu ›',
		it = 'Salta anteprima ›', pl = 'Pomiń zapowiedź ›', pt = 'Pular prévia ›', ro = 'Sari peste previzualizare ›',
		ru = 'Пропустить превью ›', tr = 'Önizlemeyi atla ›', uk = 'Пропустити анонс ›',
		['zh-HK'] = '跳過預告 ›', ['zh-hans'] = '跳过预告 ›',
	},

	-- Titles (hikari-title.lua). `Show · S1 E05`: season and episode labels.
	-- Spanish and Portuguese say temporada, Turkish bölüm; Chinese wraps the number.
	title_season = {
		en = 'S{season}', es = 'T{season}', pt = 'T{season}', ['zh-HK'] = '第{season}季', ['zh-hans'] = '第{season}季',
	},
	title_episode = {
		en = 'E{episode}', tr = 'B{episode}', ['zh-HK'] = '第{episode}集', ['zh-hans'] = '第{episode}集',
	},
	title_episodes = {
		en = 'E{first}-E{last}', tr = 'B{first}-B{last}',
		['zh-HK'] = '第{first}-{last}集', ['zh-hans'] = '第{first}-{last}集',
	},
	-- Season 0 and SP01 / Special 01: `Show · Special E03`.
	title_special = {
		en = 'Special', es = 'Especial', de = 'Special', fr = 'Spécial', it = 'Speciale', pl = 'Specjalny',
		pt = 'Especial', ro = 'Special', ru = 'Спецвыпуск', tr = 'Özel', uk = 'Спецвипуск',
		['zh-HK'] = '特別篇', ['zh-hans'] = '特别篇',
	},
}
M.STRINGS = STRINGS

-- Track languages: what hikari-media-language.lua puts in mpv's `alang` and
-- `slang` for each language of hikari, in order of preference, and the
-- original audio of anime (Japanese) that follows in `alang`.
--
-- How mpv compares them with the language of a track (misc/language.c,
-- mp_match_lang, mpv 0.40 and 0.41):
-- - The first subtag goes through a table of ISO 639 codes first, so `es`
--   already matches tracks tagged `es` and `spa`, `de` matches `ger` and
--   `deu`, `zh` matches `chi` and `zho`. The 3-letter codes are still listed
--   for mpv 0.35 and older (Debian 12, Ubuntu 22.04), which only compare the
--   strings as they are; they cost nothing in newer versions.
-- - A track whose subtags differ from an entry (or that has more subtags than
--   it) loses 1000 points per subtag, while each later entry only loses 1. So
--   with `alang=es,ja` a dub tagged `es-419` (as Crunchyroll releases tag
--   them) loses to a `jpn` track. The regional tags that real releases use
--   are therefore listed before Japanese. A region that is not listed (say
--   `es-AR`) still beats `ja-JP`, but not a bare `ja`/`jpn`.
-- - Extra subtags in an entry are ignored when the track has none: `zh-Hant`
--   matches a plain `zh`/`chi` track as well as `zh` itself would.
-- Chinese: hikari's zh-HK is Traditional (Hong Kong, Taiwan), zh-hans
-- Simplified. Each one lists its own script and regions first, then plain
-- Chinese, then the other script last: a Chinese dub tagged with any code of
-- the list (or a shorter tag, such as `zh`) beats Japanese whatever its
-- script, and subtitles in the other script beat none. A longer tag loses to
-- `ja`/`jpn` like an unlisted region: `zh-Hans-CN` or `zh-Hant-TW` has a
-- subtag that no entry has, in both lists.
M.MEDIA_LANGUAGES = {
	en = {'en', 'eng', 'en-US', 'en-GB'},
	es = {'es', 'spa', 'es-ES', 'es-419'},
	de = {'de', 'ger', 'deu', 'de-DE'},
	fr = {'fr', 'fre', 'fra', 'fr-FR', 'fr-CA'},
	it = {'it', 'ita', 'it-IT'},
	pl = {'pl', 'pol', 'pl-PL'},
	pt = {'pt', 'por', 'pt-BR', 'pt-PT'},
	ro = {'ro', 'rum', 'ron', 'ro-RO'},
	ru = {'ru', 'rus', 'ru-RU'},
	tr = {'tr', 'tur', 'tr-TR'},
	uk = {'uk', 'ukr', 'uk-UA'},
	['zh-HK'] = {'zh-Hant', 'zh-HK', 'zh-TW', 'zh', 'chi', 'zho', 'zh-Hans', 'zh-CN'},
	['zh-hans'] = {'zh-Hans', 'zh-CN', 'zh', 'chi', 'zho', 'zh-Hant', 'zh-TW'},
}
M.ORIGINAL_AUDIO = {'ja', 'jpn'}

-- The code of one of LANGUAGES for a language tag or locale name, nil when it
-- is none of them. Takes `es`, `es_ES.UTF-8`, `pt-BR`, `zh_CN`, `zh-Hant-TW`,
-- `de_DE@euro`... (case-insensitive, `_` or `-`). Chinese: Traditional (Hant,
-- Taiwan, Hong Kong, Macau) is zh-HK, anything else Simplified (zh-hans).
-- `C` and `POSIX` are no language.
function M.normalize(text)
	if type(text) ~= 'string' or #text > 64 then return nil end
	local tag = text:lower():gsub('_', '-'):match('^%s*([%w%-]*)')
	if not tag or tag == '' or tag == 'c' or tag == 'posix' then return nil end
	local lang = tag:match('^(%a+)')
	if lang == 'zh' then
		local subtags = '-' .. tag .. '-'
		if subtags:find('-hans-', 1, true) then return 'zh-hans' end
		if subtags:find('-hant-', 1, true) or subtags:find('-tw-', 1, true) or subtags:find('-hk-', 1, true)
			or subtags:find('-mo-', 1, true) then
			return 'zh-HK'
		end
		return 'zh-hans'
	end
	if lang and BY_CODE[lang] then return lang end
	return nil
end

-- Replaceable in tests.
M.getenv = os.getenv

-- The system language: LC_ALL, LC_MESSAGES or LANG, the first one set (as the
-- C library picks them); English when that one is none of LANGUAGES.
function M.detect()
	for _, name in ipairs({'LC_ALL', 'LC_MESSAGES', 'LANG'}) do
		local value = M.getenv(name)
		if type(value) == 'string' and value ~= '' then return M.normalize(value) or M.DEFAULT end
	end
	return M.DEFAULT
end

-- The language for a value of the `hikari-language` option: `auto` (or
-- nothing) is the system's, a known tag is itself, anything else English.
local warned_value = nil
function M.resolve(value)
	if value == nil or value == '' or value == 'auto' then return M.detect() end
	local code = M.normalize(value)
	if not code then
		-- Once per value: this runs again on every change of any script option.
		if value ~= warned_value then
			warned_value = value
			msg.warn('Unknown hikari-language "' .. tostring(value):sub(1, 64) .. '", using ' .. M.DEFAULT)
		end
		return M.DEFAULT
	end
	return code
end

local function option_value(script_opts)
	if type(script_opts) ~= 'table' then return nil end
	return script_opts[M.OPTION]
end

local current = nil
local callbacks = {}
local observing = false

-- The language in use: one of the codes of LANGUAGES.
function M.language()
	if not current then current = M.resolve(option_value(mp.get_property_native('options/script-opts'))) end
	return current
end

local warned = {}

-- The text for `key` in the current language (or `lang`), with `{name}`
-- replaced from `vars`. Placeholders without a value stay as they are.
function M.t(key, vars, lang)
	local entry = STRINGS[key]
	if not entry then
		if not warned[key] then
			warned[key] = true
			msg.warn('Missing hikari text: ' .. tostring(key))
		end
		return tostring(key)
	end
	local text = entry[lang or M.language()] or entry[M.DEFAULT] or tostring(key)
	if vars then
		text = text:gsub('{(%w+)}', function(name)
			local value = vars[name]
			if value == nil then return nil end
			return tostring(value)
		end)
	end
	return text
end

-- A number written with a dot (`0.75`, how menus and commands carry it) with
-- the decimal separator of the current language.
function M.decimal(text)
	local separator = M.t('decimal_separator')
	if separator == '.' then return text end
	return (text:gsub('%.', separator, 1))
end

-- Calls fn(lang) after every switch to another language.
function M.on_change(fn)
	callbacks[#callbacks + 1] = fn
	if observing then return end
	observing = true
	M.language()
	mp.observe_property('options/script-opts', 'native', function(_, script_opts)
		local lang = M.resolve(option_value(script_opts))
		if lang == current then return end
		current = lang
		for _, callback in ipairs(callbacks) do callback(lang) end
	end)
end

-- Native name of a language code, nil when unknown.
function M.name(code)
	local language = BY_CODE[code]
	return language and language.name or nil
end

function M.is_language(code) return BY_CODE[code] ~= nil end

return M
