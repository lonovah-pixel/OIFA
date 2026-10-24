--[[---------------------------------------------------------------------------
Startup sequence, called once from init.lua / cl_init.lua after all modules
are loaded.

Server: run database migrations, fire "SiteVeil.DatabaseReady", verify that
the DarkRP integration is in the expected state and report loader errors.
---------------------------------------------------------------------------]]

local SV = SiteVeil

function SV.Startup()
    if SERVER then
        local ok, result = SV.DB.migrate()
        if ok then
            SV.Log.info("база данных готова (новых миграций: %d)", result)
            hook.Run("SiteVeil.DatabaseReady")
        else
            SV.Log.error("БАЗА ДАННЫХ НЕДОСТУПНА: %s. Создание и сохранение персонажей отключено.", tostring(result))
        end

        if SV.DarkRP.verify then SV.DarkRP.verify() end
    end

    for _, e in ipairs(SV.Loader.errors) do
        SV.Log.error("loader: %s", e)
    end
    SV.Log.info("SITE-VEIL %s загружен (%s)", SV.Version, SERVER and "сервер" or "клиент")
    hook.Run("SiteVeil.Started")
end
