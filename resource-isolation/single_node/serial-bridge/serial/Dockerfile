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

# Copy all files from build context
COPY . /app

# Install dependencies
RUN pip install --no-cache-dir \
    pyserial \
    kuksa-client \
    requests

# Run the bridge
CMD ["python", "bridge.py"]
