import logging
import os

import paho.mqtt.client as mqtt
from dotenv import load_dotenv


load_dotenv()

HOST = os.getenv("MQTT_HOST", "127.0.0.1")
PORT = int(os.getenv("MQTT_PORT", "1883"))
TOPIC = os.getenv("MQTT_TOPIC", "test/topic")
MESSAGE = os.getenv("MQTT_MESSAGE", "hello mqtt from python")
CLIENT_ID = os.getenv("MQTT_CLIENT_ID", "mqtt-python-client")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger(__name__)


def on_connect(client, userdata, flags, reason_code, properties):
    """连接成功后订阅测试主题。"""
    if reason_code.is_failure:
        logger.error("连接 MQTT Broker 失败：%s", reason_code)
        client.disconnect()
        return

    logger.info("连接 MQTT Broker 成功")
    result, _ = client.subscribe(TOPIC)
    if result != mqtt.MQTT_ERR_SUCCESS:
        logger.error("订阅失败，错误码：%s", result)
        client.disconnect()


def on_subscribe(client, userdata, mid, reason_code_list, properties):
    """订阅确认后发布测试消息。"""
    if any(reason_code.is_failure for reason_code in reason_code_list):
        logger.error("订阅失败：%s", reason_code_list)
        client.disconnect()
        return

    logger.info("订阅成功：%s", TOPIC)

    # 订阅成功后，向同一主题发布测试消息。
    message_info = client.publish(TOPIC, MESSAGE)
    if message_info.rc == mqtt.MQTT_ERR_SUCCESS:
        logger.info("消息发布：%s", MESSAGE)
    else:
        logger.error("消息发布失败，错误码：%s", message_info.rc)
        client.disconnect()


def on_message(client, userdata, message):
    """打印收到的消息，并在收到测试消息后断开连接。"""
    payload = message.payload.decode("utf-8")
    logger.info("收到消息：%s", payload)
    print(f"Received: {payload}")

    if message.topic == TOPIC and payload == MESSAGE:
        client.disconnect()


def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
    """记录客户端断开连接的状态。"""
    if reason_code == 0:
        logger.info("已正常断开 MQTT Broker 连接")
    else:
        logger.warning("MQTT 连接意外断开：%s", reason_code)


def main():
    """连接本机 Mosquitto，并运行客户端直到收到测试消息。"""
    # 使用 MQTT 5.0 和 paho-mqtt 2.x 的回调接口。
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=CLIENT_ID,
        protocol=mqtt.MQTTv5,
    )
    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    try:
        logger.info("正在连接 MQTT Broker：%s:%s", HOST, PORT)
        client.connect(HOST, PORT)
        client.loop_forever()
    except (OSError, mqtt.MQTTException) as error:
        logger.error("连接或通信失败：%s", error)
    except Exception:
        logger.exception("程序运行过程中出现异常")
    finally:
        if client.is_connected():
            client.disconnect()


if __name__ == "__main__":
    main()
