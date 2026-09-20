import logging
import os

import paho.mqtt.client as mqtt
from dotenv import load_dotenv


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger(__name__)


def read_config():
    """从环境变量读取 MQTT 配置。"""
    load_dotenv()
    return {
        "MQTT_HOST": os.getenv("MQTT_HOST", "127.0.0.1"),
        "MQTT_PORT": os.getenv("MQTT_PORT", "1883"),
        "MQTT_TOPIC": os.getenv("MQTT_TOPIC", "test/topic"),
        "MQTT_MESSAGE": os.getenv("MQTT_MESSAGE", "hello mqtt from python"),
        "MQTT_CLIENT_ID": os.getenv("MQTT_CLIENT_ID", "mqtt-python-client"),
    }


def validate_config(config):
    """校验 MQTT 配置并返回端口已转换为整数的新字典。"""
    if not config["MQTT_HOST"].strip():
        raise ValueError("MQTT_HOST 不能为空")

    try:
        port = int(config["MQTT_PORT"])
    except (TypeError, ValueError):
        raise ValueError("MQTT_PORT 必须是整数") from None

    if not 1 <= port <= 65535:
        raise ValueError("MQTT_PORT 必须在 1 到 65535 之间")

    topic = config["MQTT_TOPIC"]
    if not topic.strip():
        raise ValueError("MQTT_TOPIC 不能为空")
    if "+" in topic or "#" in topic:
        raise ValueError("MQTT_TOPIC 不能包含通配符 + 或 #")

    if not config["MQTT_MESSAGE"].strip():
        raise ValueError("MQTT_MESSAGE 不能为空")

    if not config["MQTT_CLIENT_ID"].strip():
        raise ValueError("MQTT_CLIENT_ID 不能为空")

    validated_config = config.copy()
    validated_config["MQTT_PORT"] = port
    return validated_config


def on_connect(client, userdata, flags, reason_code, properties):
    """连接成功后订阅测试主题。"""
    if reason_code.is_failure:
        logger.error("连接 MQTT Broker 失败：%s", reason_code)
        client.disconnect()
        return

    logger.info("连接 MQTT Broker 成功")
    result, _ = client.subscribe(userdata["MQTT_TOPIC"])
    if result != mqtt.MQTT_ERR_SUCCESS:
        logger.error("订阅失败，错误码：%s", result)
        client.disconnect()


def on_subscribe(client, userdata, mid, reason_code_list, properties):
    """订阅确认后发布测试消息。"""
    if any(reason_code.is_failure for reason_code in reason_code_list):
        logger.error("订阅失败：%s", reason_code_list)
        client.disconnect()
        return

    topic = userdata["MQTT_TOPIC"]
    message = userdata["MQTT_MESSAGE"]
    logger.info("订阅成功：%s", topic)

    # 订阅成功后，向同一主题发布测试消息。
    message_info = client.publish(topic, message)
    if message_info.rc == mqtt.MQTT_ERR_SUCCESS:
        logger.info("消息发布：%s", message)
    else:
        logger.error("消息发布失败，错误码：%s", message_info.rc)
        client.disconnect()


def on_message(client, userdata, message):
    """打印收到的消息，并在收到测试消息后断开连接。"""
    payload = message.payload.decode("utf-8")
    logger.info("收到消息：%s", payload)
    print(f"Received: {payload}")

    if (
        message.topic == userdata["MQTT_TOPIC"]
        and payload == userdata["MQTT_MESSAGE"]
    ):
        client.disconnect()


def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
    """记录客户端断开连接的状态。"""
    if reason_code == 0:
        logger.info("已正常断开 MQTT Broker 连接")
    else:
        logger.warning("MQTT 连接意外断开：%s", reason_code)


def main():
    """连接本机 Mosquitto，并运行客户端直到收到测试消息。"""
    try:
        config = validate_config(read_config())
    except ValueError as error:
        logger.error("配置错误：%s", error)
        return 2

    # 使用 MQTT 5.0 和 paho-mqtt 2.x 的回调接口。
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=config["MQTT_CLIENT_ID"],
        userdata=config,
        protocol=mqtt.MQTTv5,
    )
    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    try:
        logger.info(
            "正在连接 MQTT Broker：%s:%s",
            config["MQTT_HOST"],
            config["MQTT_PORT"],
        )
        client.connect(config["MQTT_HOST"], config["MQTT_PORT"])
        client.loop_forever()
    except (OSError, mqtt.MQTTException) as error:
        logger.error("连接或通信失败：%s", error)
    except Exception:
        logger.exception("程序运行过程中出现异常")
    finally:
        if client.is_connected():
            client.disconnect()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
