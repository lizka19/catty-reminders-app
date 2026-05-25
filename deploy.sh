#!/bin/bash

set -e

cd /home/vboxuser/catty-reminders-app

HASH="$1"

if [ -z "$HASH" ]; then
    exit 1
fi

git fetch origin
git checkout "$HASH"

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

python3 -m playwright install chromium

if ! python3 -m pytest tests/; then
    git checkout -
    sudo systemctl restart catty
    exit 1
fi

echo "DEPLOY_REF=$HASH" > .env

sudo systemctl restart catty
