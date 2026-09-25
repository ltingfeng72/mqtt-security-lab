# ProtoFuzz-AI

ProtoFuzz-AI 是一个用于学习和研究 MQTT 5.0 协议及相关软件开发流程的本地项目。当前项目提供基于 Docker Compose 和 Eclipse Mosquitto 的本地 TLS Broker，以及用于演示 MQTT 连接、订阅、发布、接收和断开的 Python 客户端。

## 当前已实现功能

- 使用 Docker Compose 启动 Eclipse Mosquitto
- 在 `127.0.0.1:8883` 提供仅限本机访问的 TLS-only MQTT Broker
- 关闭正式环境的明文 MQTT 1883 listener 和端口映射
- 使用 Paho MQTT 5.0 和 Callback API v2 的 Python 客户端
- 使用本地 CA 验证 Broker server certificate 和 `IP SAN:127.0.0.1`
- MQTT 用户名 / 密码认证
- Mosquitto ACL Topic 授权
- 完整演示 TLS 连接、订阅、QoS 1 发布、接收和断开流程
- 日志记录、配置校验和明确的进程退出码
- 使用 `.env` 管理 MQTT 客户端配置
- 使用 pytest 编写配置校验和 MQTT callback / runtime 单元测试
- 使用隔离 Broker 执行 TLS、认证和 ACL integration tests
- 用于证书生成、启动、停止、运行客户端和执行测试的 PowerShell 脚本

## 当前架构

```text
Python MQTT 5.0 client
        |
        | TLS + CA verification + IP SAN verification
        | username/password
        v
127.0.0.1:8883
        |
Eclipse Mosquitto
        |
        +-- password_file authentication
        +-- acl_file authorization
```

正式 Broker 只发布 `127.0.0.1:8883`，明文 1883 已关闭。当前采用单向 TLS：客户端验证 Broker 身份，Broker 不要求客户端证书，因此不是 mTLS。用户名 / 密码认证和 Topic ACL 在 TLS 连接之上继续生效。

## 环境要求

- Windows
- PowerShell
- Python 3
- Docker Desktop
- Git for Windows
- OpenSSL，可来自 PATH 或当前 Git for Windows 安装

执行 Docker 相关操作前，请确保 Docker Desktop 已启动，并且 Docker daemon 正常运行。

## 项目结构

```text
.
├── compose.yaml
├── README.md
├── requirements.txt
├── requirements-dev.txt
├── .env.example
├── src/
│   └── mqtt_client.py
├── tests/
│   ├── test_config_validation.py
│   └── test_mqtt_runtime.py
├── integration_tests/
│   ├── compose.yaml
│   ├── fixtures/
│   │   ├── acl
│   │   └── mosquitto.conf
│   └── test_auth_acl.py
└── lab/
    ├── README.md
    ├── config/
    │   ├── acl
    │   ├── mosquitto.conf
    │   └── passwords          # 本地文件，已被 Git 忽略
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

`.venv`、真实 `.env`、`lab/config/passwords` 和 `lab/tls/generated/` 均为本地内容，不纳入 Git 跟踪。`lab/config/acl` 和 `lab/tls/openssl.cnf` 可以提交到 Git；`lab/data/` 与 `lab/logs/` 是 Broker 运行时目录。

## 安装与配置

以下命令均在项目根目录的 PowerShell 中执行。

### 创建 Python 虚拟环境

```powershell
python -m venv .venv
```

### 安装运行依赖

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

当前运行依赖：

- `paho-mqtt==2.1.0`
- `python-dotenv==1.2.3`

### 安装开发依赖

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

当前开发依赖为 `pytest==9.1.1`。

### 生成本地 TLS 材料

首次启动 Broker 前执行：

```powershell
.\lab\scripts\generate-tls.ps1
```

脚本在 `lab/tls/generated/` 中生成本地 CA、Broker private key、CSR 和由该 CA 签发的 server certificate。该目录已被 Git 忽略；CA private key 和 server private key 只能保留在本地，不得提交到 Git。证书材料应由每个开发环境在本地生成。

脚本按以下顺序查找 OpenSSL：

1. PATH 中的 `openssl`
2. 当前 Git for Windows 安装自带的 `usr/bin/openssl.exe`

两者均不存在时脚本失败，不会修改系统 PATH。

如果受管 TLS 生成物已经存在，脚本默认拒绝覆盖。如确实需要替换当前本地 TLS identity，可显式执行：

```powershell
.\lab\scripts\generate-tls.ps1 -Force
```

`-Force` 会替换当前受管的本地 CA 和 Broker TLS identity，不应随意使用。重新生成后，依赖旧 CA 的客户端配置也需要同步更新。

### 创建本地 `.env`

`.env.example` 是可提交的配置模板，`.env` 是本地实际配置并已被 Git 忽略。复制模板后，只在本地 `.env` 中填写真实密码：

```powershell
Copy-Item .env.example .env
```

当前配置模板为：

```ini
MQTT_HOST=127.0.0.1
MQTT_PORT=8883
MQTT_CA_FILE=lab/tls/generated/ca.crt
MQTT_TOPIC=test/topic
MQTT_MESSAGE=hello mqtt from python
MQTT_CLIENT_ID=mqtt-python-client
MQTT_USERNAME=mqtt-client
MQTT_PASSWORD=
```

`MQTT_PASSWORD` 在 `.env.example` 中必须保持为空。请只在本地 `.env` 中填写与 Mosquitto password file 对应的真实密码；`.env` 不应提交。不要把密码写入文档、命令参数或 Git。

相对形式的 `MQTT_CA_FILE` 按项目根目录解析。静态配置校验要求该值非空、路径存在且指向普通文件。

## 快速开始

### 初始化 password file

首次启动前需要以交互方式创建本地 password file，具体安全步骤见 [`lab/README.md`](lab/README.md)。

### 启动 Broker

确保本地 TLS 材料和 password file 已初始化，并且 Docker Desktop 正在运行，然后执行：

```powershell
.\lab\scripts\start.ps1
```

脚本通过 Docker Compose 启动 Mosquitto。正式本地 endpoint 只有 `127.0.0.1:8883`。

### 运行 MQTT 客户端

```powershell
.\lab\scripts\run-client.ps1
```

客户端使用 `MQTT_CA_FILE` 验证 Broker certificate 和 IP SAN，再使用本地 `.env` 中的用户名与密码完成 MQTT CONNECT。连接成功后，客户端订阅配置主题、以 QoS 1 向同一主题发布消息，收到预期消息后正常断开。

### 停止 Broker

```powershell
.\lab\scripts\stop.ps1
```

## TLS 身份验证

当前 Broker server certificate 包含：

```text
SAN = IP:127.0.0.1
```

客户端保持 certificate verification 和 hostname/IP verification 开启，并使用 `127.0.0.1` 作为连接目标。项目设计不使用 `tls_insecure_set(True)`，也不关闭 hostname verification。使用不受信任 CA 或与 SAN 不匹配的主机名时，TLS 握手会失败。

`tls_version tlsv1.2` 设置的是最低 TLS 版本，并不禁用 TLS 1.3；当前正式环境已实际协商 TLS 1.3。

## MQTT 配置与校验

配置项及当前校验规则：

- `MQTT_HOST`：Broker 地址，不能为空。
- `MQTT_PORT`：Broker 端口，必须为整数且在 `1`–`65535` 范围内。
- `MQTT_CA_FILE`：信任 CA 文件；不能为空，解析后必须存在且为普通文件。
- `MQTT_TOPIC`：订阅和发布使用的主题，不能为空，且不能包含通配符 `+` 或 `#`。
- `MQTT_MESSAGE`：发布的消息内容，不能为空。
- `MQTT_CLIENT_ID`：客户端标识，不能为空。
- `MQTT_USERNAME`：连接 Broker 使用的用户名，不能为空或仅包含空白字符。
- `MQTT_PASSWORD`：连接 Broker 使用的密码，不能为空或仅包含空白字符；校验不会修改密码原值。

