# ProtoFuzz-AI

ProtoFuzz-AI 是一个用于学习和研究 MQTT 5.0 协议及相关软件开发流程的本地项目。当前项目提供基于 Docker Compose 和 Eclipse Mosquitto 的本地 Broker，以及用于演示 MQTT 连接、订阅、发布、接收和断开的 Python 客户端。

## 当前已实现功能

- 使用 Docker Compose 启动 Eclipse Mosquitto
- 在 `127.0.0.1:1883` 提供仅限本机访问的 MQTT Broker
- 使用 Paho MQTT 5.0 和 Callback API v2 的 Python 客户端
- 完整演示 MQTT 连接、订阅、发布、接收和断开流程
- 日志记录与基础异常处理
- 使用 `.env` 管理 MQTT 配置
- MQTT 配置校验
- 使用 pytest 编写的配置校验自动化测试
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
│   └── test_config_validation.py
└── lab/
    ├── README.md
    ├── config/
    │   └── mosquitto.conf
    ├── data/
    ├── logs/
    └── scripts/
        ├── start.ps1
        ├── stop.ps1
        ├── run-client.ps1
        └── test.ps1
```

`.venv` 和真实 `.env` 均为本地文件，不纳入 Git 跟踪；`lab/data/` 和 `lab/logs/` 是 Broker 运行时目录。

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

## 快速开始

### 启动 Broker

确保 Docker Desktop 正在运行，然后执行：

```powershell
.\lab\scripts\start.ps1
```

脚本通过 Docker Compose 启动 Mosquitto，本地 Broker 地址为 `127.0.0.1:1883`。

### 运行 MQTT 客户端

```powershell
.\lab\scripts\run-client.ps1
```

客户端连接 Broker、订阅配置的主题、向同一主题发布消息，收到该消息后断开连接。

### 运行自动化测试

```powershell
.\lab\scripts\test.ps1
```

### 停止 Broker

```powershell
.\lab\scripts\stop.ps1
```

## MQTT 配置与校验

默认配置如下：

```ini
MQTT_HOST=127.0.0.1
MQTT_PORT=1883
MQTT_TOPIC=test/topic
MQTT_MESSAGE=hello mqtt from python
MQTT_CLIENT_ID=mqtt-python-client
```

配置项及当前校验规则：

- `MQTT_HOST`：Broker 地址，不能为空。
- `MQTT_PORT`：Broker 端口，必须为整数且在 `1`–`65535` 范围内。
- `MQTT_TOPIC`：订阅和发布使用的主题，不能为空。当前程序使用同一主题发布消息，因此不允许包含通配符 `+` 或 `#`。
- `MQTT_MESSAGE`：发布的消息内容，不能为空。
- `MQTT_CLIENT_ID`：客户端标识，不能为空。

这些规则是当前客户端实现的基础配置校验，不代表完整的 MQTT 协议级校验。

## 退出码

- `0`：正常流程完成。
- `2`：MQTT 配置校验失败。

## 自动化测试

配置校验测试位于 `tests/test_config_validation.py`，当前包含 12 个测试用例，覆盖无效配置、端口边界以及校验结果不会修改原始配置等行为。

当前已验证结果：

```text
12 passed
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
