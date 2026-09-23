# 本地 MQTT 实验环境

## 环境概览

`lab/` 保存本地 MQTT 实验环境使用的 Mosquitto 配置、运行数据、日志和 PowerShell 开发脚本。项目根目录的 `compose.yaml` 使用 Eclipse Mosquitto 2，并将 Broker 限制在本机回环地址。

## 目录结构

```text
lab/
├── README.md
├── config/
│   ├── acl
│   ├── mosquitto.conf
│   └── passwords          # 本地认证数据库，已被 Git 忽略
├── data/
├── logs/
└── scripts/
    ├── start.ps1
    ├── stop.ps1
    ├── run-client.ps1
    └── test.ps1
```

- `config/mosquitto.conf`：保存 Mosquitto Broker 配置。
- `config/acl`：保存可提交到 Git 的最小 Topic 授权规则。
- `config/passwords`：保存本地真实认证数据库，已被 `.gitignore` 忽略，不应提交到 Git。
- `data/`：保存 Mosquitto 持久化数据。
- `logs/`：保存 Mosquitto 日志。
- `scripts/`：保存本地开发和实验脚本。

## Mosquitto 与 Docker Compose

项目使用 `eclipse-mosquitto:2` 镜像，容器名为 `mosquitto-lab`。Mosquitto 在容器内监听 MQTT 端口 `1883`，主机侧仅绑定 `127.0.0.1:1883`，不对公网开放。

Docker Compose 挂载关系：

```text
./lab/config -> /mosquitto/config
./lab/data   -> /mosquitto/data
./lab/logs   -> /mosquitto/log
```

当前 `mosquitto.conf` 禁用匿名连接并启用用户名 / 密码认证与 ACL：

```conf
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwords
acl_file /mosquitto/config/acl
```

原有数据持久化配置仍然启用，数据写入 `/mosquitto/data/`；Broker 日志写入 `/mosquitto/log/mosquitto.log`。

## Password file 初始化

`lab/config/passwords` 是本地真实认证数据库。该文件已被 `.gitignore` 忽略，不应提交到 Git，也不应读取或输出其中的密码哈希。

首次初始化时，可以在项目根目录使用 Compose 配置中的官方 `eclipse-mosquitto:2` 镜像运行 `mosquitto_passwd`：

```powershell
docker compose run --rm --user mosquitto mosquitto `
  mosquitto_passwd -c /mosquitto/config/passwords mqtt-client
```

命令会交互式要求输入并确认密码。不要使用 `-b`，也不要把密码放入命令参数、脚本、终端历史或文档。`-c` 会创建或覆盖 password file，只应在首次初始化时使用；后续更新现有用户时省略 `-c`：

```powershell
docker compose run --rm --user mosquitto mosquitto `
  mosquitto_passwd /mosquitto/config/passwords mqtt-client
```

在 Windows / Docker bind mount 环境中，需要确保生成的文件可由容器内 Mosquitto 用户读取。当前已验证的镜像环境中该用户曾显示为 UID/GID `1883:1883`，这只是排查权限问题时的参考，不是 MQTT 协议要求，也不保证所有镜像版本或平台都固定使用该数值。可以针对当前镜像检查 `mosquitto` 用户身份和挂载文件权限；不要通过放宽为所有用户可读来绕过权限问题。

## ACL 授权行为

当前 `lab/config/acl` 只有以下最小授权：

```text
user mqtt-client
topic readwrite test/topic
```

因此 `mqtt-client` 可以订阅和发布 `test/topic`。已验证对 `test/denied` 的 QoS 1 发布会由 Broker 通过 PUBACK 返回 `Not authorized`。

传统 ACL 下，未授权 SUBSCRIBE 在部分实际流程中仍可能返回 Granted QoS；这不表示获得了对应消息访问权限，后续消息访问仍由 ACL 控制。因此不要仅凭 SUBACK 判断完整授权结果。

## PowerShell 开发脚本

### `start.ps1`

执行：

```powershell
docker compose up -d
```

用于启动本地 MQTT 实验环境。

### `stop.ps1`

执行：

```powershell
docker compose down
```

用于停止并移除当前 Compose 环境。

### `run-client.ps1`

使用项目虚拟环境中的 Python 运行：

```text
src/mqtt_client.py
```

该脚本只运行 MQTT 客户端，不会自动启动 Broker。

客户端从本地 `.env` 读取 `MQTT_USERNAME` 和 `MQTT_PASSWORD`，使用 MQTT 5.0 用户名 / 密码认证。真实 `.env` 同样已被 Git 忽略。

### `test.ps1`

使用项目虚拟环境中的 Python 执行：

```powershell
pytest -q tests -p no:cacheprovider
```

用于运行当前 pytest 自动化测试。

## 脚本执行特性

四个脚本均具有以下特性：

- 使用 `$PSScriptRoot` 定位项目根目录，不依赖调用者的当前工作目录。
- 可从项目目录之外执行。
- 使用 `Push-Location` 和 `Pop-Location`，结束后恢复调用者的工作目录。
- 所需命令、文件或目录不存在时返回退出码 `1`。
- 透传核心外部命令的退出码。
- 不自动安装 Docker、Python 或项目依赖。

## 使用注意事项

- 运行 `start.ps1` 或 `stop.ps1` 前，Docker Desktop 和 Docker daemon 必须正常运行。
- `run-client.ps1` 不负责启动 Broker，请先确保本地 Broker 已运行。
- 当前 Broker 主机端口只绑定 `127.0.0.1:1883`，只服务本机实验环境。
- 当前用户名 / 密码连接没有 TLS，不适合直接暴露到公网。
- `.env`、Python 虚拟环境和依赖安装等完整步骤见项目根目录的 [`README.md`](../README.md)。
