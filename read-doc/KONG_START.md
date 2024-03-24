### KONG 启动流程

#### 启动概述

Docker file 中 启动命令: `CMD ["kong", "docker-start", "--nginx-conf", "/custom_nginx.template"]`。

可以看这段命令会在 `build/dockerfiles/entrypoint.sh` 中，首先会设置 `kong/templates/kong_defaults.lua` 中的环境变量，然后[执行](https://github.com/ffffffff0/read-kong/blob/master/build/dockerfiles/entrypoint.sh#L49) `kong prepare -p "$PREFIX" "$@"`，`kong`来自 `bin/kong` 脚本，是用来`#!/usr/local/openresty/bin/resty`程序来执行，[入口函数](https://github.com/ffffffff0/read-kong/blob/master/bin/kong#L170)为 `require("kong.cmd.init")("prepare", {[-p]="/usr/local/kong",[--nginx-conf]=""custom_nginx.template""})`。

 `cmd/init.lua` 这个文件是个 wrapper，解析了 `args` 之后调用 `prepare`, `start`等命令。 `cmd/prepare.lua` 文件`execute`函数就是准备过程：

```lua
local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  local ok, err = prefix_handler.prepare_prefix(conf, args.nginx_conf, nil, true)
  if not ok then
    error("could not prepare Kong prefix at " .. conf.prefix .. ": " .. err)
  end
end
```

在执行 prepare 后，会[执行](https://github.com/ffffffff0/read-kong/blob/master/build/dockerfiles/entrypoint.sh#L73)启动 Nginx 服务器，以 `nginx.conf`的配置，`nginx.conf` 这里是 `kong/templates/nginx.lua` 为[样本](https://github.com/ffffffff0/read-kong/blob/master/kong/templates/nginx_kong.conf)。

```bash
exec /usr/local/openresty/nginx/sbin/nginx -p "$PREFIX" -c nginx.conf
```

#### conf_loader

读取命令行里面传入的 `kong.conf` 文件，如果没有会读取 `kong/templates/nginx.lua` 中的配置，[设置](https://github.com/ffffffff0/read-kong/blob/master/kong/conf_loader/init.lua#L2094) `proxy_listen` 为 `proxy_listeners`。

#### prepare_prefix

这个文件主要在准备注入环境变量和 `kong.conf` 覆盖配置，生成 Nginx 启动的配置文件 `nginx.conf`。`prepare_prefix` [函数](https://github.com/ffffffff0/read-kong/blob/master/kong/cmd/utils/prefix_handler.lua#L444)前半部分在创建各个子目录。重要的部分是生成 Nginx 的配置文件，`compile_kong_conf` 函数其实是是用 `kong/templates` 目录下的 `nginx_kong.lua` 和 `nginx.lua` 分别生成两个文件，其中 `nginx_kong.lua` [里面](https://github.com/ffffffff0/read-kong/blob/master/kong/templates/nginx_kong.conf)包含了嵌入 Kong 的 Lua 代码的逻辑。

#### nginx.conf

在 `prepare_prefix` 之后，`/usr/local/kong` 下存在 `nginx.conf` 文件，`nginx.conf` 中会嵌入 `nginx_kong.lua` [里面](https://github.com/ffffffff0/read-kong/blob/master/kong/templates/nginx_kong.conf)包含了嵌入 Kong 的 Lua 代码的逻辑。

```nginx
init_by_lua_block {
    Kong = require 'kong'
    Kong.init()
}
init_worker_by_lua_block {
    Kong.init_worker()
}
exit_worker_by_lua_block {
    Kong.exit_worker()
}
# init_by_lua_block, init_work_by_lua_block, exit_worker_by_lua_block 是OpenResty这个指令是 OpenResty 提供Lua API 的一部分，
# 允许开发者在工作进程的生命周期结束时执行清理操作。
# init_by_lua: 在 Master 进程被创建时执行。
# init_worker_by_lua: 在每个Worker 进程被创建时执行。
# exit_worker_by_lua_block: 在Worker进程完成所有活跃连接的处理并且准备退出之前执行。
```

在server 块中也有定义了 Kong API 网关的主要行为，包括监听端口、SSL 配置、日志路径、代理设置等。

```nginx
server {
    server_name kong;
    ...
    rewrite_by_lua_block {
        Kong.rewrite()
    }
    access_by_lua_block {
        Kong.access()
    }
    header_filter_by_lua_block {
        Kong.header_filter()
    }
    body_filter_by_lua_block {
        Kong.body_filter()
    }
    log_by_lua_block {
        Kong.log()
    }
    ...
}
```

