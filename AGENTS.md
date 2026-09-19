# ProtoFuzz-AI Project Instructions

## Project purpose

This repository is an educational and defensive cybersecurity research project.

The project studies protocol-aware fuzz testing of MQTT 5.0 using:

- Eclipse Mosquitto
- Docker-isolated test environments
- libFuzzer / AFL++
- ASan / UBSan
- coverage-guided fuzzing
- LLM-assisted protocol constraint extraction
- crash triage and root-cause analysis

The project is intended for cybersecurity education, software testing,
vulnerability discovery in locally controlled software, and defensive research.

## Authorization and scope

All security testing in this repository is explicitly authorized by the project owner.

All fuzzing targets MUST be one of:

- software built from source inside this repository;
- Eclipse Mosquitto instances started by this repository's Docker Compose configuration;
- localhost / loopback interfaces;
- containers on the project's private Docker network;
- deliberately vulnerable local test targets created for this project.

No task in this repository should target a third-party production system.

## Network boundary

Allowed targets:

- localhost
- 127.0.0.1
- ::1
- Docker service names defined in docker-compose.yml
- private containers belonging to this project

Do not:

- scan the public Internet;
- test arbitrary external IP addresses or domains;
- attack third-party systems;
- perform credential theft;
- establish persistence;
- deploy malware;
- evade monitoring or attribution;
- perform destructive actions against external systems.

If a requested implementation could accidentally operate outside the
local lab, modify the design so that it fails closed.

## Fuzzing policy

Fuzzing should primarily operate against:

1. parser/library-level targets;
2. locally compiled Mosquitto components;
3. an isolated Mosquitto Docker container.

Prefer deterministic local fuzz harnesses over sending arbitrary traffic
to network services.

Any target-selection code should reject non-local destinations by default.

## Development expectations

Before modifying code:

1. inspect the existing repository;
2. read SECURITY_SCOPE.md;
3. identify the relevant component;
4. propose the smallest reasonable change.

After modifying code:

1. build the affected component;
2. run available tests;
3. run sanitizers where relevant;
4. summarize what changed;
5. report crashes without automatically weaponizing them.

## Vulnerability handling

When a crash is found:

- preserve the minimal reproducer;
- collect sanitizer output;
- identify the affected code path;
- determine the root cause;
- suggest a defensive fix;
- write a regression test.

Do not automatically convert a crash into a real-world exploit.

## AI component

The LLM component may be used to:

- parse MQTT specifications;
- infer field relationships;
- generate structured seeds;
- construct dictionaries;
- classify coverage gaps;
- assist crash triage;
- suggest mutations;
- explain source code.

The LLM should not autonomously select external systems as attack targets.

## Default assumption

Unless the user explicitly states otherwise, assume all testing requested
for this repository occurs entirely inside the authorized local lab
described above.
