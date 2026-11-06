ARG BUILD_IMAGE=rust:1.96-bookworm@sha256:a339861ae23e9abb272cea45dfafde21760d2ce6577a70f8a926153677902663
ARG RUNTIME_IMAGE=debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc
FROM ${BUILD_IMAGE} AS build
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY rust ./rust
COPY recovery ./recovery
COPY Modules/FileBackup.Common.psm1 ./Modules/FileBackup.Common.psm1
COPY bash/reconstruct.sh ./bash/reconstruct.sh
COPY scripts/prepare_native_hash.py scripts/package_native.py ./scripts/
COPY docs/native-usage.md docs/native-support.md ./docs/
RUN python3 scripts/prepare_native_hash.py --cache /build/deps
ENV FILEBACKUP_HASH_DLL=/build/deps/System.IO.Hashing.dll
RUN --mount=type=cache,target=/usr/local/cargo/registry --mount=type=cache,target=/build/rust/target \
    cargo build --locked --release --manifest-path rust/Cargo.toml \
    && python3 scripts/package_native.py --binary rust/target/release/filebackup --output /package

FROM ${RUNTIME_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates bash gawk xxhash p7zip-full coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 65532 filebackup \
    && useradd --uid 65532 --gid 65532 --no-create-home --home-dir /tmp filebackup
COPY --from=build /package /opt/filebackup
COPY container/native.entrypoint.sh /opt/filebackup/entrypoint.sh
RUN chmod 0555 /opt/filebackup/filebackup /opt/filebackup/entrypoint.sh
ENV FILEBACKUP_CONFIG_PATH=/config/FileBackup.json HOME=/tmp
USER 65532:65532
ENTRYPOINT ["/opt/filebackup/entrypoint.sh"]
