local Result = require "mason-core.result"
local _ = require "mason-core.functional"

local M = {}

---@param purl Purl
local function parse_package_name(purl)
    if purl.namespace then
        return ("%s/%s"):format(purl.namespace, purl.name)
    else
        return purl.name
    end
end

local parse_server = _.path { "qualifiers", "repository_url" }
local parse_dev = _.compose(_.equals "true", _.path { "qualifiers", "dev" })

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class LuaRocksSource : PackageSource
    local source = {
        package = parse_package_name(purl),
        version = purl.version,
        server = parse_server(purl),
        dev = parse_dev(purl),
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source LuaRocksSource
function M.install(ctx, source)
    local luarocks = require "mason-core.managers.v2.luarocks"
    return luarocks.install(source.package, source.version, {
        server = source.server,
        dev = source.dev,
    })
end

return M
