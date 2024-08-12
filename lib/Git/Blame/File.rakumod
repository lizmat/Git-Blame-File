use path-utils:ver<0.0.20>:auth<zef:lizmat> <path-git-repo>;

my sub datetimize(Int() $epoch, $offset --> DateTime:D) {
    my int $timezone = $offset.substr(0,3).Int * 3600;
    my int $minutes  = $offset.substr(3).Int;
    $timezone += 60 * ($timezone < 0 ?? -$minutes !! $minutes);
    DateTime.new: $epoch, :$timezone, :formatter({
        my int $tz = .timezone;
        sprintf '%4d-%02d-%02d %2d:%02d:%02d %s%02d%02d',
          .year, .month, .day, .hour, .minute, .second,
          $tz < 0 ?? '-' !! '+',
          $tz.abs div 3600,
          ($tz.abs mod 3600) div 60
    })
}

my sub shortened-sha($sha) { $sha.substr(0,8) }

# Gather common information about a commit
class Git::Commit {
    has Str      $.sha1;
    has Str      $.author;
    has Str      $.author-mail;
    has Str      $.committer;
    has Str      $.committer-mail;
    has Str      $.summary;
    has Str      $.previous-sha1;
    has Str      $.previous-filename;
    has DateTime $.author-time;
    has DateTime $.committer-time;
    has          $!lock;
    has          %!blames;

    submethod TWEAK(:$filename --> Nil) {
        $!lock := Lock.new;
        %!blames{$filename} = [];
    }

    method add-blame($blame) {
        $!lock.protect: {
            %!blames{$blame.filename}.push: $blame;
        }
    }

    method blames()       { %!blames.Map                  }
    method sha()          { shortened-sha $!sha1          }
    method previous-sha() { shortened-sha $!previous-sha1 }
    method committed()    { $!sha1 ne '0' x 40            }
}

# Information about a single line of blame
class Git::Blame::Line {
    has Int         $.line-number,
    has Int         $.original-line-number,
    has Str         $.filename;
    has Str         $.line;
    has Git::Commit $.commit handles <sha sha1 author author-mail
      committed committer committer-mail summary previous
      author-time committer-time>;

    method Str() {
        "$.sha ($.author $.author-time "
          ~ $!line-number  # for now
#          ~ sprintf('%4d',$!line-number)  # need to figure out width
          ~ ") $!line"
    }
    method gist() { self.Str }
}

# All the blame information about a single file
class Git::Blame::File {
    has $.file;
    has @.lines is built(False);
    has %!commits;
    has DateTime $!created;
    has DateTime $!modified;

    multi method new(Git::Blame::File: $file --> Git::Blame::File:D) {
        self.bless: :$file, :commits(Hash.new), |%_
    }

    submethod TWEAK(:$commits is raw, :@line-numbers) {
        %!commits := $commits;

        # Fetch any specific line numbers to get
        my @sets := do if @line-numbers {
            my $sets := IterationBuffer.new;
            my int $last-seen;
            my int $start;
            for @line-numbers -> int $_ {
                if $last-seen {
                    if $_ > $last-seen + 1 {
                        $sets.push: "-L$start,$last-seen";
                        $last-seen = $start = $_;
                    }
                    else {
                        ++$last-seen;
                    }
                }
                else {
                    $last-seen = $start = $_;
                }
            }
            $sets.push: "-L$start,$last-seen";
            $sets.List
        }

        fail "Could not find Git repo for '$!file'"
          unless my $repo := path-git-repo($!file.IO.resolve.absolute);

        my $proc := indir $repo, {
            run <git blame --porcelain>,
              @sets, $!file.IO.resolve.relative, :out, :err;
        }
        my $iterator := $proc.out.lines.iterator;

        my $sha1;
        my $filename;
        my $commit;
        my Int() $todo;
        my Int() $original-line-number;
        my Int() $line-number;

        my $lines := IterationBuffer.new;
        until (my $porcelain := $iterator.pull-one) =:= IterationEnd {

            # still in a chunk
            if $todo {
                ($sha1, $original-line-number, $line-number) =
                  $porcelain.words;
                $porcelain := $iterator.pull-one;
                die "weird end" unless $porcelain.starts-with("\t");

                $commit = %!commits{$sha1}
                  // die "No commit for '$sha1' found";
            }

            # first chunk or chunk ended
            else {
                ($sha1, $original-line-number, $line-number, $todo) =
                  $porcelain.words;

                # commit seen before
                with %!commits{$sha1} {
                    $commit = $_;
                    $porcelain := $iterator.pull-one;
                    die "weird end" unless $porcelain.starts-with("\t");
                }

                # new commit
                else {
                    my %fields;
                    until ($porcelain := $iterator.pull-one) =:= IterationEnd
                      || $porcelain.starts-with("\t") {
                        my ($key, $value) = $porcelain.split(" ", 2);
                        %fields{$key} := $value;
                    }
                    die "unexpected end" unless $porcelain.starts-with("\t");

                    with %fields<author-time> {
                        $_ = datetimize $_, %fields<author-tz>:delete;
                    }
                    with %fields<committer-time> {
                        $_ = datetimize $_, %fields<committer-tz>:delete;
                    }
                    with %fields<previous>:delete {
                        %fields<previous-sha1 previous-filename> = .words;
                    }
                    $filename = %fields<filename>;
                    $commit = %!commits{$sha1} :=
                      Git::Commit.new: :$sha1, |%fields;
                }
            }

            # all ready to process this line of blame
            my $blame := Git::Blame::Line.new:
              :line($porcelain.substr(1)),  # skip TAB
              :$sha1, :$original-line-number, :$line-number,
              :$filename, :$commit;
            $commit.add-blame: $blame;
            $lines.push: $blame;
            --$todo;
        }

        # too bad if something went wrong
        if $proc.err.slurp -> $error {
            Failure.new: $error
        }
        else {
            @!lines := $lines.List
        }
    }

