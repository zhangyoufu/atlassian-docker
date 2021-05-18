# Overview

This repo is a drop-in replacement for [atlassian/jira-software](https://hub.docker.com/r/atlassian/jira-software) and [atlassian/confluence-server](https://hub.docker.com/r/atlassian/confluence-server/) Docker image.

Use environment variables as property source, and reference them from Tomcat server.xml, without relying on Jinja2 templates.

# Supported tags

## Jira Software

* `8.17.0-RC02`, `8.17`
* `8.16.1`, `8.16`, `8`
* `8.15.1`, `8.15`
* `8.14.1`, `8.14`
* `8.13.6`, `8.13`

## Confluence

* `7.13.0-m06`, `7.13`
* `7.12.1`, `7.12`, `7`
* `7.11.3`, `7.11`
* `7.10.2`, `7.10`
* `7.9.3`, `7.9`
* `7.8.3`, `7.8`
* `7.7.4`, `7.7`
* `7.6.3`, `7.6`
* `7.5.2`, `7.5`
* `7.4.8`, `7.4`

# Usage

Please consult official repo:

* [atlassian/jira-software](https://hub.docker.com/r/atlassian/jira-software/)
* [atlassian/confluence-server](https://hub.docker.com/r/atlassian/confluence-server/)

Note: some punctuations (`&<>"'`), control characters and Unicode characters need to be encoded as XML entities manually.

# Unsupported features

## Confluence

* ATL_TOMCAT_ACCESS_LOG
* ATL_TOMCAT_PROXY_INTERNAL_IPS
