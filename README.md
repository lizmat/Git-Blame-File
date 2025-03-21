[![Actions Status](https://github.com/lizmat/Git-Blame-File/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/Git-Blame-File/actions) [![Actions Status](https://github.com/lizmat/Git-Blame-File/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/Git-Blame-File/actions) [![Actions Status](https://github.com/lizmat/Git-Blame-File/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/Git-Blame-File/actions)

NAME
====

Git::Blame::File - Who did what and when on a file in a Git repository

SYNOPSIS
========

```raku
use Git::Blame::File;

my $blamer = Git::Blame::File.new("xt/target");
say $blamer.lines[2];  # show line #3
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line

.say for Git::Blame::File.new("xt/target", :line-numbers(2,4)).lines
#c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 2) This became the second line.
#77877dbc (Elizabeth Mattijsen 2022-07-27 20:39:29 +0200 4) This is the second line.
```

DESCRIPTION
===========

Git::Blame::File is a module that uses `git blame` to extract information from a single file in a Git repository. It processes the `git blame` information into `Git::Blame::Line` objects, while also keeping track of commits in `Git::Blame::Commit` objects.

Stringifies to the filename specified.

METHODS ON Git::Blame::File
===========================

new
---

```raku
my $blamer = Git::Blame::File.new: "t/target";
```

The `new` method either takes a single positional argument as the filename or the `IO::Path` object of which to obtain `git blame` information.

It can also be called with a `:file` named argument, and an optional `:commits` argument. The latter is intended for a future `Git::Blame::Repository` module that would potentially contain all `git blame` information of a repository.

Finally, it can also be called with an optional `:line-numbers` named argument, which should contain the line numbers (in ascending order) of which to obtain blame information. The `.lines` method will then iterate over the blame information of these line numbers.

lines
-----

Returns an `Array` with all the lines (as `Git::Blame::Line` objects) in the file. Note that these are 0-based, whereas line numbers are typically 1-based.

```raku
say $blamer.lines[2];  # show line #3
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line
```

authors
-------

Returns a list of unique `author`s of this file.

commits
-------

Returns a `Map` of all the commits that were seen for this file (and potentially other files in the future. Keyed to the `sha1` of the commit, and having a `Git::Blame::Commit` object as a value.

created
-------

Returns a `DateTime` object when this file was created, according to the oldest `author-time` information. Note that if no lines of the first commit exist in the file, this may actually be later.

modified
--------

Returns a `DateTime` object when this file was last modified, according to the newest `committer-time` information.

file
----

The file from which the `git blame` information was obtained.

ACCESSORS ON Git::Blame::Line
=============================

Note that `Git::Blame::Line` objects are created automatically by `Git::Blame::File.new`.

  * author - the name of the author of this line

  * author-mail - the email address of the author of this line

  * author-time - a DateTime object for the authoring of this line

  * commit - the associated Git::Blame::Commit object

  * committed - whether this line has actually been committed

  * committer - the name of the committer of this line

  * committer-mail - the email address of the committer of this line

  * committer-time - a DateTime object for the committing of this line

  * filename - the current filename

  * line - the actual line currently

  * line-number - the current line-number

  * original-line-number - line number when this line was created

  * previous-sha1 - the full SHA1 of the previous commit of this line

  * previous-sha - the shortened SHA1 of the previous commit of this line

  * previous-filename - the filename in the previous commit of this line

  * sha1 - the full SHA1 of the commit to which this line belongs

  * sha - the shortened SHA1 of the commit to which this line belongs

  * summary - the first line of the commit message of this line

ACCESSORS ON Git::Blame::Commit
===============================

Note that `Git::Blame::Commit` objects are created automatically by `Git::Blame::File.new`.

  * author - the name of the author of this commit

  * author-mail - the email address of the author of this commit

  * author-time - a DateTime object for the authoring of this commit

  * blames - a list of Git::Blame::Line objects of this commit

  * committed - whether it has actually been committed

  * committer - the name of the committer of this commit

  * committer-mail - the email address of the committer of this commit

  * committer-time - a DateTime object for the committing of this commit

  * previous-sha1 - the full SHA1 of the previous commit

  * previous-sha - the shortened SHA1 of the previous commit

  * previous-filename - the filename in the previous commit

  * sha1 - the full SHA1 of the commit

  * sha - the shortened SHA1 of the commit

  * summary - the first line of the commit message

AUTHORS
=======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Git-Blame-File . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2022, 2024, 2025 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

