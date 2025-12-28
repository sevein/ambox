ARG USER_ID=1000
ARG GROUP_ID=1000

ARG UBUNTU_VERSION=24.04
ARG S6_OVERLAY_VERSION=3.2.1.0
ARG PYTHON_VERSION=3.10.19
ARG UV_VERSION=0.9.18
ARG NODE20_VERSION=20.19.6
ARG NODE24_VERSION=24.12.0
ARG SFTPGO_VERSION=2.7.0
ARG MEDIAAREA_VERSION=1.0-25
ARG JHOVE_VERSION=1.34.0-1~22.04

# Required seed cache image (OCI artifact with /seed/*.sql.gz).
# Default keeps Dockerfile parsers happy; runtime stage enforces override.
ARG AM_SEED_CACHE_IMAGE=seedcache-empty

# uv provides the uv and uvx binaries.
# -----------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

# base provides our custom ubuntu distro.
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS base

ARG USER_ID
ARG GROUP_ID

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
	set -ex \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		gnupg \
		locales \
	&& rm -rf /var/lib/apt/lists/*

ENV DEBIAN_FRONTEND=noninteractive
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Ensure the requested UID/GID do not clash with defaults in the Ubuntu base
# image. We look up any existing user/group that already uses such identifiers
# and remove them to avoid conflicts before creating the archivematica account.
RUN set -ex \
	&& { \
		grp=$(getent group "${GROUP_ID}" | cut -d: -f1 || true); \
		if [ -n "${grp}" ]; then groupdel --force "${grp}"; fi; \
		usr=$(getent passwd "${USER_ID}" | cut -d: -f1 || true); \
		if [ -n "${usr}" ]; then userdel --remove "${usr}"; fi; \
	} \
	&& groupadd --gid ${GROUP_ID} --system archivematica \
	&& useradd --uid ${USER_ID} --gid ${GROUP_ID} --home-dir /var/archivematica --system archivematica

# python-builder provides Python and the virtual environments.
# -----------------------------------------------------------------------------
FROM base AS python-builder

ARG PYTHON_VERSION
ARG USER_ID
ARG GROUP_ID

# Build dependencies for Python packages in requirements.txt.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	set -ex \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		git \
		libldap2-dev \
		libmysqlclient-dev \
		libsasl2-dev \
		make \
		pkg-config \
		tzdata

# Install uv by copying the binary from the official uv image.
COPY --from=uv /uv /uvx /usr/local/bin/

# Use an unprivileged user for Python/venv/package installation.
RUN set -ex \
    && mkdir -p /python /venv /venv-ss /home/archivematica/.cache/uv \
    && chown -R archivematica:archivematica /python /venv /venv-ss /home/archivematica/.cache

# Use uv-managed Python and keep its install dir stable for copying into the
# final stage.
ENV UV_PYTHON_INSTALL_DIR=/python \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_CACHE_DIR=/home/archivematica/.cache/uv

USER archivematica

RUN --mount=type=cache,target=/home/archivematica/.cache/uv,sharing=locked,uid=${USER_ID},gid=${GROUP_ID} \
    uv python install ${PYTHON_VERSION}

COPY requirements.txt /requirements-am.txt
RUN --mount=type=cache,target=/home/archivematica/.cache/uv,sharing=locked,uid=${USER_ID},gid=${GROUP_ID} \
    set -ex \
	&& uv venv --python ${PYTHON_VERSION} /venv \
	&& uv pip install --python /venv/bin/python -r /requirements-am.txt

COPY hack/submodules/archivematica-storage-service/requirements.txt /requirements-ss.txt
RUN --mount=type=cache,target=/home/archivematica/.cache/uv,sharing=locked,uid=${USER_ID},gid=${GROUP_ID} \
    set -ex \
	&& uv venv --python ${PYTHON_VERSION} /venv-ss \
	&& uv pip install --python /venv-ss/bin/python -r /requirements-ss.txt

# frontend-builder provides the frontend assets.
# -----------------------------------------------------------------------------
FROM node:${NODE20_VERSION} AS frontend-builder
WORKDIR /src/src/archivematica/dashboard/frontend
COPY --link src/archivematica/dashboard/frontend/package.json /src/src/archivematica/dashboard/frontend/package.json
COPY --link src/archivematica/dashboard/frontend/package-lock.json /src/src/archivematica/dashboard/frontend/package-lock.json
RUN npm clean-install --ignore-scripts
COPY --link src/archivematica/dashboard/frontend /src/src/archivematica/dashboard/frontend
RUN npm run prepare

# vue-builder provides the Vue.js frontend assets.
# -----------------------------------------------------------------------------
FROM node:${NODE24_VERSION} AS vue-builder
WORKDIR /src/src/archivematica/dashboard/vue
COPY --link src/archivematica/dashboard/vue/package.json /src/src/archivematica/dashboard/vue/package.json
COPY --link src/archivematica/dashboard/vue/package-lock.json /src/src/archivematica/dashboard/vue/package-lock.json
RUN npm clean-install --ignore-scripts
COPY --link src/archivematica/dashboard/vue /src/src/archivematica/dashboard/vue
RUN npm run build

# Empty seed cache stage (used when explicitly requested).
FROM base AS seedcache-empty
RUN mkdir -p /seed

# Seed cache stage (must be provided via AM_SEED_CACHE_IMAGE).
FROM ${AM_SEED_CACHE_IMAGE} AS seedcache

# The final runtime image.
# -----------------------------------------------------------------------------
FROM base AS runtime-base

ARG USER_ID
ARG GROUP_ID
ARG MEDIAAREA_VERSION
ARG JHOVE_VERSION
ARG S6_OVERLAY_VERSION
ARG SFTPGO_VERSION

# Install uv in the runtime image for PEP 723 scripts.
COPY --from=uv /uv /uvx /usr/local/bin/

RUN set -ex \
	&& UBUNTU_CODENAME=$(grep -Po '(?<=^VERSION_CODENAME=).+' /etc/os-release) \
	&& UBUNTU_ARCH=$(dpkg --print-architecture)  \
	&& curl --retry 3 -fsSL https://packages.archivematica.org/1.19.x/key.asc | gpg --dearmor -o /etc/apt/keyrings/archivematica-1.19.x.gpg \
	&& echo "deb [arch=${UBUNTU_ARCH} signed-by=/etc/apt/keyrings/archivematica-1.19.x.gpg] http://packages.archivematica.org/1.19.x/ubuntu-externals ${UBUNTU_CODENAME} main" > /etc/apt/sources.list.d/archivematica-external.list \
	&& curl --retry 3 -so /tmp/repo-mediaarea.deb -L https://mediaarea.net/repo/deb/repo-mediaarea_${MEDIAAREA_VERSION}_all.deb \
	&& dpkg -i /tmp/repo-mediaarea.deb \
	&& rm /tmp/repo-mediaarea.deb

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	set -ex \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		atool \
		bulk-extractor \
		coreutils \
		ffmpeg \
		gearman \
		gettext \
		gzip \
		ghostscript \
		hashdeep \
		imagemagick \
		inkscape \
		jhove=${JHOVE_VERSION} \
		libimage-exiftool-perl \
		libffi8 \
		libldap2 \
		libmysqlclient21 \
		libsasl2-2 \
		libssl3t64 \
		libxml2 \
		libxslt1.1 \
		logapp \
		md5deep \
		mediaconch \
		mediainfo \
		media-types \
		mysql-server \
		mysql-client \
		nginx \
		nfs-common \
		openjdk-8-jre-headless \
		p7zip-full \
		pbzip2 \
		pst-utils \
		python3-lxml \
		rclone \
		rng-tools-debian \
		rsync \
		siegfried \
		sleuthkit \
		tesseract-ocr \
		tree \
		unar \
		unrar-free \
		uuid \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

# Install SFTPGo from upstream release assets.
RUN set -ex \
	&& ARCH=$(uname -m) \
	&& if [ "$ARCH" = "x86_64" ]; then SFTPGO_ARCH="x86_64"; \
	elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then SFTPGO_ARCH="arm64"; \
	else echo "Unsupported architecture for SFTPGo: $ARCH" && exit 1; fi \
	&& curl -fsSL -o /tmp/sftpgo.tar.xz "https://github.com/drakkan/sftpgo/releases/download/v${SFTPGO_VERSION}/sftpgo_v${SFTPGO_VERSION}_linux_${SFTPGO_ARCH}.tar.xz" \
	&& tar -C /tmp -xJf /tmp/sftpgo.tar.xz \
	&& install -m 0755 /tmp/sftpgo /usr/local/bin/sftpgo \
	&& install -d -m 0755 /etc/sftpgo \
	&& install -d -m 0755 /var/lib/sftpgo/templates \
	&& if [ -d /tmp/templates ]; then cp -r /tmp/templates/* /var/lib/sftpgo/templates/; fi \
	&& rm -rf /tmp/*

# Allow our user to access the MySQL unix socket via the mysql group.
RUN usermod -aG mysql archivematica

# Allow gearmand to write its log file when running as an unprivileged user.
RUN install -o gearman -g gearman -m 0644 /dev/null /var/log/gearmand.log

RUN set -ex \
	&& mkdir -p \
		/var/archivematica/sharedDirectory \
		/var/archivematica/storage_service \
		/var/archivematica/storage_service/.gnupg \
		/var/archivematica/.cache/uv \
		/var/lib/sftpgo \
	&& chown -R archivematica:archivematica \
		/var/archivematica \
		/var/lib/sftpgo

# Bring in python and the virtual environments.
COPY --from=python-builder /python /python
COPY --from=python-builder /venv /venv
COPY --from=python-builder /venv-ss /venv-ss

# Install s6-overlay.
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm /tmp/s6-overlay-noarch.tar.xz
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then S6_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then S6_ARCH="aarch64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -L -o /tmp/s6-overlay-arch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && rm /tmp/s6-overlay-arch.tar.xz
COPY hack/box/s6-rc.d/ /etc/s6-overlay/s6-rc.d/
COPY --link hack/box/scripts/disable-virus-scan.py /usr/local/bin/disable-virus-scan.py
COPY --link hack/box/scripts/wait-http.sh /usr/local/bin/wait-http.sh
COPY --link hack/box/scripts/wait-mysql.sh /usr/local/bin/wait-mysql.sh

# Install Nginx reverse-proxy configuration for the monolith.
COPY hack/box/etc/nginx/ /etc/nginx/
COPY hack/box/etc/sftpgo/initial-data.json /etc/sftpgo/initial-data.json
COPY hack/box/etc/sftpgo/sftpgo.json /etc/sftpgo/sftpgo.json
COPY hack/box/etc/archivematica/ /etc/archivematica/
RUN set -ex \
	&& rm -rf /etc/s6-overlay/s6-rc.d/contents.d \
	&& mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d

# Copy the application source code.
COPY --chown=${USER_ID}:${GROUP_ID} --link . /src

# Seed common sample transfers into the default transfer source location.
RUN set -ex \
	&& install -d -o archivematica -g archivematica -m 0755 /home/archivematica/sampledata \
	&& install -d -o archivematica -g archivematica -m 0755 /home/archivematica/transfers \
	&& if [ -d /src/hack/submodules/archivematica-sampledata/SampleTransfers ]; then \
		cp -a \
			/src/hack/submodules/archivematica-sampledata/SampleTransfers/DemoTransferCSV \
			/src/hack/submodules/archivematica-sampledata/SampleTransfers/Images \
			/home/archivematica/sampledata/; \
	else \
		echo "Sampledata submodule not present; skipping seed sample transfers."; \
	fi \
	&& chown -R archivematica:archivematica /home/archivematica/sampledata /home/archivematica/transfers

# Build-time seed helper script.
COPY --link hack/box/scripts/seed/seed.sh /usr/local/bin/seed.sh

# Dashboard build-time preparation.
USER root
RUN set -ex \
	&& internalDirs=' \
		/src/src/archivematica/dashboard/frontend \
		/src/src/archivematica/dashboard/static \
		/src/src/archivematica/dashboard/media \
	' \
	&& mkdir -p $internalDirs \
	&& chown -R archivematica:archivematica $internalDirs
COPY --from=frontend-builder --link /src/src/archivematica/dashboard/media/js/ /src/src/archivematica/dashboard/media/js/
COPY --from=vue-builder --link /src/src/archivematica/dashboard/vue/dist /src/src/archivematica/dashboard/vue/dist

ENV PATH="/venv/bin:$PATH"
ENV PYTHONPATH=/src/src

# Seed builder stage (generates /docker-seed).
FROM runtime-base AS seed-builder
RUN /usr/local/bin/seed.sh

# Final runtime image (requires AM_SEED_CACHE_IMAGE to provide dumps).
FROM runtime-base AS runtime
ARG AM_SEED_CACHE_IMAGE
RUN if [ "$AM_SEED_CACHE_IMAGE" = "seedcache-empty" ]; then \
		echo "AM_SEED_CACHE_IMAGE must be set to a seed cache image" >&2; \
		exit 1; \
	fi

# Pre-seed the MySQL databases during build to speed up container startup.
# Dumps are loaded by the db-seed oneshot at runtime.
RUN --mount=type=bind,from=seedcache,source=/seed,target=/seed-cache,ro \
	install -d /docker-seed \
	&& cp /seed-cache/mcp.sql.gz /docker-seed/mcp.sql.gz \
	&& cp /seed-cache/ss.sql.gz /docker-seed/ss.sql.gz \
	&& if [ -f /seed-cache/seed.key ]; then cp /seed-cache/seed.key /docker-seed/seed.key; fi

# Precompute static assets and translations.
USER archivematica
RUN set -ex \
	&& SS_PYTHONPATH="/src/hack/submodules/archivematica-storage-service/src:${PYTHONPATH:-/src/src}" \
	&& mkdir -p \
		/src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/assets \
		/src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/media \
	&& DJANGO_SETTINGS_MODULE=archivematica.storage_service.storage_service.settings.local \
		SS_DB_URL=${SS_DB_URL:-mysql://ne:ver@min/d} \
		PYTHONPATH="$SS_PYTHONPATH" \
		/venv-ss/bin/python3 -m archivematica.storage_service.manage collectstatic --noinput --clear \
	&& DJANGO_SETTINGS_MODULE=archivematica.storage_service.storage_service.settings.local \
		SS_DB_URL=${SS_DB_URL:-mysql://ne:ver@min/d} \
		PYTHONPATH="$SS_PYTHONPATH" \
		/venv-ss/bin/python3 -m archivematica.storage_service.manage compilemessages \
	&& cd /src \
	&& DJANGO_SETTINGS_MODULE=archivematica.dashboard.settings.local \
		python3 /src/src/archivematica/dashboard/manage.py collectstatic --noinput --clear \
	&& DJANGO_SETTINGS_MODULE=archivematica.dashboard.settings.local \
		python3 /src/src/archivematica/dashboard/manage.py compilemessages

# s6-overlay uses root but s6-setuidgid will drop to archivematica later.
USER root

# Prepare runtime environment.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
EXPOSE 64080 64081 64022
ENTRYPOINT ["/init"]
