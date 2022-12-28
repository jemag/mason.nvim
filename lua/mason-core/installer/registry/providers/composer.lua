local Result = require "mason-core.result"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class ComposerSource : PackageSource
    local source = {
        package = ("%s/%s"):format(purl.namespace, purl.name),
        version = purl.version,
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source ComposerSource
function M.install(ctx, source)
    local composer = require "mason-core.managers.v2.composer"
    return composer.install(source.package, source.version)
end

return M
