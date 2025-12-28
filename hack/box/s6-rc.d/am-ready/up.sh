#!/bin/sh
set -e
# Wait for SS and Dashboard HTTP endpoints
/usr/local/bin/wait-http.sh http://127.0.0.1:8001/ 60 0.5
/usr/local/bin/wait-http.sh http://127.0.0.1:8002/ 60 0.5
