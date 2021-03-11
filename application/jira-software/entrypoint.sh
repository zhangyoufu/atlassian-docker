#!/bin/bash
set -euo pipefail
shopt -s nullglob
umask 022

################################################################################
# Utils
################################################################################

check_bool() {
	case "${!1}" in
		true|false) ;;
		*) echo "invalid value for $1"; exit 1;;
	esac
}

check_defined() {
	if [ ! -v "$1" ]; then
		echo "$1 not specified"
		exit 1
	fi
}

xml_escape() {
	## FIXME: unicode characters are not escaped
	echo -n "$1" | sed -z 's|&|\&amp;|g; s|<|\&lt;|g; s|>|\&gt;|g; s|"|\&#34;|g; s|'"'"'|\&#39;|g; s|\t|\&#x9;|g; s|\r|\&#xD;|g; s|\n|\&#xA;|g'
}

prop_value_escape() {
	echo -n "$1" | sed -z 's|\\|\\\\|g; s|\r|\\r|g; s|\n|\\n|g'
}

check_fs_owner_group() {
	if [ ! -e "$1" ]; then
		echo "$1 does not exist"
		exit 1
	fi
	local FS_UID=$(stat -c %u -- "$1")
	local FS_GID=$(stat -c %g -- "$1")
	[ ${FS_UID} -eq ${RUN_UID} ] && [ ${FS_GID} -eq ${RUN_GID} ]
}

set_fs_owner_group_recursive() {
	## we don't follow symbolic link as it is dangerous
	chown -R "${RUN_UID}:${RUN_GID}" "$1"
}

ensure_fs_owner_group_mode() {
	check_fs_owner_group "$1" && return
	echo "fixing $1"
	set_fs_owner_group_recursive "$1"
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

: ${ATL_TOMCAT_PORT:=8080}
export ATL_TOMCAT_PORT

: ${ATL_TOMCAT_SCHEME:=${CATALINA_CONNECTOR_SCHEME:-http}}
export ATL_TOMCAT_SCHEME

case "${ATL_TOMCAT_SCHEME}" in
	https) : ${CATALINA_CONNECTOR_SECURE:=true};;
	http)  : ${CATALINA_CONNECTOR_SECURE:=false};;
	*) echo 'ATL_TOMCAT_SCHEME unknown or not specified'; exit 1;;
esac
: ${ATL_TOMCAT_SECURE:=${CATALINA_CONNECTOR_SECURE}}
check_bool ATL_TOMCAT_SECURE
export ATL_TOMCAT_SECURE

: ${ATL_TOMCAT_CONTEXTPATH:=${CATALINA_CONTEXT_PATH:-}}
export ATL_TOMCAT_CONTEXTPATH

## advanced Tomcat settings

: ${ATL_TOMCAT_MGMT_PORT:=8005}
export ATL_TOMCAT_MGMT_PORT

: ${ATL_TOMCAT_MAXTHREADS:=100}
export ATL_TOMCAT_MAXTHREADS

: ${ATL_TOMCAT_MINSPARETHREADS:=10}
export ATL_TOMCAT_MINSPARETHREADS

: ${ATL_TOMCAT_CONNECTIONTIMEOUT:=20000}
export ATL_TOMCAT_CONNECTIONTIMEOUT

: ${ATL_TOMCAT_ENABLELOOKUPS:=false}
check_bool ATL_TOMCAT_ENABLELOOKUPS
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
# Jira-specific
################################################################################

: ${ATL_AUTOLOGIN_COOKIE_AGE:=1209600}
_ATL_AUTOLOGIN_COOKIE_AGE=$(sed -n -e '/<param-name>autologin\.cookie\.age</{n;s|.*<param-value>\([0-9]\+\)<.*|\1|p}' "${JIRA_INSTALL_DIR}/atlassian-jira/WEB-INF/classes/seraph-config.xml")
if [ -n "${_ATL_AUTOLOGIN_COOKIE_AGE}" ] && [ "${ATL_AUTOLOGIN_COOKIE_AGE}" != "${_ATL_AUTOLOGIN_COOKIE_AGE}" ]; then
	sed -i -e "/<param-name>autologin\.cookie\.age</{n;s|[0-9]\+|${ATL_AUTOLOGIN_COOKIE_AGE}|}" "${JIRA_INSTALL_DIR}/atlassian-jira/WEB-INF/classes/seraph-config.xml"
fi
unset ATL_AUTOLOGIN_COOKIE_AGE _ATL_AUTOLOGIN_COOKIE_AGE

################################################################################
# Database
################################################################################

DB_VARS=("${!ATL_DB_@}" "${!ATL_JDBC_@}")

