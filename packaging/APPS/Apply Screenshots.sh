#!/bin/sh

progdir=$(dirname "$0")/nimshot
cd $progdir
HOME=$progdir

./nimshot convert
sync
