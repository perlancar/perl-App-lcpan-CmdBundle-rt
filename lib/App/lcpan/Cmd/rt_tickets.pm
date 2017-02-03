package App::lcpan::Cmd::rt_tickets;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
no warnings 'once';
use Log::Any::IfLOG '$log';

require App::lcpan;
use Perinci::Object;

our %SPEC;

$SPEC{handle_cmd} = {
    v => 1.1,
    summary => 'Return RT new/open tickets for dist/module',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_or_dists_args,
        count => {
            schema => ['bool*', is=>1],
            cmdline_aliases => {c=>{}},
        },
    },
};
sub handle_cmd {
    require HTTP::Tiny;
    require URI::Escape;

    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @res;
    my $envres = envresmulti();
    my $resmeta = {};

    if ($args{count}) {
        $resmeta->{'table.fields'} = [qw/dist count/];
    } else {
        $resmeta->{'table.fields'} = [qw/dist ticket_id ticket_subject/];
    }

  ARG:
    for my $module_or_dist (@{ $args{modules_or_dists} }) {
        my ($dist, $file_id, $cpanid, $version);
        {
            # first find dist
            if (($file_id, $cpanid, $version) = $dbh->selectrow_array(
                "SELECT file_id, cpanid, version FROM dist WHERE name=? AND is_latest", {}, $module_or_dist)) {
                $dist = $module_or_dist;
                last;
            }
            # try mod
            if (($file_id, $dist, $cpanid, $version) = $dbh->selectrow_array("SELECT m.file_id, d.name, d.cpanid, d.version FROM module m JOIN dist d ON m.file_id=d.file_id WHERE m.name=?", {}, $module_or_dist)) {
                last;
            }
        }
        $file_id or do { $envres->add_result(404, "No such module/dist '$module_or_dist'"); next ARG };

        my $query = "Queue='$dist' AND (Status='new' OR Status='open')";
        my $url = "https://rt.cpan.org/REST/1.0/search/ticket?query=".URI::Escape::uri_escape($query);
        say "D:url=<$url>";
        my $htres = HTTP::Tiny->new->get($url);
        $htres->{success} or do { $envres->add_result(500, "Can't fetch ticket for dist '$dist': $htres->{status} $htres->{reason}"); next ARG };
        my $count = 0;
        say "D:content=<$htres->{content}>";
        while ($htres->{content} =~ /^(\d+): (.+)/mg) {
            if ($args{count}) {
                $count++;
            } else {
                push @res, {dist=>$dist, ticket_id=>$1, ticket_subject=>$2};
            }
        }
        if ($args{count}) {
            push @res, {dist=>$dist, count=>$count};
        }
        $envres->add_result(200, "OK", {item_id=>$dist});
    }

    my $res = $envres->as_struct;
    if ($res->[0] == 200) {
        $res->[2] = \@res;
        $res->[3] = $resmeta;
    }
    $res;
}

1;
# ABSTRACT:
