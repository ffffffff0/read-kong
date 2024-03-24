---
-- The Plugin Development Kit (PDK) is set of Lua functions and variables
-- that can be used by plugins to implement their own logic.
-- The PDK is originally released in Kong 0.14.0.
-- The PDK is guaranteed to be forward-compatible
-- from its 1.0.0 release and onward.
--
-- The Plugin Development Kit is accessible from the `kong` global variable,
-- and various functionalities are namespaced under this table, such as
-- `kong.request`, `kong.log`, etc.
--
-- @module PDK
-- @release 1.0.0


---
-- Top-level variables
-- @section top_level_variables


---
-- A human-readable string containing the version number of the currently
-- running node.
--
-- @field kong.version
-- @usage print(kong.version) -- "2.0.0"


---
-- An integral number representing the version number of the currently running
-- node, useful for comparison and feature-existence checks.
--
-- @field kong.version_num
-- @usage
-- if kong.version_num < 13000 then -- 000.130.00 -> 0.13.0
--   -- no support for Routes & Services
-- end


---
-- A read-only table containing the configuration of the current Kong node,
-- based on the configuration file and environment variables.
--
-- See [kong.conf.default](https://github.com/Kong/kong/blob/master/kong.conf.default)
-- for details.
--
-- Comma-separated lists in the `kong.conf` file get promoted to arrays of strings in this
-- table.
--
-- @field kong.configuration
-- @usage
-- print(kong.configuration.prefix) -- "/usr/local/kong"
-- -- this table is read-only; the following throws an error:
-- kong.configuration.prefix = "foo"


--- Request/Response
-- @section request_response


--- Current request context data
-- @field kong.ctx
-- @redirect kong.ctx


--- Client information module
-- @field kong.client
-- @redirect kong.client


--- Client request module
-- @field kong.request
-- @redirect kong.request


--- Properties of the connection to the Service
-- @field kong.service
-- @redirect kong.service


--- Manipulation of the request to the Service
-- @field kong.service.request
-- @redirect kong.service.request


--- Manipulation of the response from the Service
-- @field kong.service.response
-- @redirect kong.service.response


--- Client response module
-- @field kong.response
-- @redirect kong.response


--- Router module
-- @field kong.router
-- @redirect kong.router


--- Nginx module
-- @field kong.nginx
-- @redirect kong.nginx


--- Singletons
-- @section singletons


---
-- Instance of Kong's DAO (the `kong.db` module). Contains accessor objects
-- to various entities.
--
-- A more thorough documentation of this DAO and new schema definitions is to
-- be made available in the future.
--
-- @field kong.db
-- @usage
-- kong.db.services:insert()
-- kong.db.routes:select()


---
-- Instance of Kong's DNS resolver, a client object from the
-- [lua-resty-dns-client](https://github.com/kong/lua-resty-dns-client) module.
--
-- **Note:** Usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.dns


---
-- Instance of Kong's IPC module for inter-workers communication from the
-- [lua-resty-events](https://github.com/Kong/lua-resty-events)
-- module.
--
-- **Note:** Usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.worker_events


---
-- Instance of Kong's cluster events module for inter-nodes communication.
--
-- **Note:** Usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.cluster_events


---
-- Instance of Kong's database caching object, from the `kong.cache` module.
--
-- **Note:** Usage of this module is currently reserved to the core or to
-- advanced users.
--
-- @field kong.cache

---
-- Instance of Kong's IP module to determine whether a given IP address is
-- trusted
-- @field kong.ip
-- @redirect kong.ip

--- Utilities
-- @section utilities


--- Node-level utilities
-- @field kong.node
-- @redirect kong.node


--- Utilities for Lua tables
-- @field kong.table
-- @redirect kong.table


--- Instance of Kong logging factory with various utilities
-- @field kong.log
-- @redirect kong.log


assert(package.loaded["resty.core"])

local base = require "resty.core.base"

local type = type
local error = error
local rawget = rawget
local ipairs = ipairs
local setmetatable = setmetatable


local MAJOR_MODULES = {
      "table",
      "node",
      "log",
      "ctx",
      "ip",
      "client",
      "service",
      "request",
      "service.request",
      "service.response",
      "response",
      "router",
      "nginx",
      "cluster",
      "vault",
      "tracing",
      "plugin",
}

if ngx.config.subsystem == 'http' then
  table.insert(MAJOR_MODULES, 'client.tls')
end

local _PDK = { }


function _PDK.new(kong_config, self)
  if kong_config then
    if type(kong_config) ~= "table" then
      error("kong_config must be a table", 2)
    end

  else
    kong_config = {}
  end

  self = self or {}

  self.configuration = setmetatable({
    remove_sensitive = function()
      local conf_loader = require "kong.conf_loader"
      return conf_loader.remove_sensitive(kong_config)
    end,
  }, {
    __index = function(_, v)
      return kong_config[v]
    end,

    __newindex = function()
      error("cannot write to configuration", 2)
    end,
  })

  for _, module_name in ipairs(MAJOR_MODULES) do
  -- 在 Lua 中，表（table）是引用传递的。这意味着当一个表赋值给另一个变量时，
  -- 两个变量实际上都指向同一个 Lua 表对象。在这个代码段中，self 被赋值给 parent，
  -- 所以 parent 变量现在引用了与 self 相同的表。当通过 parent 来增加或修改内容时，实际上是在修改 self 引用的同一个表。
    local parent = self
    for part in module_name:gmatch("([^.]+)%.") do
      if not parent[part] then
        parent[part] = {}
      end

      parent = parent[part]
    end
    -- 因为 Lua 中的变量并不直接存储值，而是存储对值的引用。
    -- 所以，当执行 parent[part] = {} 时，实际上是在 self 指向的表中创建了一个新的键 part，
    -- 其值为一个空表。之后，当更新 parent = parent[part] 时，
    -- 实际上是将 parent 变量的引用指向了 self 表中的 part 键所对应的新表。

    local child = module_name:match("[^.]*$")
    if parent[child] then
      error("PDK module '" .. module_name .. "' conflicts with a key")
    end

    local mod = require("kong.pdk." .. module_name)

    parent[child] = mod.new(self)
    -- 虽然 parent 在循环中被修改了，但 self 本身并没有被改变。
    -- 只有 self 对象的属性（也就是模块）被添加或修改了。
    -- self 可以在循环结束后仍然保持其原始值的原因。这种方法可以在不改变原始对象的情况下修改其属性
  end

  self._log = self.log
  self.log = nil

  return setmetatable(self, {
    __index = function(t, k)
      if k == "log" then
        if base.get_request() then
          local log = ngx.ctx.KONG_LOG
          if log then
            return log
          end
        end

        return (rawget(t, "_log"))
      end
    end
  })
end


return _PDK
