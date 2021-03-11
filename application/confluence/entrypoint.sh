#!/bin/bash
set -euo pipefail
shopt -s nullglob
umask 022

################################################################################
# Utility
################################################################################

fail() {
	echo "$1"
	exit 1
}

check_fs_owner_group() {
	[ -e "$1" ] || fail "$1 does not exist"
	local FS_UID=$(stat -c %u -- "$1")
	local FS_GID=$(stat -c %g -- "$1")
	[ ${FS_UID} -eq ${RUN_UID} ] && [ ${FS_GID} -eq ${RUN_GID} ]
}

ensure_fs_owner_group_mode() {
	check_fs_owner_group "$1" && return 0
	echo "fixing $1"
	chown -Rh "${RUN_UID}:${RUN_GID}" "$1"
	chmod -R -t,u=rw,g=r,o=,ug+X "$1"
}

################################################################################
# Custom CA
################################################################################

if [ -w /etc/ssl/certs/ca-certificates.crt ] && [ -n "$(echo /usr/local/share/ca-certificates/*.crt)" ]; then
	update-ca-certificates
fi

################################################################################
# Tomcat/Catalina
################################################################################

## reverse proxy

: ${ATL_PROXY_NAME:=${CATALINA_CONNECTOR_PROXYNAME:-}}
export ATL_PROXY_NAME

: ${ATL_PROXY_PORT:=${CATALINA_CONNECTOR_PROXYPORT:-}}
export ATL_PROXY_PORT

: ${ATL_TOMCAT_PORT:=8090}
export ATL_TOMCAT_PORT

: ${ATL_TOMCAT_SCHEME:=${CATALINA_CONNECTOR_SCHEME:-http}}
export ATL_TOMCAT_SCHEME

case "${ATL_TOMCAT_SCHEME}" in
	https) : ${CATALINA_CONNECTOR_SECURE:=true};;
	http)  : ${CATALINA_CONNECTOR_SECURE:=false};;
	*) fail 'ATL_TOMCAT_SCHEME unknown or not specified';;
esac
: ${ATL_TOMCAT_SECURE:=${CATALINA_CONNECTOR_SECURE}}
export ATL_TOMCAT_SECURE

: ${ATL_TOMCAT_CONTEXTPATH:=${CATALINA_CONTEXT_PATH:-}}
export ATL_TOMCAT_CONTEXTPATH

## advanced Tomcat settings

: ${ATL_TOMCAT_MGMT_PORT:=8000}
export ATL_TOMCAT_MGMT_PORT

: ${ATL_TOMCAT_MAXTHREADS:=100}
export ATL_TOMCAT_MAXTHREADS

: ${ATL_TOMCAT_MINSPARETHREADS:=10}
export ATL_TOMCAT_MINSPARETHREADS

: ${ATL_TOMCAT_CONNECTIONTIMEOUT:=20000}
export ATL_TOMCAT_CONNECTIONTIMEOUT

: ${ATL_TOMCAT_ENABLELOOKUPS:=false}
export ATL_TOMCAT_ENABLELOOKUPS

: ${ATL_TOMCAT_PROTOCOL:=HTTP/1.1}
export ATL_TOMCAT_PROTOCOL

: ${ATL_TOMCAT_ACCEPTCOUNT:=10}
export ATL_TOMCAT_ACCEPTCOUNT

: ${ATL_TOMCAT_MAXHTTPHEADERSIZE:=8192}
export ATL_TOMCAT_MAXHTTPHEADERSIZE

## undocumented Tomcat settings

: ${ATL_TOMCAT_REDIRECTPORT:=8443}
export ATL_TOMCAT_REDIRECTPORT

unset "${!CATALINA_CONNECTOR_@}" CATALINA_CONTEXT_PATH
## ATL_TOMCAT_ environment variables are consumed by conf/server.xml

################################################################################
# Confluence-specific
################################################################################

: ${ATL_AUTOLOGIN_COOKIE_AGE:=1209600}
_ATL_AUTOLOGIN_COOKIE_AGE=$(sed -n -e '/<param-name>autologin\.cookie\.age</{n;s|.*<param-value>\([0-9]\+\)<.*|\1|p}' "${CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/seraph-config.xml")
if [ -n "${_ATL_AUTOLOGIN_COOKIE_AGE}" ] && [ "${ATL_AUTOLOGIN_COOKIE_AGE}" != "${_ATL_AUTOLOGIN_COOKIE_AGE}" ]; then
	sed -i -e "/<param-name>autologin\.cookie\.age</{n;s|[0-9]\+|${ATL_AUTOLOGIN_COOKIE_AGE}|}" "${CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/seraph-config.xml"
fi
unset ATL_AUTOLOGIN_COOKIE_AGE _ATL_AUTOLOGIN_COOKIE_AGE

: ${CONFLUENCE_LOG_STDOUT:=true}
export CONFLUENCE_LOG_STDOUT

################################################################################
# utility
################################################################################

property_defined() {
	[ -v "PROPERTIES[$1]" ]
}

property_get() {
	echo "${PROPERTIES[$1]}"
}

