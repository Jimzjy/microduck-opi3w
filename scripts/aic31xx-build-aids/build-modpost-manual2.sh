#!/bin/bash
# Regenerate devicetable-offsets.h correctly and build modpost
set -e
M=/root/hdr/usr/src/linux-headers-6.6.98-vendor-sun60iw2/scripts/mod
cd "$M"
{
  echo '/* Automatically generated. */'
  echo '#ifndef __DEVICETABLE_OFFSETS_H__'
  echo '#define __DEVICETABLE_OFFSETS_H__'
  grep -o '"->[^"]*"' devicetable-offsets.s | tr -d '"' | sed 's/\\n//g' \
    | awk '{printf "#define %s %s /* %s */\n", substr($1,3), $2, $3}'
  echo ''
  echo '#endif /* __DEVICETABLE_OFFSETS_H__ */'
} > devicetable-offsets.h
head -6 devicetable-offsets.h; wc -l devicetable-offsets.h

gcc -O2 -Wall -o modpost modpost.c file2alias.c sumversion.c symsearch.c -I"$M"
ls -la modpost
