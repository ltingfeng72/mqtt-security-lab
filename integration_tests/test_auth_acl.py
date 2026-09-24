import os
import threading
import uuid

import paho.mqtt.client as mqtt
import pytest


TIMEOUT_SECONDS = 5
ALLOWED_TOPIC = "test/topic"
DENIED_TOPIC = "test/denied"
EXPECTED_USERNAME = "integration-client"


@pytest.fixture(scope="session")
def integration_config():
    environment_names = (
        "MQTT_INTEGRATION_HOST",
        "MQTT_INTEGRATION_PORT",
        "MQTT_INTEGRATION_USERNAME",
        "MQTT_INTEGRATION_PASSWORD",
    )
    values = {name: os.getenv(name) for name in environment_names}
    missing = [name for name, value in values.items() if not value]
    if missing:
        pytest.fail(
            "Missing required integration environment variables: "
            + ", ".join(missing),
            pytrace=False,
        )

    try:
        port = int(values["MQTT_INTEGRATION_PORT"])
    except ValueError:
        pytest.fail(
            "MQTT_INTEGRATION_PORT must be an integer",
            pytrace=False,
        )

    if not 1 <= port <= 65535:
        pytest.fail(
            "MQTT_INTEGRATION_PORT must be between 1 and 65535",
            pytrace=False,
        )

    username = values["MQTT_INTEGRATION_USERNAME"]
    if username != EXPECTED_USERNAME:
        pytest.fail(
            f"MQTT_INTEGRATION_USERNAME must be {EXPECTED_USERNAME}",
            pytrace=False,
        )

    return {
        "host": values["MQTT_INTEGRATION_HOST"],
        "port": port,
        "username": username,
        "password": values["MQTT_INTEGRATION_PASSWORD"],
    }


def _new_client(username, password):
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"mqtt-integration-{uuid.uuid4().hex}",
        protocol=mqtt.MQTTv5,
    )
    client.username_pw_set(username, password)
    return client


def _wait(event, stage):
    assert event.wait(TIMEOUT_SECONDS), (
        f"Timed out after {TIMEOUT_SECONDS} seconds waiting for {stage}"
    )


def _install_round_trip_callbacks(client, topic, payload, state, events):
    def on_connect(active_client, userdata, flags, reason_code, properties):
        state["connect_reason"] = reason_code
        if not reason_code.is_failure:
            result, _ = active_client.subscribe(topic, qos=1)
            state["subscribe_request_result"] = result
        events["connect"].set()

    def on_subscribe(
        active_client,
        userdata,
        mid,
        reason_code_list,
        properties,
    ):
        state["subscribe_reasons"] = reason_code_list
        if not any(reason_code.is_failure for reason_code in reason_code_list):
            message_info = active_client.publish(topic, payload, qos=1)
            state["publish_request_result"] = message_info.rc
        events["subscribe"].set()

    def on_publish(
        active_client,
        userdata,
        mid,
        reason_code,
        properties,
    ):
        state["publish_reason"] = reason_code
        events["publish"].set()

    def on_message(active_client, userdata, message):
        state["message_topic"] = message.topic
        state["message_payload"] = message.payload
        events["message"].set()

    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_publish = on_publish
    client.on_message = on_message


def _new_round_trip_state():
    return {}, {
        "connect": threading.Event(),
        "subscribe": threading.Event(),
        "publish": threading.Event(),
        "message": threading.Event(),
    }


def _assert_successful_round_trip(state, events, topic, payload):
    _wait(events["connect"], "successful CONNACK")
    assert not state["connect_reason"].is_failure, (
        f"CONNECT failed: {state['connect_reason']}"
    )
    assert state["subscribe_request_result"] == mqtt.MQTT_ERR_SUCCESS, (
        "SUBSCRIBE request failed locally"
    )

    _wait(events["subscribe"], f"successful SUBACK for {topic}")
    subscribe_reasons = state["subscribe_reasons"]
    assert subscribe_reasons, f"SUBACK for {topic} contained no reason code"
    assert not any(reason_code.is_failure for reason_code in subscribe_reasons), (
        f"SUBACK failed for {topic}: {subscribe_reasons}"
    )
    assert state["publish_request_result"] == mqtt.MQTT_ERR_SUCCESS, (
        f"PUBLISH request failed locally for {topic}"
    )

    _wait(events["publish"], f"successful PUBACK for {topic}")
    assert not state["publish_reason"].is_failure, (
        f"PUBACK failed for {topic}: {state['publish_reason']}"
    )

    _wait(events["message"], f"loopback message on {topic}")
    assert state["message_topic"] == topic
    assert state["message_payload"] == payload.encode("utf-8")