CA 的静态校验只检查路径和文件类型，不在该阶段解析 certificate 内容。TLS trust 和 Broker identity 在实际握手时验证。

## 退出码

- `0`：完整 MQTT 流程成功，包括收到预期 Topic 和 Message。
- `2`：本地静态配置校验失败，例如 CA 路径为空、不存在或不是普通文件。
- `3`：Broker、MQTT 或 TLS 运行期失败，包括 TLS trust failure 和 hostname/IP SAN verification failure。

## 自动化测试

### Unit tests

Unit tests 覆盖配置校验、CA 路径解析、CONNECT、SUBACK、PUBACK、消息接收、断开连接和 TLS/socket runtime exit code。它们不需要连接 Broker，也不依赖 `lab/tls/generated/`。

执行命令：

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests -p no:cacheprovider
```

也可以使用：

```powershell
.\lab\scripts\test.ps1
```

当前已验证结果：

```text
32 passed
0 failed
0 warnings
```

### TLS integration tests

执行命令：

```powershell
.\lab\scripts\test-integration.ps1
```

当前 6 个 integration tests 全部运行在 TLS 上：

1. 正确凭据完成完整 TLS MQTT 流程
2. TLS 成功后错误密码被拒绝
3. TLS + ACL allow
4. TLS + ACL deny
5. untrusted CA 被拒绝
6. hostname/SAN mismatch 被拒绝

当前已验证结果：

```text
6 passed
0 failed
0 warnings
```

Integration runner 使用独立的 `127.0.0.1:18884` Broker。每次运行都会在系统临时目录动态生成 integration CA、server certificate/private key 和独立 untrusted CA；它不读取正式 `.env`、正式 password file，也不使用正式 `lab/tls/generated/`。测试结束后 runner 会停止并删除 integration Compose 环境，同时删除临时配置、证书和所有临时 private keys。

### CI 状态

GitHub Actions 当前只运行 unit tests：

```text
python -m pytest -q tests -p no:cacheprovider
```

TLS integration tests 当前仍由本地 `test-integration.ps1` runner 执行，尚未加入 GitHub Actions。

## 本地实验环境

Mosquitto 配置、本地挂载目录、证书初始化和开发脚本的详细说明见 [`lab/README.md`](lab/README.md)。

## 安全边界

- 正式 Broker 只绑定本机回环地址 `127.0.0.1:8883`；明文 1883 已关闭。
- TLS 提供传输加密及 Broker 身份验证，用户名 / 密码和 ACL 分别提供认证与 Topic 授权。
- 当前为单向 TLS，不是 mTLS；客户端不向 Broker 提供 client certificate。
- `.env`、password file、CA private key 和 server private key 均不得提交或输出。
- 当前配置只用于本机实验；不要把 listener 或 Compose 端口映射改为公共网络地址。
