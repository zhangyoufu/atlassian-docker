FROM ubuntu:latest@sha256:adf73ca014822ad8237623d388cedf4d5346aa72c270c5acc01431cc93e18e2d

# locale (for file.encoding property)
ENV LC_CTYPE=C.UTF-8

# upgrade/install distro packages
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Use-Pty=0 ca-certificates fontconfig gosu tini

# configure oracle-java repo
COPY oracle-java.gpg /etc/apt/
COPY oracle-java.sources /etc/apt/sources.list.d/

# install oracle-java
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Use-Pty=0 --no-install-recommends oracle-java-8-jre-headless oracle-java-8-cacerts

# clean up apt/dpkg garbage
RUN rm -rf /var/cache/debconf/*-old /var/lib/apt/lists/* /var/lib/dpkg/*-old

# generate Class Data Sharing archive to reduce JRE startup time
RUN java -XX:-UsePerfData -Xshare:dump

# install support scripts
COPY support/ /opt/atlassian/support/

# build arguments
ARG APP
ARG USER
ARG GROUP
ARG UID_GID
ARG PORT
ARG APP_INSTALL_DIR
ARG APP_HOME

# install application
COPY app "${APP_INSTALL_DIR}"

# add user/group
RUN groupadd --system --gid "${UID_GID}" "${GROUP}" && grpck --sort && rm /etc/*-
RUN useradd --system --uid "${UID_GID}" --gid "${UID_GID}" --home-dir "${APP_HOME}" --shell /usr/sbin/nologin --no-log-init "${USER}" && pwck --sort && rm /etc/*-

# set owner/group/permission (for book-keeping, checked in entrypoint.sh)
RUN install -d -m 750 -o "${USER}" -g "${GROUP}" "${APP_HOME}"
RUN install -d -m 750 -o "${USER}" -g "${GROUP}" "${APP_INSTALL_DIR}/logs/"
RUN install -d -m 750 -o "${USER}" -g "${GROUP}" "${APP_INSTALL_DIR}/temp/"
RUN install -d -m 750 -o "${USER}" -g "${GROUP}" "${APP_INSTALL_DIR}/work/"

# entrypoint
COPY entrypoint.sh /
RUN mkdir /docker-entrypoint.d

# runtime
ENV ${APP}_INSTALL_DIR=${APP_INSTALL_DIR}
ENV ${APP}_HOME=${APP_HOME}
ENV RUN_UID=${UID_GID}
ENV RUN_GID=${UID_GID}
VOLUME ["${APP_HOME}"]
WORKDIR ${APP_HOME}
ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
EXPOSE ${PORT}
