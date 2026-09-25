import pytest

import src.mqtt_client as mqtt_client
from src.mqtt_client import validate_config


@pytest.fixture
def base_config(tmp_path):
    ca_file = tmp_path / "ca.crt"
    ca_file.touch()
    return {
        "MQTT_HOST": "127.0.0.1",
        "MQTT_PORT": "8883",
        "MQTT_CA_FILE": str(ca_file),
        "MQTT_TOPIC": "test/topic",
        "MQTT_MESSAGE": "hello mqtt from python",
        "MQTT_CLIENT_ID": "mqtt-python-client",
        "MQTT_USERNAME": "mqtt-client",
        "MQTT_PASSWORD": "test-password",
    }


@pytest.mark.parametrize(
    "field, value, expected_message",
    [
        ("MQTT_CA_FILE", "", "MQTT_CA_FILE cannot be empty"),
        ("MQTT_CA_FILE", "   ", "MQTT_CA_FILE cannot be empty"),
        ("MQTT_HOST", "   ", "MQTT_HOST 不能为空"),
        ("MQTT_PORT", "abc", "MQTT_PORT 必须是整数"),
        ("MQTT_PORT", "0", "MQTT_PORT 必须在 1 到 65535 之间"),
        ("MQTT_PORT", "65536", "MQTT_PORT 必须在 1 到 65535 之间"),
        ("MQTT_TOPIC", "   ", "MQTT_TOPIC 不能为空"),
        ("MQTT_TOPIC", "test/+", "MQTT_TOPIC 不能包含通配符 + 或 #"),
        ("MQTT_TOPIC", "test/#", "MQTT_TOPIC 不能包含通配符 + 或 #"),
        ("MQTT_MESSAGE", "   ", "MQTT_MESSAGE 不能为空"),
        ("MQTT_CLIENT_ID", "   ", "MQTT_CLIENT_ID 不能为空"),
        ("MQTT_USERNAME", "   ", "MQTT_USERNAME 不能为空"),
        ("MQTT_PASSWORD", "   ", "MQTT_PASSWORD 不能为空"),
    ],
)
def test_validate_config_rejects_invalid_values(
    field,
    value,
    expected_message,
    base_config,
):
    config = base_config.copy()
    config[field] = value

    with pytest.raises(ValueError) as error:
        validate_config(config)

    assert str(error.value) == expected_message


@pytest.mark.parametrize("port, expected_port", [("1", 1), ("65535", 65535)])
def test_validate_config_accepts_port_boundaries(
    port,
    expected_port,
    base_config,
):
    config = base_config.copy()
    config["MQTT_PORT"] = port

    validated_config = validate_config(config)

    assert type(validated_config["MQTT_PORT"]) is int
    assert validated_config["MQTT_PORT"] == expected_port


def test_validate_config_rejects_missing_ca_file(base_config, tmp_path):
    config = base_config.copy()
    config["MQTT_CA_FILE"] = str(tmp_path / "missing-ca.crt")

    with pytest.raises(ValueError) as error:
        validate_config(config)

    assert str(error.value) == "MQTT_CA_FILE does not exist"


def test_validate_config_rejects_ca_directory(base_config, tmp_path):
    config = base_config.copy()
    config["MQTT_CA_FILE"] = str(tmp_path)

    with pytest.raises(ValueError) as error:
        validate_config(config)

    assert str(error.value) == "MQTT_CA_FILE must point to a regular file"


def test_validate_config_accepts_ca_file(base_config):
    validated_config = validate_config(base_config)

    assert validated_config["MQTT_CA_FILE"] == base_config["MQTT_CA_FILE"]


def test_validate_config_resolves_relative_ca_file_from_project_root(
    base_config,
    tmp_path,
    monkeypatch,
):
    certificate_directory = tmp_path / "certificates"
    certificate_directory.mkdir()
    ca_file = certificate_directory / "ca.crt"
    ca_file.touch()
    monkeypatch.setattr(mqtt_client, "PROJECT_ROOT", tmp_path)

    config = base_config.copy()
    config["MQTT_CA_FILE"] = "certificates/ca.crt"
    original_config = config.copy()

    validated_config = validate_config(config)

    assert validated_config["MQTT_CA_FILE"] == str(ca_file.resolve())
    assert config == original_config


def test_validate_config_returns_new_dict_without_changing_input(base_config):
    config = base_config.copy()
    original_config = config.copy()

    validated_config = validate_config(config)

    expected_config = original_config.copy()
    expected_config["MQTT_PORT"] = 8883
    assert isinstance(validated_config, dict)
    assert validated_config == expected_config
    assert type(validated_config["MQTT_PORT"]) is int
    assert validated_config["MQTT_PASSWORD"] == original_config["MQTT_PASSWORD"]
    assert validated_config is not config
    assert config == original_config
