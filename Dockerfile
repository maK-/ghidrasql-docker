FROM ghidrasql-ai-base:latest

USER root

RUN apk add --no-cache \
    git \
    cmake \
    ninja \
    curl \
    ca-certificates \
    gradle \
    build-base \
    linux-headers \
    protobuf-dev \
    py3-pip \
    python3-dev

ARG LIBGHIDRA_REF=main
ARG GHIDRASQL_REF=main
ARG LIBXSQL_REF=ea11622eeec5ac7e5988364ebfaffefccb1bb3f4
ARG GHIDRASQL_SKILLS_REF=main

RUN mkdir -p /opt/src /opt/ghidrasql/scripts

RUN git clone https://github.com/0xeb/libghidra.git /opt/src/libghidra \
 && cd /opt/src/libghidra \
 && git checkout "${LIBGHIDRA_REF}"

RUN git clone https://github.com/0xeb/libxsql.git /opt/src/libxsql \
 && cd /opt/src/libxsql \
 && git checkout "${LIBXSQL_REF}"

RUN git clone https://github.com/0xeb/ghidrasql.git /opt/src/ghidrasql \
 && cd /opt/src/ghidrasql \
 && git checkout "${GHIDRASQL_REF}"

COPY docker/patch-ghidrasql-source.py /tmp/patch-ghidrasql-source.py
RUN python3 /tmp/patch-ghidrasql-source.py \
 && rm /tmp/patch-ghidrasql-source.py \
 && grep -q 'MemoryBlockRecord' /opt/src/ghidrasql/src/lib/src/source_libghidra.cpp \
 && grep -q 'ListFunctions(start, range_end' /opt/src/ghidrasql/src/lib/src/source_libghidra.cpp \
 && grep -q 'out.push_back(map_symbol(row))' /opt/src/ghidrasql/src/lib/src/source_libghidra.cpp \
 && ! grep -q 'client::MemoryBlock>' /opt/src/ghidrasql/src/lib/src/source_libghidra.cpp

RUN cd /opt/src/libghidra/ghidra-extension \
 && gradle installExtension -PGHIDRA_INSTALL_DIR=/ghidra

RUN test -d /ghidra/Ghidra/Extensions/LibGhidraHost

RUN cp /opt/src/libghidra/ghidra-extension/ghidra_scripts/LibGhidraHeadlessServer.java \
        /opt/ghidrasql/scripts/LibGhidraHeadlessServer.java \
 && test -f /opt/ghidrasql/scripts/LibGhidraHeadlessServer.java

RUN /ghidra/venv/bin/python3 -m pip install --upgrade pip setuptools wheel \
 && /ghidra/venv/bin/python3 -m pip install -e "/opt/src/libghidra/python[cli]"

RUN /ghidra/venv/bin/python3 -m pip show libghidra \
 && /ghidra/venv/bin/python3 - <<'PYI'
import libghidra
print("libghidra import OK:", libghidra.__file__)
PYI

RUN cmake -S /opt/src/ghidrasql -B /opt/src/ghidrasql/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-Wno-missing-requires" \
      -DGHIDRASQL_LIBGHIDRA_DIR=/opt/src/libghidra/cpp \
      -DGHIDRASQL_LIBXSQL_DIR=/opt/src/libxsql \
 && cmake --build /opt/src/ghidrasql/build --config Release -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" \
 && find /opt/src/ghidrasql/build -type f -name ghidrasql -print -quit \
      | xargs -I{} install -m 0755 {} /usr/local/bin/ghidrasql

RUN test -x /usr/local/bin/ghidrasql \
 && /usr/local/bin/ghidrasql --help >/tmp/ghidrasql-help.txt

RUN git clone https://github.com/0xeb/ghidrasql-skills.git /opt/ghidrasql-skills \
 && cd /opt/ghidrasql-skills \
 && git checkout "${GHIDRASQL_SKILLS_REF}" || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PATH="/ghidra/venv/bin:/usr/local/bin:${PATH}"
ENV GHIDRA_INSTALL_DIR=/ghidra

USER ghidra
WORKDIR /ghidra

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EXPOSE 18080 8081
