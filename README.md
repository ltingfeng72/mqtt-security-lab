# ProtoFuzz-AI

ProtoFuzz-AI 是一个用于学习和研究 MQTT 5.0 协议及相关软件开发流程的本地项目。当前项目提供基于 Docker Compose 和 Eclipse Mosquitto 的本地 Broker，以及用于演示 MQTT 连接、订阅、发布、接收和断开的 Python 客户端。

## 当前已实现功能

- 使用 Docker Compose 启动 Eclipse Mosquitto
- 在 `127.0.0.1:1883` 提供仅限本机访问的 MQTT Broker
- 使用 Paho MQTT 5.0 和 Callback API v2 的 Python 客户端
- 完整演示 MQTT 连接、订阅、发布、接收和断开流程
- MQTT 用户名 / 密码认证
- Mosquitto ACL Topic 授权
- QoS 1 发布与 Broker 运行期失败退出码
- 日志记录与基础异常处理
- 使用 `.env` 管理 MQTT 配置
- MQTT 配置校验
- 使用 pytest 编写的配置校验和 MQTT callback / runtime 状态测试
- 用于启动、停止、运行客户端和执行测试的 PowerShell 脚本

## 环境要求

- Windows
- PowerShell
- Python 3
- Docker Desktop
- Git

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
└── lab/
    ├── README.md
    ├── config/
    │   ├── acl
    │   ├── mosquitto.conf
    │   └── passwords          # 本地文件，已被 Git 忽略
    ├── data/
    ├── logs/
    └── scripts/
        ├── start.ps1
        ├── stop.ps1
        ├── run-client.ps1
        └── test.ps1
```

`.venv`、真实 `.env` 和 `lab/config/passwords` 均为本地文件，不纳入 Git 跟踪；`lab/config/acl` 可以提交到 Git，`lab/data/` 和 `lab/logs/` 是 Broker 运行时目录。

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

### 创建本地 `.env`

`.env.example` 是可提交的配置模板，`.env` 是本地实际配置并已被 Git 忽略。复制模板后，可按需修改本地 `.env`：

```powershell
Copy-Item .env.example .env
```

认证配置模板如下：

```ini
MQTT_USERNAME=mqtt-client
MQTT_PASSWORD=
```

用户名固定使用当前 ACL 中的 `mqtt-client`。`MQTT_PASSWORD` 在可提交的 `.env.example` 中必须保持为空，请只在本地 `.env` 中填写与 Mosquitto password file 对应的真实密码。不要把密码写入文档、命令参数或 Git。

## 快速开始

### 启动 Broker

确保 Docker Desktop 正在运行，然后执行：

```powershell
.\lab\scripts\start.ps1
```

脚本通过 Docker Compose 启动 Mosquitto，本地 Broker 地址为 `127.0.0.1:1883`。首次启动前需要以交互方式创建本地 password file，具体步骤见 [`lab/README.md`](lab/README.md)。

### 运行 MQTT 客户端

```powershell
.\lab\scripts\run-client.ps1
```

客户端使用本地 `.env` 中的用户名和密码连接 Broker、订阅配置的主题、以 QoS 1 向同一主题发布消息，收到该消息后断开连接。

### 运行自动化测试

```powershell
.\lab\scripts\test.ps1
```

### 停止 Broker

```powershell
.\lab\scripts\stop.ps1
```

## MQTT 配置与校验

`.env.example` 配置模板如下：

```ini
MQTT_HOST=127.0.0.1
MQTT_PORT=1883
MQTT_TOPIC=test/topic
MQTT_MESSAGE=hello mqtt from python
MQTT_CLIENT_ID=mqtt-python-client
MQTT_USERNAME=mqtt-client
MQTT_PASSWORD=
```

上面的密码字段故意留空；运行客户端前需要在本地 `.env` 中填写真实密码。

配置项及当前校验规则：

- `MQTT_HOST`：Broker 地址，不能为空。
- `MQTT_PORT`：Broker 端口，必须为整数且在 `1`–`65535` 范围内。
- `MQTT_TOPIC`：订阅和发布使用的主题，不能为空。当前程序使用同一主题发布消息，因此不允许包含通配符 `+` 或 `#`。
- `MQTT_MESSAGE`：发布的消息内容，不能为空。
- `MQTT_CLIENT_ID`：客户端标识，不能为空。
- `MQTT_USERNAME`：连接 Broker 使用的用户名，不能为空或仅包含空白字符。
- `MQTT_PASSWORD`：连接 Broker 使用的密码，不能为空或仅包含空白字符；校验不会修改密码原值。

这些规则是当前客户端实现的基础配置校验，不代表完整的 MQTT 协议级校验。

## 退出码

- `0`：完整 MQTT 流程成功，包括收到预期 Topic 和 Message。
- `2`：本地静态配置校验失败。
- `3`：Broker 拒绝、MQTT 协议层失败或 MQTT 运行期错误。

## 自动化测试

当前自动化测试包括：

- `tests/test_config_validation.py`：配置校验、端口边界、用户名 / 密码必填以及原始配置不被修改。
- `tests/test_mqtt_runtime.py`：CONNECT、SUBACK、PUBACK、消息接收、断开连接和 runtime exit code 的纯单元测试。

测试不需要连接真实 Broker，也不运行 Docker integration tests。当前共 25 个测试。

当前已验证结果：

```text
25 passed
0 failed
0 warnings
```

推荐直接使用开发脚本：

```powershell
.\lab\scripts\test.ps1
```

也可以执行对应的 pytest 命令：

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests -p no:cacheprovider
```

## 本地实验环境

Mosquitto 配置、本地挂载目录和开发脚本的详细说明见 [`lab/README.md`](lab/README.md)。

## 安全边界

- Broker 主机端口仍仅绑定 `127.0.0.1:1883`，用于本机实验。
- 当前用户名 / 密码连接未启用 TLS，凭据传输不具备 TLS 加密保护。
- 当前配置不适合直接暴露到公网；不要把 listener 或 Compose 端口映射改为公共网络地址。
