-- Config stage: runs before roles are indexed.
SiteVeilTestConfigSawRoles = SiteVeil.Roles ~= nil and SiteVeil.Roles.byId ~= nil and next(SiteVeil.Roles.byId) ~= nil
SiteVeil.Config.TestAddonValue = 42