    method commits(Git::Blame::File:D:) {
        %!commits.Map
    }
    method authors(Git::Blame::File:D:) {
        %!commits.values.map({.author if .committed}).unique
    }

    multi method Str(Git::Blame::File:D:) { $!file }

    method created() {
        $!created //= %!commits.values.map(*.author-time).sort.head;
    }
    method modified() {
        $!modified //= %!commits.values.map(*.committer-time).sort.tail;
    }
}

=begin pod

=head1 NAME

Git::Blame::File - Who did what and when on a file in a Git repository

=head1 SYNOPSIS

=begin code :lang<raku>

use Git::Blame::File;

my $blamer = Git::Blame::File.new("xt/target");
say $blamer.lines[2];  # show line #3
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line

.say for Git::Blame::File.new("xt/target", :line-numbers(2,4)).lines
#c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 2) This became the second line.
#77877dbc (Elizabeth Mattijsen 2022-07-27 20:39:29 +0200 4) This is the second line.

=end code

=head1 DESCRIPTION

Git::Blame::File is a module that uses C<git blame> to extract information
from a single file in a Git repository.  It processes the C<git blame>
information into C<Git::Blame::Line> objects, while also keeping track
of commits in C<Git::Blame::Commit> objects.

Stringifies to the filename specified.

=head1 METHODS ON Git::Blame::File

=head2 new

=begin code :lang<raku>

my $blamer = Git::Blame::File.new: "t/target";

=end code

The C<new> method either takes a single positional argument as the
filename or the C<IO::Path> object of which to obtain C<git blame>
information.

It can also be called with a C<:file> named argument, and an
optional C<:commits> argument.  The latter is intended for a future
C<Git::Blame::Repository> module that would potentially contain
all C<git blame> information of a repository.

Finally, it can also be called with an optional C<:line-numbers>
named argument, which should contain the line numbers (in ascending
order) of which to obtain blame information.  The C<.lines> method
will then iterate over the blame information of these line numbers.

=head2 lines

Returns an C<Array> with all the lines (as C<Git::Blame::Line> objects)
in the file.  Note that these are 0-based, whereas line numbers are
typically 1-based.

=begin code :lang<raku>

say $blamer.lines[2];  # show line #3
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line

=end code

=head2 authors

Returns a list of unique C<author>s of this file.

=head2 commits

Returns a C<Map> of all the commits that were seen for this file (and
potentially other files in the future.  Keyed to the C<sha1> of the
commit, and having a C<Git::Blame::Commit> object as a value.

=head2 created

Returns a C<DateTime> object when this file was created, according to
the oldest C<author-time> information.  Note that if no lines of the
first commit exist in the file, this may actually be later.

=head2 modified

Returns a C<DateTime> object when this file was last modified, according
to the newest C<committer-time> information.

=head2 file

The file from which the C<git blame> information was obtained.
 
=head1 ACCESSORS ON Git::Blame::Line

Note that C<Git::Blame::Line> objects are created automatically by
C<Git::Blame::File.new>.

=item author - the name of the author of this line
=item author-mail - the email address of the author of this line
=item author-time - a DateTime object for the authoring of this line
=item commit - the associated Git::Blame::Commit object
=item committed - whether this line has actually been committed
=item committer - the name of the committer of this line
=item committer-mail - the email address of the committer of this line
=item committer-time - a DateTime object for the committing of this line
=item filename - the current filename
=item line - the actual line currently
=item line-number - the current line-number
=item original-line-number - line number when this line was created
=item previous-sha1 - the full SHA1 of the previous commit of this line
=item previous-sha - the shortened SHA1 of the previous commit of this line
=item previous-filename - the filename in the previous commit of this line
=item sha1 - the full SHA1 of the commit to which this line belongs
=item sha - the shortened SHA1 of the commit to which this line belongs
=item summary - the first line of the commit message of this line

=head1 ACCESSORS ON Git::Blame::Commit

Note that C<Git::Blame::Commit> objects are created automatically by
C<Git::Blame::File.new>.

=item author - the name of the author of this commit
=item author-mail - the email address of the author of this commit
=item author-time - a DateTime object for the authoring of this commit
=item blames - a list of Git::Blame::Line objects of this commit
=item committed - whether it has actually been committed
=item committer - the name of the committer of this commit
=item committer-mail - the email address of the committer of this commit
=item committer-time - a DateTime object for the committing of this commit
=item previous-sha1 - the full SHA1 of the previous commit
=item previous-sha - the shortened SHA1 of the previous commit
=item previous-filename - the filename in the previous commit
=item sha1 - the full SHA1 of the commit
=item sha - the shortened SHA1 of the commit
=item summary - the first line of the commit message

=head1 AUTHORS

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Git-Blame-File .
Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

=head1 COPYRIGHT AND LICENSE

Copyright 2022, 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
