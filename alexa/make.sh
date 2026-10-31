#!/usr/bin/env bash
# Makes ./alexa.topic once (the secret relay topic, gitignored) and alexa/out/index.js: the skill
# code with that topic filled in, to paste into the Alexa developer console. Rebuild the TV app
# after the topic changes (it's built in from ./alexa.topic).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -s alexa.topic ] || { echo "onetv-$(openssl rand -hex 16)" > alexa.topic; chmod 600 alexa.topic; echo "› New topic in alexa.topic"; }
mkdir -p alexa/out
sed "s/__ALEXA_TOPIC__/$(tr -d ' \n' < alexa.topic)/" alexa/lambda/index.js > alexa/out/index.js
echo "› alexa/out/index.js ready (contains the secret: don't share or commit it)"