property_set() {
	PROPERTIES[$1]=$2
}

## set property to default value if the property is not configured
property_default() {
	property_defined "$1" || property_set "$1" "$2"
}

## set property to the value of a variable
## also unset the variable
property_env() {
	[ -v "$2" ] || fail "$2 not defined"
	property_set "$1" "${!2}"
}

## set property to:
## 1. the value of a variable, if the variable is defined
## 2. unchanged, whether configured/unconfigured
## also unset the variable
property_env_optional() {
	[ ! -v "$2" ] || property_env "$1" "$2"
}

## set property to:
## 1. the value of a variable, if the variable is defined
## 2. original property value (unchanged), if the property is configured
## 3. default value provided
## also unset the variable
property_env_default() {
	[ ! -v "$2" ] || property_env "$1" "$2"
	property_default "$1" "$3"
}

################################################################################
# parse existing confluence.cfg.xml
################################################################################

extract_tag() {
	if [ -e "${CONFLUENCE_HOME}/confluence.cfg.xml" ]; then
		REGEX="<$1>(.*)</$1>"
		while read -r LINE; do
			if [[ ${LINE} =~ ${REGEX} ]]; then
				echo -n "${BASH_REMATCH[1]}"
				return 0
			fi
		done <"${CONFLUENCE_HOME}/confluence.cfg.xml"
	fi
	echo -n "$2"
	return 0
}

SETUP_STEP=$(extract_tag setupStep setupstart)
SETUP_TYPE=$(extract_tag setupType custom)
BUILD_NUMBER=$(extract_tag buildNumber 0)

declare -A PROPERTIES
if [ -e "${CONFLUENCE_HOME}/confluence.cfg.xml" ]; then
	REGEX='<property name="([.0-9A-Z_a-z]+)">(.*)</property>'
	while read -r LINE; do
		if [[ ${LINE} =~ ${REGEX} ]]; then
			PROPERTIES[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
		fi
	done <"${CONFLUENCE_HOME}/confluence.cfg.xml"
fi

################################################################################
# Server ID & License
################################################################################

property_env_optional confluence.setup.server.id CONFLUENCE_SETUP_SERVER_ID
property_env_optional atlassian.license.message ATL_LICENSE_KEY

################################################################################
# Directory
################################################################################

property_default attachments.dir '${confluenceHome}/attachments'
property_env_default lucene.index.dir ATL_LUCENE_INDEX_DIR '${confluenceHome}/index'
property_default webwork.multipart.saveDir '${localHome}/temp'

################################################################################
# Database
################################################################################

property_default confluence.database.connection.type database-type-standard

if [ -v ATL_DB_TYPE ]; then
	case "${ATL_DB_TYPE}" in
		mssql)
			ATL_DB_DRIVER=com.microsoft.sqlserver.jdbc.SQLServerDriver
			ATL_DB_DIALECT=com.atlassian.confluence.impl.hibernate.dialect.SQLServerDialect
		;;
		mysql)
			ATL_DB_DRIVER=com.mysql.jdbc.Driver
			ATL_DB_DIALECT=com.atlassian.confluence.impl.hibernate.dialect.MySQLDialect
		;;
		oracle12c)
			ATL_DB_DRIVER=oracle.jdbc.driver.OracleDriver
			ATL_DB_DIALECT=com.atlassian.confluence.impl.hibernate.dialect.OracleDialect
		;;
		postgresql)
			ATL_DB_DRIVER=org.postgresql.Driver
			ATL_DB_DIALECT=com.atlassian.confluence.impl.hibernate.dialect.PostgreSQLDialect
		;;
		*)
			fail 'ATL_DB_TYPE unknown or not specified'
		;;
	esac
	property_env confluence.database.choice ATL_DB_TYPE
	property_env hibernate.dialect ATL_DB_DIALECT
	property_env hibernate.connection.driver_class ATL_DB_DRIVER
fi

property_env_optional hibernate.connection.url ATL_JDBC_URL
property_env_default hibernate.connection.username ATL_JDBC_USER ''
property_env_default hibernate.connection.password ATL_JDBC_PASSWORD ''
property_env_default hibernate.c3p0.acquire_increment ATL_DB_ACQUIREINCREMENT 1
property_env_default hibernate.c3p0.idle_test_period ATL_DB_IDLETESTPERIOD 100
property_env_default hibernate.c3p0.max_size ATL_DB_POOLMAXSIZE 100 # wizard default: 60
property_env_default hibernate.c3p0.max_statements ATL_DB_MAXSTATEMENTS 0
property_env_default hibernate.c3p0.min_size ATL_DB_POOLMINSIZE 20
property_env_default hibernate.c3p0.preferredTestQuery ATL_DB_VALIDATIONQUERY 'select 1'
property_env_default hibernate.c3p0.timeout ATL_DB_TIMEOUT 30
property_env_default hibernate.c3p0.validate ATL_DB_VALIDATE false

################################################################################
# Cluster
################################################################################

