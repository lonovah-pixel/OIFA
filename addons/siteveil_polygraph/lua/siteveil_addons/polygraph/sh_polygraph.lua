local Net = SiteVeil.Net
SiteVeil.Polygraph = SiteVeil.Polygraph or {}
Net.define("poly.start", {args = {"ent", "str:120"}, alive = true, rate = {burst = 2, refill = 0.1}})
Net.define("poly.consent", {args = {"bool"}, alive = true, rate = {burst = 3, refill = 0.5}})
