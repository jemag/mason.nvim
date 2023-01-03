local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local util = require "mason-core.installer.registry.util"

local M = {}

---@param purl Purl
local function get_package_name(purl)
    if purl.subpath then
        return ("%s/%s/%s"):format(purl.namespace, purl.name, purl.subpath)
    else
        return ("%s/%s"):format(purl.namespace, purl.name)
    end
end

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class GolangSource : PackageSource
    local source = {
        package = get_package_name(purl),
        version = purl.version,
        extra_packages = spec.source.extra_packages,
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source GolangSource
function M.install(ctx, source)
    local golang = require "mason-core.managers.v2.golang"
    local providers = require "mason-core.providers"

    return Result.try(function(try)
        try(util.ensure_valid_version(function()
            return providers.golang.get_all_versions(source.package)
        end))

        try(golang.install(source.package, source.version, {
            extra_packages = source.extra_packages,
        }))
    end)
end

return M
