[![Actions Status](https://github.com/lizmat/Git-Blame-File/actions/workflows/test.yml/badge.svg)](https://github.com/lizmat/Git-Blame-File/actions)

NAME
====

Git::Blame::File - Who did what and when on a file in a Git repository

SYNOPSIS
========

```raku
use Git::Blame::File;

my $blamer = Git::Blame::File.new( "t/target" );
say $blamer.lines[3];
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line
```

DESCRIPTION
===========

Git::Blame is a module that uses `git blame` to extract information from a single file in a Git repository and process it in a number of ways. It's mainly geared to tally contributions via lines changed, but it can also be modified and used to do some repository mining.

It works, for the time being, with single files.

METHODS
=======

lines()
-------

Returns an Array with all the lines in the file (1-based).

AUTHORS
=======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Git-Blame-File . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2022 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

