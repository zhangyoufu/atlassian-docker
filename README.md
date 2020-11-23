# Overview

This repo is a drop-in replacement for [atlassian/jira-software](https://hub.docker.com/r/atlassian/jira-software) and [atlassian/confluence-server](https://hub.docker.com/r/atlassian/confluence-server/) Docker image.

Use environment variables as property source, and reference them from Tomcat server.xml, without relying on Jinja2 templates.

# Supported tags

## Jira Software

* `8.14.0`, `8.14`, `8`
* `8.13.1`, `8.13`
* `8.12.3`, `8.12`
* `8.11.1`, `8.11`
* `8.10.1`, `8.10`
* `8.9.1`, `8.9`

## Confluence

* `7.10.0-m32`, `7.10`
* `7.10.0-xstream-14-m03`, `7.10-xstream-14`
* `7.9.0`, `7.9`, `7`
* `7.8.3`, `7.8`
* `7.7.4`, `7.7`
* `7.6.2`, `7.6`
* `7.5.2`, `7.5`
* `7.4.5`, `7.4`

# Usage

Please consult official repo:

* [atlassian/jira-software](https://hub.docker.com/r/atlassian/jira-software/)
* [atlassian/confluence-server](https://hub.docker.com/r/atlassian/confluence-server/)

Note: some punctuations (`&<>"'`), control characters and Unicode characters need to be encoded as XML entities manually.

# Unsupported features

## Confluence

* ATL_TOMCAT_ACCESS_LOG
* ATL_TOMCAT_PROXY_INTERNAL_IPS

# Note

## for Confluence Data Center cluster

If you want to reconfigure database or cluster, make sure you specified both database and cluster related environment variables, which are required to regenerate confluence.cfg.xml from scratch.
