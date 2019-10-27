#/bin/bash

set -e -x

mkdir -p ~/Images
./repo_mod -o random -t "-cummins-nsfw-baby nipples" -i "~/Dropbox/Images Labelled" -i "~/Dropbox/Images Unlabelled" --link-type hard -s link_tags ~/Images
