# 本地 MQTT 实验环境

## 环境概览

`lab/` 保存正式本地 MQTT 实验环境使用的 Mosquitto 配置、TLS 配置、运行数据、日志和 PowerShell 开发脚本。项目根目录的 `compose.yaml` 使用 Eclipse Mosquitto 2，并将 TLS-only Broker 限制在本机回环地址 `127.0.0.1:8883`。明文 1883 已关闭。

当前安全层次包括：

- 单向 TLS 传输加密和 Broker identity verification
- `password_file` 用户名 / 密码认证
- `acl_file` Topic 授权

客户端验证 Broker certificate；Broker 不要求 client certificate，因此当前不是 mTLS。

## 目录结构

```text
lab/
├── README.md
├── config/
│   ├── acl
│   ├── mosquitto.conf
│   └── passwords          # 本地认证数据库，已被 Git 忽略
├── tls/
│   ├── openssl.cnf
│   └── generated/         # 本地 TLS 材料，已被 Git 忽略
├── data/
├── logs/
└── scripts/
    ├── generate-tls.ps1
    ├── start.ps1
    ├── stop.ps1
    ├── run-client.ps1
    ├── test.ps1
    └── test-integration.ps1
```

- `config/mosquitto.conf`：保存正式 Mosquitto Broker 配置。
- `config/acl`：保存可提交到 Git 的最小 Topic 授权规则。
- `config/passwords`：保存本地真实认证数据库，已被 `.gitignore` 忽略。
- `tls/openssl.cnf`：定义本地 Broker server certificate 的扩展和 SAN。
- `tls/generated/`：保存本地生成的 CA 与 Broker TLS 材料，整个目录已被 Git 忽略。
- `data/`：保存 Mosquitto 持久化数据。
- `logs/`：保存 Mosquitto 日志。
- `scripts/`：保存本地开发、证书生成和测试脚本。

## Mosquitto 与 Docker Compose

项目使用 `eclipse-mosquitto:2` 镜像，容器名为 `mosquitto-lab`。正式 Broker 在容器内只监听 TLS 端口 `8883`，主机侧只发布 `127.0.0.1:8883`，不对公网开放。明文 1883 listener 和 Compose mapping 均已删除。

Docker Compose 挂载关系：

```text
./lab/config        -> /mosquitto/config
./lab/data          -> /mosquitto/data
./lab/logs          -> /mosquitto/log
./lab/tls/generated -> /mosquitto/certs   (read-only)
```

当前 `mosquitto.conf` 的核心配置为：

```conf
allow_anonymous false
password_file /mosquitto/config/passwords
acl_file /mosquitto/config/acl

listener 8883
protocol mqtt
certfile /mosquitto/certs/server.crt
keyfile /mosquitto/certs/server.key
tls_version tlsv1.2
require_certificate false
```

`require_certificate false` 表示不要求 client certificate，因此不是 mTLS。`tls_version tlsv1.2` 设置最低 TLS 版本，不会禁用 TLS 1.3；当前环境已实际协商 TLS 1.3。

数据持久化配置仍然启用，数据写入 `/mosquitto/data/`；Broker 日志写入 `/mosquitto/log/mosquitto.log`。

## TLS certificate 初始化

在项目根目录执行：

```powershell
.\lab\scripts\generate-tls.ps1
```

脚本使用 `lab/tls/openssl.cnf`，在 `lab/tls/generated/` 中创建本地 CA、Broker private key、CSR 和由该 CA 签发的 server certificate。Server certificate 使用 `server_certificate` extension，包含：

```text
CA:FALSE
serverAuth
SAN = IP:127.0.0.1
```

客户端应连接 `127.0.0.1` 并使用 `lab/tls/generated/ca.crt` 验证 certificate chain 和 IP SAN。Hostname/IP verification 必须保持开启；项目不使用 `tls_insecure_set(True)`。

### OpenSSL 发现顺序

Windows 脚本按以下顺序查找 OpenSSL：

1. PATH 中的 `openssl`
2. 当前 Git for Windows 安装自带的 `usr/bin/openssl.exe`

两者均不存在时脚本失败，不修改系统 PATH，也不使用机器专有的硬编码安装路径。

### 覆盖保护和 Git 安全

`lab/tls/generated/` 已被 Git 忽略。CA private key 和 server private key 只应存在于本地，不能提交到 Git，也不应读取或输出其内容。

如果任何受管 TLS 生成物已经存在，脚本默认拒绝覆盖。确实需要重新生成完整本地 TLS identity 时执行：

```powershell
.\lab\scripts\generate-tls.ps1 -Force
```

`-Force` 会替换当前受管的本地 CA 和 Broker identity。使用它会使信任旧 CA 的客户端失效，因此不应随意执行。

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

需要确保生成的文件可由容器内 Mosquitto 用户读取。排查 bind mount 权限问题时，应检查当前镜像中的用户身份和文件 owner/mode，不要通过对所有用户开放读取权限来绕过问题。

