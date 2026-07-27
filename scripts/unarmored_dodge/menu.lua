-- Strona ustawien musi byc rejestrowana z kontekstu MENU - globalny interfejs Settings
-- wystawia wylacznie registerGroup (vfs/scripts/omw/settings/global.lua).

local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

-- Bez `description`: strona ma od razu pokazywac opcje, a nie wyklad o tym, co robi mod.
I.Settings.registerPage({
    key = config.PAGE,
    l10n = config.L10N,
    name = 'pageName',
})
