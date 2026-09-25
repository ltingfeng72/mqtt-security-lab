import ssl

import src.mqtt_client as mqtt_client
from src.mqtt_client import (
    on_connect,
    on_disconnect,
    on_message,
    on_publish,
    on_subscribe,
)


class FakeReasonCode:
    def __init__(self, is_failure, label):
        self.is_failure = is_failure
        self.label = label

    def __str__(self):
        return self.label

    def __repr__(self):
        return self.label


class FakePublishResult:
    def __init__(self, rc):
        self.rc = rc


class FakeClient:
    def __init__(self, subscribe_rc=0, publish_rc=0):
        self.subscribe_rc = subscribe_rc
        self.publish_rc = publish_rc
        self.disconnect_called = False
        self.subscribe_called = False
        self.publish_called = False
        self.subscribe_topic = None
        self.publish_arguments = None

    def disconnect(self):
        self.disconnect_called = True

    def subscribe(self, topic):
        self.subscribe_called = True
        self.subscribe_topic = topic
        return self.subscribe_rc, 1

    def publish(self, topic, message, qos):
        self.publish_called = True
        self.publish_arguments = (topic, message, qos)
        return FakePublishResult(self.publish_rc)


class FakeMessage:
    def __init__(self, topic, payload):
        self.topic = topic
        self.payload = payload.encode("utf-8")


def make_runtime_state(exit_code=3):
    return {
        "MQTT_TOPIC": "test/topic",
        "MQTT_MESSAGE": "test message",
        "exit_code": exit_code,
    }


def test_on_connect_failure_sets_exit_code_and_disconnects_without_subscribe():
    client = FakeClient()
    runtime_state = make_runtime_state(exit_code=0)

    on_connect(
        client,
        runtime_state,
        None,
        FakeReasonCode(True, "Not authorized"),
        None,
    )

    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is True
    assert client.subscribe_called is False


def test_on_connect_subscribe_call_failure_sets_exit_code_and_disconnects():
    client = FakeClient(subscribe_rc=1)
    runtime_state = make_runtime_state(exit_code=0)

    on_connect(client, runtime_state, None, FakeReasonCode(False, "Success"), None)

    assert runtime_state["exit_code"] == 3
    assert client.subscribe_called is True
    assert client.disconnect_called is True


def test_on_subscribe_failure_sets_exit_code_and_disconnects_without_publish():
    client = FakeClient()
    runtime_state = make_runtime_state(exit_code=0)
    reason_codes = [
        FakeReasonCode(False, "Granted QoS 0"),
        FakeReasonCode(True, "Not authorized"),
    ]

    on_subscribe(client, runtime_state, 1, reason_codes, None)

    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is True
    assert client.publish_called is False


def test_on_subscribe_success_publishes_with_qos_one_without_marking_success():
    client = FakeClient()
    runtime_state = make_runtime_state()

    on_subscribe(
        client,
        runtime_state,
        1,
        [FakeReasonCode(False, "Granted QoS 1")],
        None,
    )

    assert client.publish_called is True
    assert client.publish_arguments == ("test/topic", "test message", 1)
    assert client.disconnect_called is False
    assert runtime_state["exit_code"] == 3


def test_on_subscribe_publish_call_failure_sets_exit_code_and_disconnects():
    client = FakeClient(publish_rc=1)
    runtime_state = make_runtime_state(exit_code=0)

    on_subscribe(
        client,
        runtime_state,
        1,
        [FakeReasonCode(False, "Granted QoS 1")],
        None,
    )

    assert client.publish_called is True
    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is True


def test_on_publish_failure_sets_exit_code_and_disconnects():
    client = FakeClient()
    runtime_state = make_runtime_state(exit_code=0)

    on_publish(
        client,
        runtime_state,
        1,
        FakeReasonCode(True, "Not authorized"),
        None,
    )

    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is True


def test_on_publish_success_does_not_mark_complete():
    client = FakeClient()
    runtime_state = make_runtime_state()

    on_publish(
        client,
        runtime_state,
        1,
        FakeReasonCode(False, "Success"),
        None,
    )

    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is False


def test_on_message_expected_sets_success_and_disconnects():
    client = FakeClient()
    runtime_state = make_runtime_state()
    message = FakeMessage("test/topic", "test message")

    on_message(client, runtime_state, message)

    assert runtime_state["exit_code"] == 0
    assert client.disconnect_called is True


def test_on_message_unexpected_topic_does_not_mark_success():
    client = FakeClient()
    runtime_state = make_runtime_state()
    message = FakeMessage("test/unexpected", "test message")

    on_message(client, runtime_state, message)

    assert runtime_state["exit_code"] == 3
    assert client.disconnect_called is False


def test_on_disconnect_failure_keeps_runtime_failure():
    client = FakeClient()
    runtime_state = make_runtime_state()

    on_disconnect(
        client,
        runtime_state,
        None,
        FakeReasonCode(True, "Unspecified error"),
        None,
    )

    assert runtime_state["exit_code"] == 3


def test_on_disconnect_success_does_not_overwrite_completed_success():
    client = FakeClient()
    runtime_state = make_runtime_state(exit_code=0)

    on_disconnect(client, runtime_state, None, 0, None)

    assert runtime_state["exit_code"] == 0


def test_main_returns_runtime_failure_for_tls_socket_error(monkeypatch):
    class FakeRuntimeClient:
        def __init__(self):
            self.loop_forever_called = False

        def username_pw_set(self, username, password):
            pass

        def tls_set(self, ca_certs):
            pass

        def connect(self, host, port):
            raise ssl.SSLEOFError("simulated TLS EOF")

        def loop_forever(self):
            self.loop_forever_called = True

        def is_connected(self):
            return False

        def disconnect(self):
            pass

    config = {
        "MQTT_HOST": "127.0.0.1",
        "MQTT_PORT": 8883,
        "MQTT_CA_FILE": "unused-ca.crt",
        "MQTT_TOPIC": "test/topic",
        "MQTT_MESSAGE": "test message",
        "MQTT_CLIENT_ID": "mqtt-runtime-test",
        "MQTT_USERNAME": "test-user",
        "MQTT_PASSWORD": "test-password",
    }
    client = FakeRuntimeClient()
    monkeypatch.setattr(mqtt_client, "read_config", lambda: {})
    monkeypatch.setattr(mqtt_client, "validate_config", lambda raw: config)
    monkeypatch.setattr(
        mqtt_client.mqtt,
        "Client",
        lambda *args, **kwargs: client,
    )

    assert mqtt_client.main() == 3
    assert client.loop_forever_called is False
