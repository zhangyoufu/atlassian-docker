FROM youfu/oracle-jre-headless:14@sha256:5e065b321ef9adbe31c7be4aafab73a14d28d165b098f8087a21ce100917fab6

# upgrade & install packages
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends fontconfig gosu tini
RUN rm -rf /var/cache/debconf/*-old /var/lib/apt/lists/* /var/lib/dpkg/*-old

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
