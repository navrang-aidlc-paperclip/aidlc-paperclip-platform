#!/bin/sh
# Hands straight off to Paperclip's entrypoint. Project checkouts are added
# later, one Paperclip project at a time; this image does not create a
# workspace directory or clone a repository.
set -e
exec /usr/local/bin/docker-entrypoint.sh "$@"
