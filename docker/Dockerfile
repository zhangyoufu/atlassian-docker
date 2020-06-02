FROM ubuntu:20.04@sha256:5747316366b8cc9e3021cd7286f42b2d6d81e3d743e2ab571f55bcd5df788cc8

# upgrade/install distro packages
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
RUN apt-get install -y ca-certificates fontconfig gosu tini

# configure oracle-java repo
COPY oracle-java.gpg /etc/apt/
COPY oracle-java.sources /etc/apt/sources.list.d/

# install oracle-java
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends oracle-java-8-jre-headless oracle-java-8-cacerts

# clean up apt/dpkg garbage
RUN rm -rf /var/cache/debconf/*-old /var/lib/apt/lists/* /var/lib/dpkg/*-old

# generate Class Data Sharing archive to reduce JRE startup time
RUN java -XX:-UsePerfData -Xshare:dump

# install jira
ENV JIRA_INSTALL_DIR=/opt/atlassian/jira
COPY jira "${JIRA_INSTALL_DIR}"

# install support scripts
COPY support/ /opt/atlassian/support/

# add user/group
ENV JIRA_HOME=/var/atlassian/application-data/jira
ENV RUN_UID=2001
ENV RUN_GID=2001
RUN groupadd --system --gid "${RUN_GID}" jira && grpck --sort && rm /etc/*-
RUN useradd --system --uid "${RUN_UID}" --gid "${RUN_GID}" --home-dir "${JIRA_HOME}" --shell /usr/sbin/nologin --no-log-init jira && pwck --sort && rm /etc/*-

# set owner/group/permission (for book-keeping, checked in entrypoint.sh)
RUN install -d -m 750 -o jira -g jira "${JIRA_HOME}"
RUN install -d -m 750 -o jira -g jira "${JIRA_INSTALL_DIR}/logs/"
RUN install -d -m 750 -o jira -g jira "${JIRA_INSTALL_DIR}/temp/"
RUN install -d -m 750 -o jira -g jira "${JIRA_INSTALL_DIR}/work/"

# entrypoint
COPY entrypoint.sh /

# runtime
VOLUME ["${JIRA_HOME}"]
WORKDIR ${JIRA_HOME}
ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
EXPOSE 8080