if [ -v ATL_CLUSTER_TYPE ]; then
	property_set confluence.cluster true
	: ${CONFLUENCE_SHARED_HOME:=${CONFLUENCE_HOME}/shared-home}
fi

## ATL_PRODUCT_HOME_SHARED > CONFLUENCE_SHARED_HOME > confluence.cluster.home
property_env_optional confluence.cluster.home CONFLUENCE_SHARED_HOME
property_env_optional confluence.cluster.home ATL_PRODUCT_HOME_SHARED

## synchronize shared-home with confluence.cluster.home
## the only reference to shared-home property is com.atlassian.confluence.setup.actions.SetupClusterAction.doDefault()
if property_defined confluence.cluster.home; then
	property_set shared-home $(property_get confluence.cluster.home)
fi

## cluster settings
property_env_optional confluence.cluster.name ATL_CLUSTER_NAME
property_env_optional confluence.cluster.node.name ATL_CLUSTER_NODE_NAME
property_env_optional confluence.cluster.join.type ATL_CLUSTER_TYPE
property_env_optional confluence.cluster.interface ATL_CLUSTER_INTERFACE
property_env_optional confluence.cluster.address ATL_CLUSTER_ADDRESS
property_env_optional confluence.cluster.ttl ATL_CLUSTER_TTL
property_env_optional confluence.cluster.peers ATL_CLUSTER_PEERS
## https://github.com/hazelcast/hazelcast-aws
property_env_optional confluence.cluster.aws.iam.role ATL_HAZELCAST_NETWORK_AWS_IAM_ROLE
property_env_optional confluence.cluster.aws.access.key ATL_HAZELCAST_NETWORK_AWS_ACCESS_KEY
property_env_optional confluence.cluster.aws.secret.key ATL_HAZELCAST_NETWORK_AWS_SECRET_KEY
property_env_optional confluence.cluster.aws.region ATL_HAZELCAST_NETWORK_AWS_IAM_REGION
property_env_optional confluence.cluster.aws.host.header ATL_HAZELCAST_NETWORK_AWS_HOST_HEADER
property_env_optional confluence.cluster.aws.security.group ATL_HAZELCAST_NETWORK_AWS_SECURITY_GROUP
property_env_optional confluence.cluster.aws.tag.key ATL_HAZELCAST_NETWORK_AWS_TAG_KEY
property_env_optional confluence.cluster.aws.tag.value ATL_HAZELCAST_NETWORK_AWS_TAG_VALUE

################################################################################
# generate new confluence.cfg.xml
################################################################################

(
	cat <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>

	<confluence-configuration>
	  <setupStep>${SETUP_STEP}</setupStep>
	  <setupType>${SETUP_TYPE}</setupType>
	  <buildNumber>${BUILD_NUMBER}</buildNumber>
	  <properties>
	EOF

	mapfile -d '' SORTED_KEYS < <(printf '%s\0' "${!PROPERTIES[@]}" | sort -z)
	for KEY in "${SORTED_KEYS[@]}"; do
		echo "    <property name=\"${KEY}\">${PROPERTIES[${KEY}]}</property>"
	done

	cat <<-EOF
	  </properties>
	</confluence-configuration>
	EOF
) >"${CONFLUENCE_HOME}/confluence.cfg.xml.new"

mv "${CONFLUENCE_HOME}/confluence.cfg.xml.new" "${CONFLUENCE_HOME}/confluence.cfg.xml"

################################################################################
# Hook
################################################################################

for HOOK_PATH in /docker-entrypoint.d/*; do
	if [ -x "${HOOK_PATH}" ]; then
		"${HOOK_PATH}"
	else
		echo "${HOOK_PATH} is not executable, skipped"
	fi
done

unset HOOK_PATH

################################################################################
# Start
################################################################################

export -n RUN_UID RUN_GID SET_PERMISSIONS

: ${SET_PERMISSIONS:=true}

## update RUN_UID and RUN_GID
if [ ${EUID} -ne 0 ] && [ ${RUN_UID} -eq 2002 ]; then
	RUN_UID=${EUID}
fi
EGID=$(id -g)
if [ ${EGID} -ne 0 ] && [ ${RUN_GID} -eq 2002 ]; then
	RUN_GID=${EGID}
fi

## set fs owner/group/permission
if [ "${SET_PERMISSIONS}" = "true" ]; then
	ensure_fs_owner_group_mode "${CONFLUENCE_HOME}"
	ensure_fs_owner_group_mode "${CONFLUENCE_INSTALL_DIR}/logs"
	ensure_fs_owner_group_mode "${CONFLUENCE_INSTALL_DIR}/temp"
	ensure_fs_owner_group_mode "${CONFLUENCE_INSTALL_DIR}/work"
	if property_defined confluence.cluster.home; then
		ensure_fs_owner_group_mode "$(property_get confluence.cluster.home)"
	fi
fi

## start app
umask 027
if [ ${EUID} -eq ${RUN_UID} ] && [ ${EGID} -eq ${RUN_GID} ]; then
	exec "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh" -fg
else
	exec gosu "${RUN_UID}:${RUN_GID}" "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh" -fg
fi