if [ ${#DB_VARS[@]} -gt 0 ]; then
	case "${ATL_DB_TYPE}" in
		mssql)
			: ${ATL_DB_SCHEMA_NAME:=dbo}
			: ${ATL_DB_DRIVER:=com.microsoft.sqlserver.jdbc.SQLServerDriver}
		;;
		mysql)
			: ${ATL_DB_SCHEMA_NAME:=public}
			: ${ATL_DB_DRIVER:=com.mysql.jdbc.Driver}
		;;
		oracle10g)
			: ${ATL_DB_SCHEMA_NAME:=}
			: ${ATL_DB_DRIVER:=oracle.jdbc.OracleDriver}
		;;
		postgres72)
			: ${ATL_DB_SCHEMA_NAME:=public}
			: ${ATL_DB_DRIVER:=org.postgresql.Driver}
		;;
		h2)
			: ${ATL_DB_SCHEMA_NAME:=}
			: ${ATL_DB_DRIVER:=org.h2.Driver}
		;;
		*)
			echo 'ATL_DB_TYPE unknown or not specified'
			exit 1
		;;
	esac

	## required
	check_defined ATL_JDBC_URL
	: ${ATL_JDBC_USER:=}
	: ${ATL_JDBC_PASSWORD:=}

	## optional
	: ${ATL_DB_MAXIDLE:=20}
	: ${ATL_DB_MAXWAITMILLIS:=30000}
	: ${ATL_DB_MINEVICTABLEIDLETIMEMILLIS:=5000}
	: ${ATL_DB_MINIDLE:=10}
	: ${ATL_DB_POOLMAXSIZE:=100}
	: ${ATL_DB_POOLMINSIZE:=20}
	: ${ATL_DB_REMOVEABANDONED:=true}
	: ${ATL_DB_REMOVEABANDONEDTIMEOUT:=300}
	: ${ATL_DB_TESTONBORROW:=false}
	: ${ATL_DB_TESTWHILEIDLE:=true}
	: ${ATL_DB_TIMEBETWEENEVICTIONRUNSMILLIS:=30000}

	## undocumented
	: ${ATL_DB_VALIDATIONQUERY:=select 1}

	cat >"${JIRA_HOME}/dbconfig.xml" <<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		
		<jira-database-config>
		  <name>defaultDS</name>
		  <delegator-name>default</delegator-name>
		  <database-type>${ATL_DB_TYPE}</database-type>
		  <schema-name>$(xml_escape "${ATL_DB_SCHEMA_NAME}")</schema-name>
		  <jdbc-datasource>
		    <url>$(xml_escape "${ATL_JDBC_URL}")</url>
		    <driver-class>$(xml_escape "${ATL_DB_DRIVER}")</driver-class>
		    <username>$(xml_escape "${ATL_JDBC_USER}")</username>
		    <password>$(xml_escape "${ATL_JDBC_PASSWORD}")</password>
		    <min-evictable-idle-time-millis>$(xml_escape "${ATL_DB_MINEVICTABLEIDLETIMEMILLIS}")</min-evictable-idle-time-millis>
		    <pool-min-idle>$(xml_escape "${ATL_DB_MINIDLE}")</pool-min-idle>
		    <pool-max-idle>$(xml_escape "${ATL_DB_MAXIDLE}")</pool-max-idle>
		    <pool-min-size>$(xml_escape "${ATL_DB_POOLMINSIZE}")</pool-min-size>
		    <pool-max-size>$(xml_escape "${ATL_DB_POOLMAXSIZE}")</pool-max-size>
		    <pool-max-wait>$(xml_escape "${ATL_DB_MAXWAITMILLIS}")</pool-max-wait>
		    <pool-remove-abandoned>$(xml_escape "${ATL_DB_REMOVEABANDONED}")</pool-remove-abandoned>
		    <pool-remove-abandoned-timeout>$(xml_escape "${ATL_DB_REMOVEABANDONEDTIMEOUT}")</pool-remove-abandoned-timeout>
		    <pool-test-on-borrow>$(xml_escape "${ATL_DB_TESTONBORROW}")</pool-test-on-borrow>
		    <pool-test-while-idle>$(xml_escape "${ATL_DB_TESTWHILEIDLE}")</pool-test-while-idle>
		    <time-between-eviction-runs-millis>$(xml_escape "${ATL_DB_TIMEBETWEENEVICTIONRUNSMILLIS}")</time-between-eviction-runs-millis>
		    <validation-query>$(xml_escape "${ATL_DB_VALIDATIONQUERY}")</validation-query>
		  </jdbc-datasource>
		</jira-database-config>
	EOF

	unset "${DB_VARS[@]}"