def test_valid_credentials_complete_mqtt_flow(integration_config):
    payload = uuid.uuid4().hex
    state, events = _new_round_trip_state()
    client = _new_client(
        integration_config["username"],
        integration_config["password"],
    )
    _install_round_trip_callbacks(
        client,
        ALLOWED_TOPIC,
        payload,
        state,
        events,
    )

    try:
        result = client.connect(
            integration_config["host"],
            integration_config["port"],
        )
        assert result == mqtt.MQTT_ERR_SUCCESS, "CONNECT request failed locally"
        client.loop_start()
        _assert_successful_round_trip(
            state,
            events,
            ALLOWED_TOPIC,
            payload,
        )
    finally:
        client.loop_stop()
        client.disconnect()


def test_wrong_password_is_rejected(integration_config):
    wrong_password = uuid.uuid4().hex
    while wrong_password == integration_config["password"]:
        wrong_password = uuid.uuid4().hex

    connack_received = threading.Event()
    state = {}
    client = _new_client(integration_config["username"], wrong_password)

    def on_connect(active_client, userdata, flags, reason_code, properties):
        state["connect_reason"] = reason_code
        connack_received.set()

    client.on_connect = on_connect

    try:
        result = client.connect(
            integration_config["host"],
            integration_config["port"],
        )
        assert result == mqtt.MQTT_ERR_SUCCESS, "CONNECT request failed locally"
        client.loop_start()
        _wait(connack_received, "rejected CONNACK")

        reason_code = state["connect_reason"]
        assert reason_code.is_failure is True
        assert str(reason_code) == "Not authorized", (
            f"Unexpected rejected CONNACK reason: {reason_code}"
        )
    finally:
        client.loop_stop()
        client.disconnect()


def test_acl_allows_read_write_on_test_topic(integration_config):
    payload = uuid.uuid4().hex
    state, events = _new_round_trip_state()
    client = _new_client(
        integration_config["username"],
        integration_config["password"],
    )
    _install_round_trip_callbacks(
        client,
        ALLOWED_TOPIC,
        payload,
        state,
        events,
    )

    try:
        result = client.connect(
            integration_config["host"],
            integration_config["port"],
        )
        assert result == mqtt.MQTT_ERR_SUCCESS, "CONNECT request failed locally"
        client.loop_start()
        _assert_successful_round_trip(
            state,
            events,
            ALLOWED_TOPIC,
            payload,
        )
    finally:
        client.loop_stop()
        client.disconnect()


def test_acl_denies_publish_to_denied_topic(integration_config):
    connect_received = threading.Event()
    puback_received = threading.Event()
    state = {}
    client = _new_client(
        integration_config["username"],
        integration_config["password"],
    )

    def on_connect(active_client, userdata, flags, reason_code, properties):
        state["connect_reason"] = reason_code
        if not reason_code.is_failure:
            message_info = active_client.publish(
                DENIED_TOPIC,
                uuid.uuid4().hex,
                qos=1,
            )
            state["publish_request_result"] = message_info.rc
        connect_received.set()

    def on_publish(
        active_client,
        userdata,
        mid,
        reason_code,
        properties,
    ):
        state["publish_reason"] = reason_code
        puback_received.set()

    client.on_connect = on_connect
    client.on_publish = on_publish

    try:
        result = client.connect(
            integration_config["host"],
            integration_config["port"],
        )
        assert result == mqtt.MQTT_ERR_SUCCESS, "CONNECT request failed locally"
        client.loop_start()

        _wait(connect_received, "successful CONNACK before ACL deny check")
        assert not state["connect_reason"].is_failure, (
            f"CONNECT failed: {state['connect_reason']}"
        )
        assert state["publish_request_result"] == mqtt.MQTT_ERR_SUCCESS, (
            f"PUBLISH request failed locally for {DENIED_TOPIC}"
        )

        _wait(puback_received, f"denied PUBACK for {DENIED_TOPIC}")
        reason_code = state["publish_reason"]
        assert reason_code.is_failure is True
        assert str(reason_code) == "Not authorized", (
            f"Unexpected PUBACK reason for {DENIED_TOPIC}: {reason_code}"
        )
    finally:
        client.loop_stop()
        client.disconnect()
