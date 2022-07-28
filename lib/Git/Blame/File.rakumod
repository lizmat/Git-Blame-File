my sub datetimize(Int() $epoch, $offset --> DateTime:D) {
    my int $hour    = $offset.substr(0,3).Int;
    my int $minutes = $offset.substr(3).Int;
    my int $timezone = $hour * 3600;
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
    has Str      $.sha;
    has Str      $.author;
    has Str      $.author-mail;
    has Str      $.committer;
    has Str      $.committer-mail;
    has Str      $.summary;
    has Str      $.previous-sha;
    has Str      $.previous-filename;
    has DateTime $.author-time;
    has DateTime $.committer-time;
    has          $!lock;
    has          %!blames;

    method TWEAK(:$filename --> Nil) {
        $!lock := Lock.new;
        %!blames{$filename} = [];
    }

    method add-blame($blame) {
        $!lock.protect: {
            %!blames{$blame.filename}.push: $blame;
        }
    }

    method blames() { %!blames.Map }
}

# Information about a single line of blame
class Git::Blame::Line {
    has Int         $.line-number,
    has Int         $.original-line-number,
    has Str         $.filename;
    has Str         $.line;
    has Git::Commit $.commit handles <sha author author-mail committer
      committer-mail summary previous author-time committer-time>;

    method Str() {
        "$.sha.substr(0,8) ($.author $.author-time "
          ~ $!line-number  # for now
#          ~ sprintf('%4d',$!line-number)  # need to figure out width
          ~ ") $!line"
    }
    method gist() { self.Str }
}

# All the blame information about a single file
class Git::Blame::File {
    has @.lines   is built(False);
    has %!commits;

    multi method new(Git::Blame::File: $file --> Git::Blame::File:D) {
        self.bless: :$file, :commits(Hash.new)
    }

    method TWEAK(:$file, :$commits is raw --> Nil) {
        %!commits := $commits;

        my $io     := $file.IO;
        my $parent := $io.parent;
        my $proc;
        my $iterator := indir $parent, {
            $proc := run <git blame --porcelain>, $io.basename, :out, :err;
            $proc.out.lines.iterator
        }

        my $lines := IterationBuffer.new;
        $lines.push: Nil;  # lines[] is 1-based
        my $sha;
        my $filename;
        my $commit;
        my Int() $todo;
        my Int() $original-line-number;
        my Int() $line-number;

        until (my $porcelain := $iterator.pull-one) =:= IterationEnd {

            # still in a chunk
            if $todo {
                ($sha, $original-line-number, $line-number) =
                  $porcelain.words;
                $porcelain := $iterator.pull-one;
                die "weird end" unless $porcelain.starts-with("\t");

                $commit = %!commits{$sha}
                  // die "No commit for '$sha' found";
            }

            # first chunk or chunk ended
            else {
                ($sha, $original-line-number, $line-number, $todo) =
                  $porcelain.words;

                with %!commits{$sha} {
                    $commit = $_;
                    $porcelain := $iterator.pull-one;
                    die "weird end" unless $porcelain.starts-with("\t");
                }
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
                        %fields<previous-sha previous-filename> = .words;
                    }
                    $filename = %fields<filename>;
                    $commit = %!commits{$sha} :=
                      Git::Commit.new: :$sha, |%fields;
                }
            }

            # all ready to process this line of blame
            my $blame := Git::Blame::Line.new:
              :line($porcelain.substr(1)),  # skip TAB
              :$sha, :$original-line-number, :$line-number,
              :$filename, :$commit;
            $commit.add-blame: $blame;
            $lines.push: $blame;
            --$todo;
        }

        if $proc.err.slurp -> $error {
            return $error.Failure;
        }
        @!lines := $lines.List;
    }

    method commits() { %!commits.Map }
}

=begin pod

=head1 NAME

Git::Blame::File - Who did what and when on a file in a Git repository

=head1 SYNOPSIS

=begin code :lang<raku>

use Git::Blame::File;

my $blamer = Git::Blame::File.new( "t/target" );
say $blamer.lines[3];
# c64c97c3 (Elizabeth Mattijsen 2022-07-27 20:40:22 +0200 3) And this the third line

=end code

=head1 DESCRIPTION

Git::Blame is a module that uses C<git blame> to extract information from a single file in a
Git repository and process it in a number of ways. It's mainly geared to tally contributions
via lines changed, but it can also be modified and used to do some repository mining.

It works, for the time being, with single files.

=head1 METHODS

=head2 lines()

Returns an Array with all the lines in the file (1-based).

=head1 AUTHORS

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/Git-Blame-File .
Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

=head1 COPYRIGHT AND LICENSE

Copyright 2022 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
