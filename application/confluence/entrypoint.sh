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

: ${ATL_TOMCAT_PORT:=8090}
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

: ${ATL_TOMCAT_MGMT_PORT:=8000}
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
# Confluence-specific
################################################################################

: ${ATL_AUTOLOGIN_COOKIE_AGE:=1209600}
_ATL_AUTOLOGIN_COOKIE_AGE=$(sed -n -e '/<param-name>autologin\.cookie\.age</{n;s|.*<param-value>\([0-9]\+\)<.*|\1|p}' "${CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/seraph-config.xml")
if [ -n "${_ATL_AUTOLOGIN_COOKIE_AGE}" ] && [ "${ATL_AUTOLOGIN_COOKIE_AGE}" != "${_ATL_AUTOLOGIN_COOKIE_AGE}" ]; then
	sed -i -e "/<param-name>autologin\.cookie\.age</{n;s|[0-9]\+|${ATL_AUTOLOGIN_COOKIE_AGE}|}" "${CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/classes/seraph-config.xml"
fi
unset ATL_AUTOLOGIN_COOKIE_AGE _ATL_AUTOLOGIN_COOKIE_AGE

################################################################################
# confluence.cfg.xml begin
################################################################################

config() {
	cat >>"${CONFLUENCE_HOME}/confluence.cfg.xml.new"
}

remove() {
	rm -f "${CONFLUENCE_HOME}/confluence.cfg.xml.new"
}

remove
trap remove EXIT

config <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<confluence-configuration>
  <properties>
EOF

_RECONFIGURE=false

################################################################################
# Setup
################################################################################

if [ -v CONFLUENCE_SETUP_SERVER_ID ]; then
	config <<-EOF
	    <property name="confluence.setup.server.id">$(xml_escape "${CONFLUENCE_SETUP_SERVER_ID}")</property>
	EOF
	unset CONFLUENCE_SETUP_SERVER_ID
fi

################################################################################
# Database
################################################################################

DB_VARS=("${!ATL_DB_@}" "${!ATL_JDBC_@}")
if [ ${#DB_VARS[@]} -gt 0 ]; then
	case "${ATL_DB_TYPE}" in
		mssql)
			ATL_DB_DRIVER=com.microsoft.sqlserver.jdbc.SQLServerDriver
			ATL_DB_DIALECT=SQLServerDialect
		;;
		mysql)
			ATL_DB_DRIVER=com.mysql.jdbc.Driver
			ATL_DB_DIALECT=MySQLDialect
		;;
		oracle12c)
			ATL_DB_DRIVER=oracle.jdbc.driver.OracleDriver
			ATL_DB_DIALECT=OracleDialect
		;;
		postgresql)
			ATL_DB_DRIVER=org.postgresql.Driver
			ATL_DB_DIALECT=PostgreSQLDialect
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
	: ${ATL_DB_POOLMINSIZE:=20}
	: ${ATL_DB_POOLMAXSIZE:=100} # wizard default: 60
	: ${ATL_DB_TIMEOUT:=30}
	: ${ATL_DB_IDLETESTPERIOD:=100}
	: ${ATL_DB_MAXSTATEMENTS:=0}
	: ${ATL_DB_VALIDATE:=false}
	: ${ATL_DB_ACQUIREINCREMENT:=1}
	: ${ATL_DB_VALIDATIONQUERY:=select 1}

	config <<-EOF
	    <property name="hibernate.c3p0.acquire_increment">$(xml_escape "${ATL_DB_ACQUIREINCREMENT}")</property>
	    <property name="hibernate.c3p0.idle_test_period">$(xml_escape "${ATL_DB_IDLETESTPERIOD}")</property>
	    <property name="hibernate.c3p0.max_size">$(xml_escape "${ATL_DB_POOLMAXSIZE}")</property>
	    <property name="hibernate.c3p0.max_statements">$(xml_escape "${ATL_DB_MAXSTATEMENTS}")</property>
	    <property name="hibernate.c3p0.min_size">$(xml_escape "${ATL_DB_POOLMINSIZE}")</property>
	    <property name="hibernate.c3p0.preferredTestQuery">$(xml_escape "${ATL_DB_VALIDATIONQUERY}")</property>
	    <property name="hibernate.c3p0.timeout">$(xml_escape "${ATL_DB_TIMEOUT}")</property>
	    <property name="hibernate.c3p0.validate">$(xml_escape "${ATL_DB_VALIDATE}")</property>
	    <property name="hibernate.connection.driver_class">${ATL_DB_DRIVER}</property>
	    <property name="hibernate.connection.password">$(xml_escape "${ATL_JDBC_PASSWORD}")</property>
	    <property name="hibernate.connection.url">$(xml_escape "${ATL_JDBC_URL}")</property>
	    <property name="hibernate.connection.username">$(xml_escape "${ATL_JDBC_USER}")</property>
	    <property name="hibernate.dialect">com.atlassian.confluence.impl.hibernate.dialect.${ATL_DB_DIALECT}</property>
	EOF
	_RECONFIGURE=true

	unset "${DB_VARS[@]}"
fi

unset DB_VARS

################################################################################
# Cluster
################################################################################

