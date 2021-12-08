FROM ubuntu:focal as pre_base

# Warning: This file is experimental.
#
# Short-term goals:
# * Be a suitable replacement for the `edxops/edxapp` image in devstack (in progress).
# * Take advantage of Docker caching layers: aim to put commands in order of
#   increasing cache-busting frequency.
# * Related to ^, use no Ansible or Paver.
# Long-term goals:
# * Be a suitable base for production LMS and Studio images (THIS IS NOT YET THE CASE!).
#
# TODO: factor out an env-agnostic base from which a `dev` and `prod` stages
#       can be derived (for both lms and studio).

# Install system requirements.
# We update, upgrade, and delete lists all in one layer
# in order to reduce total image size.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes \
        # Global requirements
        build-essential \
        curl \
        # If we don't need gcc, we should remove it.
        g++ \
        gcc \
        git \
        git-core \
        language-pack-en \
        libfreetype6-dev \
        libmysqlclient-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libxslt1-dev \
        swig \
        # openedx requirements
        gettext \
        gfortran \
        graphviz \
        libffi-dev \
        libfreetype6-dev \
        libgeos-dev \
        libgraphviz-dev \
        libjpeg8-dev \
        liblapack-dev \
        libpng-dev \
        libsqlite3-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libxslt1-dev \
        # lynx: Required by https://github.com/edx/edx-platform/blob/b489a4ecb122/openedx/core/lib/html_to_text.py#L16
        lynx \
        ntp \
        pkg-config \
        python3-dev \
        python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Set locale.
RUN locale-gen en_US.UTF-8

# Define and switch to working directory.
WORKDIR /openedx/app/edxapp/edx-platform

# Settings: locale
ENV LANG='en_US.UTF-8'
ENV LANGUAGE='en_US:en'
ENV LC_ALL='en_US.UTF-8'

# Settings: configuration
ENV CONFIG_ROOT='/openedx/etc/'
ENV LMS_CFG='/openedx/etc/lms.yml'
ENV STUDIO_CFG='/openedx/etc/studio.yml'
ENV EDX_PLATFORM_SETTINGS='devstack_docker'

# Settings: path
ENV VIRTUAL_ENV='/openedx/app/edxapp/venvs/edxapp'
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV PATH="./node_modules/.bin:${PATH}"
ENV PATH="/openedx/app/edxapp/edx-platform/bin:${PATH}"
ENV PATH="/openedx/app/edxapp/nodeenv/bin:${PATH}"

# Settings: paver
# We intentionally don't use paver in this Dockerfile, but Devstack may invoke paver commands
# during provisioning. Enabling NO_PREREQ_INSTALL tells paver not to re-install Python
# requirements for every paver command, saving a lot of time.
ENV NO_PREREQ_INSTALL='1'

# Copy in custom system files.
COPY container-root /

# Dump above environment vars to ../edxapp_env so they can be available to
# those opening a shell against this container.
RUN (echo "export LANG='$LANG'" \
  && echo "export PATH='$PATH'" \
  && echo "export LMS_CFG='$LMS_CFG'" \
  && echo "export STUDIO_CFG='$STUDIO_CFG'" \
  && echo "export NO_PREREQ_INSTALL='$NO_PREREQ_INSTALL'" \
  && echo "export EDX_PLATFORM_SETTINGS='$EDX_PLATFORM_SETTINGS'" \
    ) >> ../edxapp_env

# Set up a Python virtual environment.
# It is already 'activated' because $VIRTUAL_ENV/bin was put on $PATH.
RUN python3.8 -m venv "$VIRTUAL_ENV"

# TODO: This stage is purely for Dockerfile debugging purposes.
# It should be removed when the image is no longer experimental.
FROM pre_base AS base

