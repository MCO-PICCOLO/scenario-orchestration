# /********************************************************************************
# * Copyright (c) 2026 Contributors to the Eclipse Foundation
# *
# * See the NOTICE file(s) distributed with this work for additional
# * information regarding copyright ownership.
# *
# * This program and the accompanying materials are made available under the
# * terms of the Apache License 2.0 which is available at
# * https://www.apache.org/licenses/LICENSE-2.0
# *
# * SPDX-License-Identifier: Apache-2.0
# ********************************************************************************/

FROM python:3.11-slim

WORKDIR /app

# Copy bridge code (build context: kuksa-bridge)
COPY bridge.py /app/bridge.py
COPY .env /app/.env

# Copy trigger scripts
COPY script/trigger-on.sh /app/script/trigger-on.sh
COPY script/trigger-off.sh /app/script/trigger-off.sh

# Install bash, podman, stress-ng and other dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash \
    podman \
    stress-ng \
    procps \
    psmisc \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir pyserial kuksa-client python-dotenv

# Make scripts executable
RUN chmod +x /app/script/*.sh

# Disable Python output buffering for real-time logs
ENV PYTHONUNBUFFERED=1

CMD ["python3", "-u", "bridge.py"]
