local a = require "mason-core.async"
local async_uv = require "mason-core.async.uv"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local platform = require "mason-core.platform"
local settings = require "mason.settings"
local expr = require "mason-core.installer.registry.expr"
local util = require "mason-core.installer.registry.util"
local path = require "mason-core.path"

local build = {
    ---@param spec RegistryPackageSpec
    ---@param purl Purl
    ---@param opts PackageInstallOpts
    parse = function(spec, purl, opts)
        return Result.try(function(try)
            ---@type { run: string }
            local build_instruction = try(util.coalesce_by_target(spec.source.build, opts):ok_or "PLATFORM_UNSUPPORTED")

            ---@class GitHubBuildSource : PackageSource
            local source = {
                build = build_instruction,
                repo = ("https://github.com/%s/%s.git"):format(purl.namespace, purl.name),
                rev = purl.version,
            }
            return source
        end)
    end,

    ---@async
    ---@param ctx InstallContext
    ---@param source GitHubBuildSource
    install = function(ctx, source)
        local std = require "mason-core.managers.v2.std"
        return Result.try(function(try)
            try(std.clone(source.repo, { rev = source.rev }))
            try(platform.when {
                unix = function()
                    return ctx.spawn.bash {
                        on_spawn = a.scope(function(_, stdio)
                            local stdin = stdio[1]
                            async_uv.write(stdin, "set -euxo pipefail;\n")
                            async_uv.write(stdin, source.build.run)
                            async_uv.shutdown(stdin)
                            async_uv.close(stdin)
                        end),
                    }
                end,
                win = function()
                    local powershell = require "mason-core.managers.powershell"
                    return powershell.command(source.build.run, {}, ctx.spawn)
                end,
            })
        end)
    end,
}

local release = {
    ---@param spec RegistryPackageSpec
    ---@param purl Purl
    ---@param opts PackageInstallOpts
    parse = function(spec, purl, opts)
        return Result.try(function(try)
            local asset = try(util.coalesce_by_target(spec.source.asset, opts):ok_or "PLATFORM_UNSUPPORTED")

            local expr_ctx = { version = purl.version }

            ---@type { out_file: string, download_url: string }[]
            local downloads = {}

            for __, file in ipairs(type(asset.file) == "string" and { asset.file } or asset.file) do
                local asset_file_components = _.split(":", file)
                local source_file = try(expr.interpolate(_.head(asset_file_components), expr_ctx))
                local out_file = try(expr.interpolate(_.last(asset_file_components), expr_ctx))

                if _.matches("/$", out_file) then
                    -- out_file is a dir expression (e.g. "libexec/")
                    out_file = path.concat { out_file, source_file }
                end

                table.insert(downloads, {
                    out_file = out_file,
                    download_url = settings.current.github.download_url_template:format(
                        ("%s/%s"):format(purl.namespace, purl.name),
                        purl.version,
                        source_file
                    ),
                })
            end

            local interpolated_asset = try(expr.tbl_interpolate(asset, expr_ctx))

            ---@class GitHubReleaseSource : PackageSource
            local source = {
                repo = ("%s/%s"):format(purl.namespace, purl.name),
                asset = interpolated_asset,
                downloads = downloads,
            }
            return source
        end)
    end,

    ---@async
    ---@param ctx InstallContext
    ---@param source GitHubReleaseSource
    install = function(ctx, source)
        local std = require "mason-core.managers.v2.std"
        local providers = require "mason-core.providers"

        return Result.try(function(try)
            try(util.ensure_valid_version(function()
                return providers.github.get_all_release_versions(source.repo)
            end))

            for __, download in ipairs(source.downloads) do
                if vim.in_fast_event() then
                    a.scheduler()
                end
                local out_dir = vim.fn.fnamemodify(download.out_file, ":h")
                local out_file = vim.fn.fnamemodify(download.out_file, ":t")
                if out_dir ~= "." then
                    try(Result.pcall(function()
                        ctx.fs:mkdir(out_dir)
                    end))
                end
                try(ctx:chdir(out_dir, function()
                    return Result.try(function(try)
                        try(std.download_file(download.download_url, out_file))
                        try(std.unpack(out_file))
                    end)
                end))
            end
        end)
    end,
}

local M = {}

---@param spec RegistryPackageSpec
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(spec, purl, opts)
    if spec.source.asset then
        return release.parse(spec, purl, opts)
    elseif spec.source.build then
        return build.parse(spec, purl, opts)
    else
        return Result.failure "Unknown source type."
    end
end

---@async
---@param ctx InstallContext
---@param source GitHubReleaseSource | GitHubBuildSource
function M.install(ctx, source)
    if source.asset then
        return release.install(ctx, source)
    elseif source.build then
        return build.install(ctx, source)
    else
        return Result.failure "Unknown source type."
    end
end

return M