CLUSTER_VARS=("${!ATL_CLUSTER_@}" "${!ATL_HAZELCAST_@}")
if [ ${#CLUSTER_VARS[@]} -gt 0 ] || [ -v ATL_PRODUCT_HOME_SHARED ] || [ -v CONFLUENCE_SHARED_HOME ]; then
	if [ "${_RECONFIGURE}" != "true" ]; then
		echo 'database related environment variables are required to regenerate confluence.cfg.xml'
		exit 1
	fi

	config <<-EOF
	    <property name="confluence.cluster">true</property>
	EOF

	# the only reference to shared-home property is com.atlassian.confluence.setup.actions.SetupClusterAction.doDefault()
	: ${ATL_PRODUCT_HOME_SHARED:=${CONFLUENCE_SHARED_HOME:${CONFLUENCE_HOME}/shared-home}}
	config <<-EOF
	    <property name="confluence.cluster.home">$(xml_escape "${ATL_PRODUCT_HOME_SHARED}")</property>
	    <property name="shared-home">$(xml_escape "${ATL_PRODUCT_HOME_SHARED}")</property>
	EOF

	check_defined ATL_CLUSTER_NAME
	config <<-EOF
	    <property name="confluence.cluster.name">$(xml_escape "${ATL_CLUSTER_NAME}")</property>
	EOF

	if [ -v ATL_CLUSTER_NODE_NAME ]; then
		config <<-EOF
		    <property name="confluence.cluster.node.name">$(xml_escape "${ATL_CLUSTER_NODE_NAME}")</property>
		EOF
	fi

	config <<-EOF
	    <property name="confluence.cluster.join.type">$(xml_escape "${ATL_CLUSTER_TYPE}")</property>
	EOF
	if [ -v ATL_CLUSTER_INTERFACE ]; then
		config <<-EOF
		    <property name="confluence.cluster.interface">$(xml_escape "${ATL_CLUSTER_INTERFACE}")</property>
		EOF
	fi
	case "${ATL_CLUSTER_TYPE}" in
		multicast)
			BAD_VARS=("${!ATL_HAZELCAST_@}")
			[ -v ATL_CLUSTER_PEERS ] && BAD_VARS+=(ATL_CLUSTER_PEERS)

			config <<-EOF
			    <property name="confluence.cluster.address">$(xml_escape "${ATL_CLUSTER_ADDRESS}")</property>
			    <property name="confluence.cluster.ttl">$(xml_escape "${ATL_CLUSTER_TTL}")</property>
			EOF
		;;
		tcp_ip)
			BAD_VARS=("${!ATL_HAZELCAST_@}")
			[ -v ATL_CLUSTER_ADDRESS ] && BAD_VARS+=(ATL_CLUSTER_ADDRESS)
			[ -v ATL_CLUSTER_TTL ] && BAD_VARS+=(ATL_CLUSTER_TTL)

			config <<-EOF
			    <property name="confluence.cluster.peers">$(xml_escape "${ATL_CLUSTER_PEERS}")</property>
			EOF
		;;
		aws)
			BAD_VARS=()
			[ -v ATL_CLUSTER_ADDRESS ] && BAD_VARS+=(ATL_CLUSTER_ADDRESS)
			[ -v ATL_CLUSTER_PEERS ] && BAD_VARS+=(ATL_CLUSTER_PEERS)
			[ -v ATL_CLUSTER_TTL ] && BAD_VARS+=(ATL_CLUSTER_TTL)

			# https://github.com/hazelcast/hazelcast-aws
			if [ -v ATL_HAZELCAST_NETWORK_AWS_IAM_ROLE ]; then
				config <<-EOF
				    <property name="confluence.cluster.aws.iam.role">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_IAM_ROLE}")</property>
				EOF
			else
				check_defined ATL_HAZELCAST_NETWORK_AWS_ACCESS_KEY
				check_defined ATL_HAZELCAST_NETWORK_AWS_SECRET_KEY
				config <<-EOF
				    <property name="confluence.cluster.aws.access.key">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_ACCESS_KEY}")</property>
				    <property name="confluence.cluster.aws.secret.key">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_SECRET_KEY}")</property>
				EOF
			fi
			config <<-EOF
			    <property name="confluence.cluster.aws.region">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_IAM_REGION}")</property>
			    <property name="confluence.cluster.aws.host.header">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_HOST_HEADER}")</property>
			    <property name="confluence.cluster.aws.security.group.name">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_SECURITY_GROUP}")</property>
			    <property name="confluence.cluster.aws.tag.key">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_TAG_KEY}")</property>
			    <property name="confluence.cluster.aws.tag.value">$(xml_escape "${ATL_HAZELCAST_NETWORK_AWS_TAG_VALUE}")</property>
			EOF
		;;
		*)
			echo 'ATL_CLUSTER_TYPE unknown or not specified'
			exit 1
		;;
	esac

	if [ ${#BAD_VARS[@]} -gt 0 ]; then
		echo "unexpected environment variable: ${BAD_VARS[@]}"
		exit 1
	fi
	unset BAD_VARS

	# ATL_PRODUCT_HOME_SHARED is referenced below
	unset "${CLUSTER_VARS[@]}" CONFLUENCE_SHARED_HOME
fi

unset CLUSTER_VARS

################################################################################
# confluence.cfg.xml end
################################################################################

if [ "${_RECONFIGURE}" = "true" ]; then
	config <<-EOF
	  </properties>
	</confluence-configuration>
	EOF
	mv "${CONFLUENCE_HOME}/confluence.cfg.xml.new" "${CONFLUENCE_HOME}/confluence.cfg.xml"
fi
unset _RECONFIGURE
trap - EXIT

################################################################################
# Start
################################################################################

export -n RUN_UID RUN_GID SET_PERMISSIONS

: ${SET_PERMISSIONS:=true}
check_bool SET_PERMISSIONS

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
	ensure_fs_owner_group_mode "${ATL_PRODUCT_HOME_SHARED}"
fi
unset ATL_PRODUCT_HOME_SHARED

## start app
umask 027
if [ ${EUID} -eq ${RUN_UID} ] && [ ${EGID} -eq ${RUN_GID} ]; then
	exec "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh" -fg
else
	exec gosu "${RUN_UID}:${RUN_GID}" "${CONFLUENCE_INSTALL_DIR}/bin/start-confluence.sh" -fg
fi
