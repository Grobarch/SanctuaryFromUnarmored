-- The settings page must be registered from a MENU script: the global Settings interface
-- only exposes registerGroup (vfs/scripts/omw/settings/global.lua).

local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

-- No `description`: the page should open straight into the options, not into a lecture.
I.Settings.registerPage({
    key = config.PAGE,
    l10n = config.L10N,
    name = 'pageName',
})
