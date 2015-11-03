#!/usr/bin/env bash

# preprocess using texpp
TEXPP_DIRS="."
TEXPP_DIRS="$HOME/segfs/repo/texpp $TEXPP_DIRS"
TEXPP_DIRS="/segfs/linux/dance_sdk/tools $TEXPP_DIRS"
for d in $TEXPP_DIRS; do
 p="$d/texpp.py"
 if [ -e $p ]; then
  TEXPP_PATH=$p
  break
 fi
done

if [ -z "$TEXPP_PATH" ]; then
 echo 'texpp not found'
 exit -1
fi

$TEXPP_PATH main.tex main.pp.tex > main.pp.tex

# create version.tex
echo -n '\newcommand{\version}{SVN revision ' > version.tex
(svnversion -c -n || echo none) >> version.tex
echo -n '}' >> version.tex

texi2pdf main.pp.tex
mv main.pp.pdf main.pdf
