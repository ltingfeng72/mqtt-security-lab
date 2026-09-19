# Security Research Scope

## Owner

This lab is controlled by the repository owner.

## Purpose

Cybersecurity education and defensive software testing.

## Primary target

Eclipse Mosquitto MQTT broker.

## Protocol

MQTT 5.0.

## Execution environment

Local Docker containers.

## Authorized addresses

127.0.0.1
::1
localhost

Docker-internal service names defined by this repository are also allowed.

## Explicitly out of scope

Public IP addresses
Public websites
Cloud production services
University production networks
Corporate networks
Third-party MQTT brokers
Devices not owned or explicitly authorized by the researcher

## Testing techniques

Allowed within the local laboratory:

- fuzz testing
- coverage-guided fuzzing
- malformed protocol messages
- parser testing
- sanitizer instrumentation
- crash reproduction
- source-code debugging
- static analysis
- dynamic analysis
- protocol state-machine testing

## Crash handling

A discovered crash should be treated as a software-quality and
defensive-security finding.

Preferred workflow:

crash
→ reproduce
→ minimize
→ ASan/UBSan analysis
→ source-code root cause
→ patch
→ regression test

Do not automatically escalate a crash into an external attack.
