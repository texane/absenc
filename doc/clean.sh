#!/usr/bin/env bash

for f in main.{aux,bbl,blg,log,toc}; do
 [ -e $f ] && rm $f;
done

for f in main.pp.{tex,aux,bbl,blg,log,toc}; do
 [ -e $f ] && rm $f;
done

for f in version.{tex,tex.aux}; do
 [ -e $f ] && rm $f;
done