# Install Python requirements.
# Requires copying over requirements files, but not entire repository.
# We filter out the local ('common/*' and 'openedx/*', and '.') Python projects,
# because those require code in order to be installed. They will be installed
# later. This step can be simplified when the local projects are dissolved
# (see https://openedx.atlassian.net/browse/BOM-2579).
COPY requirements requirements
RUN  sed '/^-e \(common\/\|openedx\/\|.\)/d' requirements/edx/base.txt \
  > requirements/edx/base-minus-local.txt
RUN pip install -r requirements/pip.txt
RUN pip install -r requirements/edx/base-minus-local.txt

# Set up a Node environment and install Node requirements.
# Must be done after Python requirements, since nodeenv is installed
# via pip.
# The node environment is already 'activated' because its .../bin was put on $PATH.
RUN nodeenv /openedx/app/edxapp/nodeenv --node=12.11.1 --prebuilt
COPY package.json package.json
COPY package-lock.json package-lock.json
RUN npm set progress=false && npm install

# Copy over remaining parts of repository (including all code).
COPY . .

# Install Python requirements again in order to capture local projects, which
# were skipped earlier. This should be much quicker than if were installing
# all requirements from scratch.
RUN pip install -r requirements/edx/base.txt

##################################################
# Define LMS non-dev target.
FROM base as lms
ENV SERVICE_VARIANT lms
ENV EDX_PLATFORM_SETTINGS='production'
ENV DJANGO_SETTINGS_MODULE="lms.envs.$EDX_PLATFORM_SETTINGS"
EXPOSE 8000
CMD gunicorn \
    -c /openedx/app/edxapp/edx-platform/lms/docker_lms_gunicorn.py \
    --name lms \
    --bind=0.0.0.0:8000 \
    --max-requests=1000 \
    --access-logfile \
    - lms.wsgi:application

##################################################
# Define Studio non-dev target.
FROM base as studio
ENV SERVICE_VARIANT studio
ENV EDX_PLATFORM_SETTINGS='production'
ENV DJANGO_SETTINGS_MODULE="cms.envs.$EDX_PLATFORM_SETTINGS"
EXPOSE 8010
CMD gunicorn \
    -c /openedx/app/edxapp/edx-platform/cms/docker_cms_gunicorn.py \
    --name cms \
    --bind=0.0.0.0:8010 \
    --max-requests=1000 \
    --access-logfile \
    - cms.wsgi:application

##################################################
# Define intermediate dev target for LMS/Studio.
# Install development requirements and rewrite EDX_PLATFORM_SETTINGS
# variable to ../edxapp_env, so ../edxapp_env will look like:
#   export PATH='...''
#   export ...
#   export EDX_PLATFORM_SETTINGS=production
#   export EDX_PLATFORM_SETTINGS=devstack_docker
# Per bash semantics, the latter export will override the former.
#
# Although it might seem more logical to forego the `dev` stage
# and instead base `lms-dev` and `studio-dev` off of `lms` and
# `studio`, respectively, we choose to have this `dev` stage
# so that the installed development requirements are contained
# in a single layer, shared between `lms-dev` and `studio-dev`.
FROM base as dev
RUN pip install -r requirements/edx/development.txt
ENV EDX_PLATFORM_SETTINGS='devstack_docker'
RUN echo "export EDX_PLATFORM_SETTINGS='$EDX_PLATFORM_SETTINGS'" >> ../edxapp_env

##################################################
#  Define LMS dev target.
FROM dev as lms-dev
ENV DJANGO_SETTINGS_MODULE="lms.envs.$EDX_PLATFORM_SETTINGS"
EXPOSE 18000
CMD while true; do python ./manage.py lms runserver 0.0.0.0:18000; sleep 2; done


##################################################
#  Define Studio dev target.
FROM dev as studio-dev
ENV DJANGO_SETTINGS_MODULE="cms.envs.$EDX_PLATFORM_SETTINGS"
EXPOSE 18010
CMD while true; do python ./manage.py cms runserver 0.0.0.0:18010; sleep 2; done
