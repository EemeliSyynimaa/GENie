--
-- _cmake.lua
-- Define the CMake action(s).
-- Copyright (c) 2015 Miodrag Milanovic
-- Modifications and additions in 2017 by Maurizio Petrarota
--

local cmake = premake.cmake
local tree = premake.tree

local function is_excluded(prj, cfg, file)
    if table.icontains(prj.excludes, file) then
        return true
    end

    if table.icontains(cfg.excludes, file) then
        return true
    end

    return false
end


function cmake.list(value)
    if #value > 0 then
        return " " .. table.concat(value, " ")
    else
        return ""
    end
end

function cmake.files(prj)
    local tr = premake.project.buildsourcetree(prj)
    tree.traverse(tr, {
        onbranchenter = function(node, depth)
        end,
        onbranchexit = function(node, depth)
        end,
        onleaf = function(node, depth)
            _p(1, '../%s', node.cfg.name)
        end,
    }, true, 1)
end

function cmake.header(prj)
    _p('# %s project autogenerated by GENie', premake.action.current().shortname)
    _p('cmake_minimum_required(VERSION 2.8.4)')
    _p('')
    _p('project(%s)', premake.esc(prj.name))
end

function cmake.customtasks(prj)
    local dirs = {}
    local tasks = {}
    for _, custombuildtask in ipairs(prj.custombuildtask or {}) do
        for _, buildtask in ipairs(custombuildtask or {}) do
            table.insert(tasks, buildtask)
            local d = string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s", path.getdirectory(path.getrelative(prj.location, buildtask[2])))
            if not table.contains(dirs, d) then
                table.insert(dirs, d)
                _p('file(MAKE_DIRECTORY \"%s\")', d)
            end
        end
    end
    _p('')

    for _, buildtask in ipairs(tasks) do
        local deps = string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s ", path.getrelative(prj.location, buildtask[1]))
        local outputs = string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s ", path.getrelative(prj.location, buildtask[2]))
        local msg = ""

        for _, depdata in ipairs(buildtask[3] or {}) do
            deps = deps .. string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s ", path.getrelative(prj.location, depdata))
        end

        _p('add_custom_command(')
        _p(1, 'OUTPUT %s', outputs)
        _p(1, 'DEPENDS %s', deps)

        for _, cmdline in ipairs(buildtask[4] or {}) do
            if (cmdline:sub(1, 1) ~= "@") then
                local cmd = cmdline
                local num = 1
                for _, depdata in ipairs(buildtask[3] or {}) do
                    cmd = string.gsub(cmd, "%$%(" .. num .. "%)", string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s ", path.getrelative(prj.location, depdata)))
                    num = num + 1
                end

                cmd = string.gsub(cmd, "%$%(<%)", string.format("${CMAKE_CURRENT_SOURCE_DIR}/../%s ", path.getrelative(prj.location, buildtask[1])))
                cmd = string.gsub(cmd, "%$%(@%)", outputs)

                _p(1, 'COMMAND %s', cmd)
            else
                msg = cmdline
            end
        end
        _p(1, 'COMMENT \"%s\"', msg)
        _p(')')
        _p('')
    end
end

function cmake.depRules(prj)
    local maintable = {}
    for _, dependency in ipairs(prj.dependency or {}) do
        for _, dep in ipairs(dependency or {}) do
            if path.issourcefile(dep[1]) then
                local dep1 = premake.esc(path.getrelative(prj.location, dep[1]))
                local dep2 = premake.esc(path.getrelative(prj.location, dep[2]))
                if not maintable[dep1] then maintable[dep1] = {} end
                table.insert(maintable[dep1], dep2)
            end
        end
    end

    for key, _ in pairs(maintable) do
        local deplist = {}
        local depsname = string.format('%s_deps', path.getname(key))

        for _, d2 in pairs(maintable[key]) do
            table.insert(deplist, d2)
        end
        _p('set(')
        _p(1, depsname)
        for _, v in pairs(deplist) do
            _p(1, '${CMAKE_CURRENT_SOURCE_DIR}/../%s', v)
        end
        _p(')')
        _p('')
        _p('set_source_files_properties(')
        _p(1, '\"${CMAKE_CURRENT_SOURCE_DIR}/../%s\"', key)
        _p(1, 'PROPERTIES OBJECT_DEPENDS \"${%s}\"', depsname)
        _p(')')
        _p('')
    end
end

function cmake.commonRules(conf, str)
    local Dupes = {}
    local t2 = {}
    for _, cfg in ipairs(conf) do
        local cfgd = iif(str == 'include_directories(../%s)', cfg.includedirs, cfg.defines)
        for _, v in ipairs(cfgd) do
            if(t2[v] == #conf - 1) then
                _p(str, v)
                table.insert(Dupes, v)
            end
            if not t2[v] then
                t2[v] = 1
            else
                t2[v] = t2[v] + 1
            end
        end
    end
    return Dupes
end

function cmake.cfgRules(cfg, dupes, str)
    for _, v in ipairs(cfg) do
        if (not table.icontains(dupes, v)) then
            _p(1, str, v)
        end
    end
end

function cmake.removeCrosscompiler(platforms)
    for i = #platforms, 1, -1 do
        if premake.platforms[platforms[i]].iscrosscompiler then
            table.remove(platforms, i)
        end
    end
end

function cmake.project(prj)
    io.indent = "  "
    cmake.header(prj)
    _p('set(')
    _p('source_list')
    cmake.files(prj)
    _p(')')
    _p('')

    local nativeplatform = iif(os.is64bit(), "x64", "x32")
    local cc = premake.gettool(prj)
    local platforms = premake.filterplatforms(prj.solution, cc.platforms, "Native")

    cmake.removeCrosscompiler(platforms)

    local configurations = {}

    for _, platform in ipairs(platforms) do
        for cfg in premake.eachconfig(prj, platform) do
            -- TODO: Extend support for 32-bit targets on 64-bit hosts
            if cfg.platform == nativeplatform then
                table.insert(configurations, cfg)
            end
        end
    end

    local commonIncludes = cmake.commonRules(configurations, 'include_directories(../%s)')
    local commonDefines = cmake.commonRules(configurations, 'add_definitions(-D%s)')
    _p('')

    for _, cfg in ipairs(configurations) do
        _p('if(CMAKE_BUILD_TYPE MATCHES \"%s\")', cfg.name)

        -- add includes directories
        cmake.cfgRules(cfg.includedirs, commonIncludes, 'include_directories(../%s)')

        -- add build defines
        cmake.cfgRules(cfg.defines, commonDefines, 'add_definitions(-D%s)')

        -- set CXX flags
        _p(1, 'set(CMAKE_CXX_FLAGS \"${CMAKE_CXX_FLAGS} %s\")', cmake.list(table.join(cc.getcppflags(cfg), cc.getcflags(cfg), cc.getcxxflags(cfg), cfg.buildoptions, cfg.buildoptions_cpp)))

        -- set C flags
        _p(1, 'set(CMAKE_C_FLAGS \"${CMAKE_C_FLAGS} %s\")', cmake.list(table.join(cc.getcppflags(cfg), cc.getcflags(cfg), cfg.buildoptions, cfg.buildoptions_c)))

        _p('endif()')
        _p('')
    end

    -- force CPP if needed
    if (prj.options.ForceCPP) then
        _p('set_source_files_properties(${source_list} PROPERTIES LANGUAGE CXX)')
    end

    -- add custom tasks
    cmake.customtasks(prj)

    -- per-dependency build rules
    cmake.depRules(prj)

    for _, cfg in ipairs(configurations) do
        _p('if(CMAKE_BUILD_TYPE MATCHES \"%s\")', cfg.name)

        if (prj.kind == 'StaticLib') then
            _p(1, 'add_library(%s STATIC ${source_list})', premake.esc(cfg.buildtarget.basename))
        end

        if (prj.kind == 'SharedLib') then
            _p(1, 'add_library(%s SHARED ${source_list})', premake.esc(cfg.buildtarget.basename))
        end
        if (prj.kind == 'ConsoleApp' or prj.kind == 'WindowedApp') then
            _p(1, 'add_executable(%s ${source_list})', premake.esc(cfg.buildtarget.basename))
            _p(1, 'target_link_libraries(%s%s%s)', premake.esc(cfg.buildtarget.basename), cmake.list(premake.esc(premake.getlinks(cfg, "siblings", "basename"))), cmake.list(cc.getlinkflags(cfg)))
        end
        _p('endif()')
        _p('')
    end
end
