#/bin/bash

set -e -x

mkdir -p ~/Images
./repo_mod -o random -t "-cummins-nsfw-baby nipples" -i "~/Dropbox/PhotoRepo/Images Labelled" -i "~/Dropbox/PhotoRepo/Images Unlabelled" --link-type hard -s link_tags ~/Images
