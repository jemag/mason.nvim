local Result = require "mason-core.result"

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
function M.parse(spec, purl)
    ---@class OpamSource : PackageSource
    local source = {
        package = purl.name,
        version = purl.version,
    }

    return Result.success(source)
end

---@async
---@param ctx InstallContext
---@param source OpamSource
function M.install(ctx, source)
    local opam = require "mason-core.managers.v2.opam"
    return opam.install(source.package, source.version)
end

return M
