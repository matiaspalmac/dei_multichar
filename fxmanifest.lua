fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Dei'
description 'Selector de Personajes - Dei Ecosystem'
version '1.1'

provide 'esx_multicharacter'

dependencies { 'es_extended', 'esx_identity', 'esx_skin' }

shared_scripts {
    '@es_extended/imports.lua',
    '@es_extended/locale.lua',
    'locales/*.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/js/app.js',
    'html/assets/css/themes.css',
    'html/assets/css/styles.css',
    'html/assets/fonts/*.otf',
}
