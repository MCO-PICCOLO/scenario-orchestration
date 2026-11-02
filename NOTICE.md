## Notice for the Eclipse SDV Blueprint: scenario-orchestration

This content is produced and maintained by the Eclipse SDV Blueprints project.

* Project home: https://github.com/eclipse-sdv-blueprints/scenario-orchestration

## Trademarks

Eclipse and the Eclipse logo are registered trademarks of the Eclipse Foundation.
All other trademarks are the property of their respective owners.

## Copyright

All content is the property of the respective authors or their employers.
For more information regarding authorship of content, please consult the
listed source code repository logs.

## Declared Project Licenses

This program and the accompanying materials are made available under the
terms of the Apache License Version 2.0 which is available at
https://www.apache.org/licenses/LICENSE-2.0.

SPDX-License-Identifier: Apache-2.0

## Source Code

The project maintains the following source code repository:

* https://github.com/eclipse-sdv-blueprints/scenario-orchestration

## Third-party Content

This blueprint builds on, and interoperates with, the following third-party
components. Each is subject to its own license.

### Eclipse SDV projects (Apache-2.0)

* Eclipse Pullpiri (https://projects.eclipse.org/projects/automotive.pullpiri) -
  container/workload orchestration
* Eclipse Timpani (https://projects.eclipse.org/projects/automotive.timpani) -
  time-triggered scheduling
* Eclipse Kuksa (https://projects.eclipse.org/projects/automotive.kuksa) -
  Kuksa Databroker 0.6.0 (`quay.io/eclipse-kuksa/kuksa-databroker`) and
  `kuksa-client` 0.6.0

### Prebuilt binaries included in this repository

Located in `resource-isolation/artifacts`. These are prebuilt Timpani
artifacts, included for convenience of reproducing the demo.

| File | Description | SHA-256 |
|------|-------------|---------|
| `timpani-n-2.0.0-Linux.deb` | Timpani-N node executor package (Debian/Ubuntu) | `2bd242a8b48ceebc9cd80799423d6b47d4c5767d8096e70dc56e1b81d4daee6a` |
| `timpani-n-2.0.0-Linux.rpm` | Timpani-N node executor package (RHEL/CentOS/Fedora) | `1a799c5cf1965d5e6f95efb7cf28befe00ba47be377eac418d99be68b8bb86b1` |
| `timpani-o-0.1.0.tar` | Timpani-O orchestrator container image archive | `e556e72594f32942928c74d9222d09149a935b07bcad40e7245633e13f1020e0` |

### Container images (pulled at runtime, not redistributed)

* `grafana/grafana` and `prom/prometheus` - monitoring
* `python:3.11-slim`, `debian:bookworm-slim`, `gcc:12` - base images
* `ghcr.io/mco-piccolo/timpani-o` - Timpani-O image (used by the install script)

### Python dependencies (installed via pip in the Dockerfiles)

`pyserial`, `kuksa-client`, `python-dotenv`, `requests` and their transitive
dependencies. See the [DEPENDENCIES](./DEPENDENCIES) file, generated with the
[Eclipse Dash License Tool](https://github.com/eclipse/dash-licenses). The
following items are still marked `restricted` and require IP review by the EMO
(requested together with the initial contribution pull request):

* websockets 17.3
* grpcio 1.84.1
* jsonpath-ng 1.13.0
* cmd2 4.3.1
* kuksa-client 0.6.0

### Tools used by the demo scripts

* stress-ng - CPU load generation

## Cryptography

Content may contain encryption software. The country in which you are currently
may have restrictions on the import, possession, and use, and/or re-export to
another country, of encryption software. BEFORE using any encryption software,
please check the country's laws, regulations and policies concerning the import,
possession, or use, and re-export of encryption software, to see if this is
permitted.
