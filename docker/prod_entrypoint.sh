#!/bin/sh

if [ "$SEPARATE_HEALTH_APP" = "1" ]; then
    export LITELLM_ARGS="$@"
    exec supervisord -c /etc/supervisord.conf
fi

litellm_exec_args="$@"

# Fly Machines currently invoke this entrypoint as
#   docker/prod_entrypoint.sh /usr/bin/litellm ...
# which causes the litellm CLI to see "/usr/bin/litellm" as an
# unexpected extra argument. Detect and strip that leading token so the
# CLI receives only the intended flags.
if [ "$1" = "/usr/bin/litellm" ] || [ "$1" = "litellm" ]; then
    shift
fi

if [ "$USE_DDTRACE" = "true" ]; then
    export DD_TRACE_OPENAI_ENABLED="False"
    exec ddtrace-run litellm "$@"
else
    exec litellm "$@"
fi