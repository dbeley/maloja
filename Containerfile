FROM lsiobase/alpine:3.21 AS base

WORKDIR /usr/src/app


# based on https://github.com/linuxserver/docker-pyload-ng/blob/main/Dockerfile

RUN \
  echo "" && \
  echo "**** install build packages ****" && \
	apk add --no-cache --virtual=build-deps \
		gcc \
		g++ \
		python3-dev \
		libxml2-dev \
		libxslt-dev \
		libffi-dev \
		libc-dev \
		py3-pip \
		linux-headers && \
  echo "" && \
	echo "**** install runtime packages ****" && \
	apk add --no-cache \
		python3 \
		py3-lxml \
		libmagic \
		tzdata && \
  echo "" && \
	echo "**** install pip and build backend ****" && \
	python3 -m venv /venv && \
    . /venv/bin/activate && \
	python3 -m ensurepip && \
    pip install -U --no-cache-dir \
	  pip \
	  wheel \
	  flit-core

# Copy pyproject.toml with its referenced files (README.md, LICENSE) and install dependencies
# This layer is cached unless pyproject.toml changes
COPY --chown=abc:abc pyproject.toml README.md LICENSE .

RUN \
  echo "" && \
	echo "**** install maloja dependencies from pyproject.toml ****" && \
	. /venv/bin/activate && \
	pip install --no-cache-dir -e . && \
  echo "" && \
	echo "**** cleanup build dependencies ****" && \
	apk del --purge \
		build-deps && \
	rm -rf \
		/tmp/* \
		${HOME}/.cache

# Copy the rest of the source and reinstall (only the package itself, deps are cached)
COPY --chown=abc:abc maloja/ ./maloja/

RUN \
  echo "" && \
	echo "**** install maloja ****" && \
	. /venv/bin/activate && \
	pip install --no-cache-dir -e . && \
	rm -rf \
		/tmp/* \
		${HOME}/.cache


COPY container/root/ /

ENV	\
	# Docker-specific configuration
	MALOJA_SKIP_SETUP=yes \
	MALOJA_CONTAINER=yes \
	PYTHONUNBUFFERED=1 \
	# Prevents breaking change for previous container that ran maloja as root
	# On linux hosts (non-podman rootless) these variables should be set to the
	# host user that should own the host folder bound to MALOJA_DATA_DIRECTORY
	PUID=0 \
	PGID=0

EXPOSE 42010

VOLUME /data
