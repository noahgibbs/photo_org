# Photo Organiser

This is a little photo organisation program I'm writing for my own use.
I'm an enthusiastic amateur photographer with my little iPhone (and several
previous phones.) And I like showing pictures of my family on my backgrounds
and screensavers.

We've hit the point where there are enough situations and categories
and we often want just some specific chunks of the massive number of
photos. That can be work vs home desktop background, dead pets we
don't necessarily want to be reminded of during fast-rotation
screensavers, or even just wanting some "theme" as if the screensaver
were a music playlist.

The idea here is that you can run the organiser program on a set of
directories that tag the photos in different ways. The tags could be
where they were taken or who is in them, for instance. And you can
specify that certain tags are mandatory (only those photos) or
excluded (not those photos.) The organiser can then produce a
directory of links to the appropriate photos suitable for a
screensaver program or a directory of desktop images.

## Link Types

Symbolic links make me more comfortable than hard links... But the Mac
screensaver program doesn't recognize symlinked images, so you have to
use hard links. You can also use the "test" link type to just print a
message instead of making a real link.

## Saved Incantation for Making a Repo

Turn an empty directory at ~/Dropbox/PhotoRepo/output/Shanna_Orion/
into a new photo repo for photos with multiple Shanna- or
Orion-related tags and no "baby nipples" or "nsfw" tag, using hard
links.

* ./repo_mod ~/Dropbox/PhotoRepo/output/Shanna_Orion/ -i ~/Dropbox/PhotoRepo/Images\ Labeled -b "shanna|orion|orion pregnancy" -t "-baby nipples-nsfw" -l hard

## Saved Incantation for Later Implementation Work:

* for file in *; do SetFile -m "$(exiftool -p '$CreateDate' -d '%m/%d/%Y %H:%M:%S'"$file")""$file"; done

Related: use exiftool?
