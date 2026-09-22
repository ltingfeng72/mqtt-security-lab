# 本地 MQTT 实验环境

## 环境概览

`lab/` 保存本地 MQTT 实验环境使用的 Mosquitto 配置、运行数据、日志和 PowerShell 开发脚本。项目根目录的 `compose.yaml` 使用 Eclipse Mosquitto 2，并将 Broker 限制在本机回环地址。

## 目录结构

```text
lab/
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

- `config/`：保存 Mosquitto 配置。
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

`mosquitto.conf` 为本地实验启用匿名连接和数据持久化，并将日志写入 `/mosquitto/log/mosquitto.log`。

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
- 当前 Broker 只服务本机实验环境。
- `.env`、Python 虚拟环境和依赖安装等完整步骤见项目根目录的 [`README.md`](../README.md)。
