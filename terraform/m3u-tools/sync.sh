#!/bin/bash

rsync -avz --progress --include '*.py' --include '*.ini' --exclude '*' --rsync-path="sudo -u hashi rsync" . matt@jerry.shamsway.net:/mnt/services/iptvtools/