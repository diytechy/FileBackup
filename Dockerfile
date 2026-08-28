ARG POWERSHELL_IMAGE=mcr.microsoft.com/powershell:7.5-ubuntu-24.04@sha256:042240d57ec9e47e511033b92625a8d95875ee5860af3015992c248b58a8be81
FROM ${POWERSHELL_IMAGE}

ARG SYSTEM_IO_HASHING_VERSION=8.0.0
ARG SYSTEM_IO_HASHING_SHA256=B33386B744CD068E9D11D0B781FE87F9EF585B7370D30A1AE949C218618AE5C1

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl p7zip-full unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/filebackup

COPY FileBackup.ps1 ./
# The deployed-kit contract uses this canonical uppercase name. Windows source
# checkouts are case-insensitive; Linux container filesystems are not.
COPY Reconstruct.ps1 ./RECONSTRUCT.ps1
COPY Modules/ ./Modules/
COPY bash/reconstruct.sh ./bash/reconstruct.sh
# The macOS launcher is part of the restore kit New-ReconstructScript deposits
# (SR-007, seven artifacts), and that function THROWS when a kit template is
# missing - so omitting this file here would fail every backup the container
# runs, not merely ship a smaller kit.
COPY bash/reconstruct.command ./bash/reconstruct.command
COPY container/entrypoint.sh ./container/entrypoint.sh

# Bake the required hashing assembly into the image. Production runs never use
# FileBackup's interactive/online package installation path.
RUN curl --fail --location --silent --show-error \
        "https://api.nuget.org/v3-flatcontainer/system.io.hashing/${SYSTEM_IO_HASHING_VERSION}/system.io.hashing.${SYSTEM_IO_HASHING_VERSION}.nupkg" \
        --output /tmp/system.io.hashing.zip \
    && echo "${SYSTEM_IO_HASHING_SHA256}  /tmp/system.io.hashing.zip" | sha256sum --check --strict \
    && unzip -j /tmp/system.io.hashing.zip 'lib/net8.0/System.IO.Hashing.dll' -d /opt/filebackup/Modules \
    && rm /tmp/system.io.hashing.zip \
    && chmod 0555 /opt/filebackup/container/entrypoint.sh \
    && groupadd --gid 65532 filebackup \
    && useradd --uid 65532 --gid 65532 --no-create-home --home-dir /tmp/filebackup-home filebackup

ENV FILEBACKUP_CONFIG_PATH=/config/FileBackup.json \
    FILEBACKUP_LOG_PATH=/logs/Backup_Global.log \
    FILEBACKUP_7ZIP_PATH=/usr/bin/7z \
    HOME=/tmp/filebackup-home

USER 65532:65532

ENTRYPOINT ["/opt/filebackup/container/entrypoint.sh"]
