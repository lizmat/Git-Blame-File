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
    has Int         $.line-number;
    has Int         $.original-line-number;
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

        my $io   := $!file.IO.resolve;
        my $proc := indir $io.parent, {
            run <git blame --porcelain>, @sets, $io.relative, :out, :err;
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

# vim: expandtab shiftwidth=4
