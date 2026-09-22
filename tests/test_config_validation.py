import pytest

from src.mqtt_client import validate_config


BASE_CONFIG = {
    "MQTT_HOST": "127.0.0.1",
    "MQTT_PORT": "1883",
    "MQTT_TOPIC": "test/topic",
    "MQTT_MESSAGE": "hello mqtt from python",
    "MQTT_CLIENT_ID": "mqtt-python-client",
}


@pytest.mark.parametrize(
    "field, value, expected_message",
    [
        ("MQTT_HOST", "   ", "MQTT_HOST 不能为空"),
        ("MQTT_PORT", "abc", "MQTT_PORT 必须是整数"),
        ("MQTT_PORT", "0", "MQTT_PORT 必须在 1 到 65535 之间"),
        ("MQTT_PORT", "65536", "MQTT_PORT 必须在 1 到 65535 之间"),
        ("MQTT_TOPIC", "   ", "MQTT_TOPIC 不能为空"),
        ("MQTT_TOPIC", "test/+", "MQTT_TOPIC 不能包含通配符 + 或 #"),
        ("MQTT_TOPIC", "test/#", "MQTT_TOPIC 不能包含通配符 + 或 #"),
        ("MQTT_MESSAGE", "   ", "MQTT_MESSAGE 不能为空"),
        ("MQTT_CLIENT_ID", "   ", "MQTT_CLIENT_ID 不能为空"),
    ],
)
def test_validate_config_rejects_invalid_values(field, value, expected_message):
    config = BASE_CONFIG.copy()
    config[field] = value

    with pytest.raises(ValueError) as error:
        validate_config(config)

    assert str(error.value) == expected_message


@pytest.mark.parametrize("port, expected_port", [("1", 1), ("65535", 65535)])
def test_validate_config_accepts_port_boundaries(port, expected_port):
    config = BASE_CONFIG.copy()
    config["MQTT_PORT"] = port

    validated_config = validate_config(config)

    assert type(validated_config["MQTT_PORT"]) is int
    assert validated_config["MQTT_PORT"] == expected_port


def test_validate_config_returns_new_dict_without_changing_input():
    config = BASE_CONFIG.copy()
    original_config = config.copy()

    validated_config = validate_config(config)

    expected_config = original_config.copy()
    expected_config["MQTT_PORT"] = 1883
    assert isinstance(validated_config, dict)
    assert validated_config == expected_config
    assert type(validated_config["MQTT_PORT"]) is int
    assert validated_config is not config
    assert config == original_config
