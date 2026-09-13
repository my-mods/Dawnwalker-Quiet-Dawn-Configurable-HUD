-- MIT. One converted snapshot per gameplay session; no file I/O on Apply.
local Model=require('SettingsModel')
local context=SaveLoadContext
local ok,values=pcall(function() return context and context.settings or Model.load() end)
if not ok then
    print('[Quiet Dawn - Configurable HUD] Settings rejected: '..tostring(values))
    return {enabled=false,panels={},debugLogging=false}
end
return Model.convert(values)