fi

unset DB_VARS

################################################################################
# Cluster
################################################################################

: ${CLUSTERED:=false}
check_bool CLUSTERED
if [ "${CLUSTERED}" = "false" ]; then
	rm -f "${JIRA_HOME}/clusters.properties"
else
	if [ ! -v JIRA_NODE_ID ]; then
		JIRA_NODE_ID=jira-node-$(shuf --random-source=/dev/urandom -er -n12 {0..9} {a..f} | tr -d '\n')
	fi
	: ${JIRA_SHARED_HOME:=${JIRA_HOME}/shared}
	: ${EHCACHE_PEER_DISCOVERY:=default}

	cat >"${JIRA_HOME}/clusters.properties" <<-EOF
		jira.node.id=$(prop_value_escape "${JIRA_NODE_ID}")
		jira.shared.home=$(prop_value_escape "${JIRA_SHARED_HOME}")
	EOF
	if [ "${EHCACHE_PEER_DISCOVERY}" != "default" ]; then
		echo "ehcache.peer.discovery=$(prop_value_escape "${EHCACHE_PEER_DISCOVERY}")" >>"${JIRA_HOME}/clusters.properties"
	fi
	if [ "${EHCACHE_PEER_DISCOVERY}" = "automatic" ]; then
		cat >>"${JIRA_HOME}/clusters.properties" <<-EOF
			ehcache.multicast.address=$(prop_value_escape "${EHCACHE_MULTICAST_ADDRESS:-}")
			ehcache.multicast.port=$(prop_value_escape "${EHCACHE_MULTICAST_PORT:-}")
			ehcache.multicast.timeToLive=$(prop_value_escape "${EHCACHE_MULTICAST_TIMETOLIVE:-}")
			ehcache.multicast.hostName=$(prop_value_escape "${EHCACHE_MULTICAST_HOSTNAME:-}")
		EOF
	fi
	if [ -v EHCACHE_LISTENER_HOSTNAME ]; then
		echo "ehcache.listener.hostName=$(prop_value_escape "${EHCACHE_LISTENER_HOSTNAME}")" >>"${JIRA_HOME}/clusters.properties"
	fi
	if [ -v EHCACHE_LISTENER_PORT ]; then
		echo "ehcache.listener.port=$(prop_value_escape "${EHCACHE_LISTENER_PORT}")" >>"${JIRA_HOME}/clusters.properties"
	fi
	if [ -v EHCACHE_OBJECT_PORT ]; then
		echo "ehcache.object.port=$(prop_value_escape "${EHCACHE_OBJECT_PORT}")" >>"${JIRA_HOME}/clusters.properties"
	fi
	if [ -v EHCACHE_LISTENER_SOCKETTIMEOUTMILLIS ]; then
		echo "ehcache.listener.socketTimeoutMillis=$(prop_value_escape "${EHCACHE_LISTENER_SOCKETTIMEOUTMILLIS}")" >>"${JIRA_HOME}/clusters.properties"
	fi
fi

unset CLUSTERED JIRA_NODE_ID JIRA_SHARED_HOME "${!EHCACHE_@}"

################################################################################
# Start
################################################################################

export -n RUN_UID RUN_GID SET_PERMISSIONS

: ${SET_PERMISSIONS:=true}
check_bool SET_PERMISSIONS

## update RUN_UID and RUN_GID
if [ ${EUID} -ne 0 ] && [ ${RUN_UID} -eq 2001 ]; then
	RUN_UID=${EUID}
fi
EGID=$(id -g)
if [ ${EGID} -ne 0 ] && [ ${RUN_GID} -eq 2001 ]; then
	RUN_GID=${EGID}
fi

## set fs owner/group/permission
if [ "${SET_PERMISSIONS}" = "true" ]; then
	ensure_fs_owner_group_mode "${JIRA_HOME}"
	ensure_fs_owner_group_mode "${JIRA_INSTALL_DIR}/logs"
	ensure_fs_owner_group_mode "${JIRA_INSTALL_DIR}/temp"
	ensure_fs_owner_group_mode "${JIRA_INSTALL_DIR}/work"
fi

## start app
umask 027
if [ ${EUID} -eq ${RUN_UID} ] && [ ${EGID} -eq ${RUN_GID} ]; then
	exec "${JIRA_INSTALL_DIR}/bin/start-jira.sh" -fg
else
	exec gosu "${RUN_UID}:${RUN_GID}" "${JIRA_INSTALL_DIR}/bin/start-jira.sh" -fg
fi
