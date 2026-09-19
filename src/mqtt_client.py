import paho.mqtt.client as mqtt


HOST = "127.0.0.1"
PORT = 1883
TOPIC = "test/topic"
MESSAGE = "hello mqtt from python"


def on_connect(client, userdata, flags, reason_code, properties):
    """连接成功后订阅主题并发布测试消息。"""
    if reason_code == 0:
        # 先订阅，再向同一主题发布消息。
        client.subscribe(TOPIC)
        client.publish(TOPIC, MESSAGE)
    else:
        print(f"Connection failed: {reason_code}")
        client.disconnect()


def on_message(client, userdata, message):
    """打印收到的消息，并在收到测试消息后断开连接。"""
    payload = message.payload.decode("utf-8")
    print(f"Received: {payload}")

    if message.topic == TOPIC and payload == MESSAGE:
        client.disconnect()


# 使用 MQTT 5.0 和 paho-mqtt 2.x 的回调接口。
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, protocol=mqtt.MQTTv5)
client.on_connect = on_connect
client.on_message = on_message

# 连接本机 Mosquitto，并持续处理网络事件直到主动断开。
client.connect(HOST, PORT)
client.loop_forever()
