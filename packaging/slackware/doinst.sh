#!/bin/sh

if [ -x /sbin/udevadm ]; then
    /sbin/udevadm control --reload-rules || true
fi