本地 `.env` 中的 `MQTT_PASSWORD` 必须与该 password file 中的 `mqtt-client` 凭据一致。真实密码只能写入已被 Git 忽略的本地 `.env`。

## ACL 授权行为

当前 `lab/config/acl` 只有以下最小授权：

```text
user mqtt-client
topic readwrite test/topic
```

因此 `mqtt-client` 可以订阅和发布 `test/topic`。已验证对 `test/denied` 的 QoS 1 发布会由 Broker 通过 PUBACK 返回 `Not authorized`。

传统 ACL 下，未授权 SUBSCRIBE 在部分实际流程中仍可能返回 Granted QoS；这不表示获得了对应消息访问权限，后续消息访问仍由 ACL 控制。因此不要仅凭 SUBACK 判断完整授权结果。

## 客户端配置

本地 `.env` 应基于项目根目录的 `.env.example` 创建。TLS 相关的关键配置为：

```ini
MQTT_HOST=127.0.0.1
MQTT_PORT=8883
MQTT_CA_FILE=lab/tls/generated/ca.crt
MQTT_USERNAME=mqtt-client
MQTT_PASSWORD=
```

只在本地 `.env` 中填写真实 `MQTT_PASSWORD`，不要提交 `.env`。相对 CA 路径由客户端按项目根目录解析。

## 启动、运行与停止

建议顺序是：生成本地 TLS 材料、初始化 password file、创建本地 `.env`，然后启动 Broker 并运行客户端。

### `start.ps1`

```powershell
.\lab\scripts\start.ps1
```

该脚本执行 `docker compose up -d`，启动正式 TLS-only Broker。

### `run-client.ps1`

```powershell
.\lab\scripts\run-client.ps1
```

该脚本使用项目虚拟环境运行 `src/mqtt_client.py`，但不会自动启动 Broker。客户端使用正确 CA 验证 `127.0.0.1:8883` 的 Broker identity，再使用 MQTT 5.0 用户名 / 密码认证完成订阅、QoS 1 发布、接收和断开流程。

### `stop.ps1`

```powershell
.\lab\scripts\stop.ps1
```

该脚本执行 `docker compose down`，停止并移除正式 Compose 环境。

## Unit tests

执行：

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests -p no:cacheprovider
```

也可以运行：

```powershell
.\lab\scripts\test.ps1
```

当前已验证结果：

```text
32 passed
0 failed
0 warnings
```

Unit tests 不运行 Docker，也不依赖本地 `lab/tls/generated/`。

## TLS integration tests

执行：

```powershell
.\lab\scripts\test-integration.ps1
```

Runner 使用与正式 Broker 分离的 `127.0.0.1:18884` TLS-only Broker，并覆盖 6 个场景：

1. 正确凭据完整 TLS MQTT 流程
2. TLS 成功后错误密码拒绝
3. TLS + ACL allow
4. TLS + ACL deny
5. untrusted CA verification failure
6. hostname/SAN mismatch verification failure

当前已验证结果：

```text
6 passed
0 failed
0 warnings
```

每次运行时，runner 会在系统临时目录中：

- 动态生成独立 integration CA、server key/CSR/certificate
- 生成独立 untrusted CA
- 创建一次性 password file 和随机凭据
- 通过正确 CA 和 `127.0.0.1` IP SAN verification 完成 TLS readiness
- 向 pytest 传递临时 CA 路径和凭据

Runner 不读取正式 `.env` 或正式 password file，也不复用正式 `lab/tls/generated/`。无论测试成功还是失败，它都会尝试停止并删除 integration Compose 环境、清除 `MQTT_INTEGRATION_*` 环境变量，并删除临时配置、certificates 和所有临时 private keys。

TLS integration tests 当前只由本地 runner 执行；GitHub Actions 仍只运行 unit tests。

## 退出码

- `0`：完整 MQTT 流程成功。
- `2`：本地静态配置错误。
- `3`：Broker、MQTT 或 TLS 运行期失败；CA trust failure 和 hostname/IP SAN mismatch 均属于此类。

## 脚本执行特性

- 脚本使用 `$PSScriptRoot` 定位项目根目录，不依赖调用者的当前工作目录。
- 脚本可从项目目录之外执行，并在结束后恢复调用者的工作目录。
- 所需命令、文件或目录不存在时会返回非零退出码。
- 脚本不自动安装 Docker、Python、OpenSSL 或项目依赖。

## 使用注意事项

- 运行 `start.ps1`、`stop.ps1` 或 integration runner 前，Docker Desktop 和 Docker daemon 必须正常运行。
- 启动正式 Broker 前必须先生成本地 TLS 材料并初始化 password file。
- `run-client.ps1` 不负责启动 Broker，请先确认正式 Broker 正在运行。
- 正式 Broker 只绑定 `127.0.0.1:8883`；明文 1883 已关闭。
- 当前为单向 TLS，不是 mTLS，并继续强制用户名 / 密码认证和 Topic ACL。
- `.env`、password file、CA private key 和 server private key 都不得提交或输出。
- 完整的环境与依赖安装步骤见项目根目录的 [`README.md`](../README.md)。
