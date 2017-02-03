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
    summary => 'Return RT tickets for dist/module',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mods_or_dists_args,
        type => {
            schema => ['str*', in=>[qw/Active Resolved Rejected/]],
            default => 'Active',
        },
        count => {
            summary => 'Instead of listing each ticket, return ticket count for each distribution',
            schema => ['bool*', is=>1],
            cmdline_aliases => {c=>{}},
        },
    },
};
sub handle_cmd {
    require WWW::RT::CPAN;

    my %args = @_;
    my $type = $args{type};

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my @res;
    my $envres = envresmulti();
    my $resmeta = {};

    if ($args{count}) {
        $resmeta->{'table.fields'} = [qw/dist count/];
    } else {
        $resmeta->{'table.fields'} = [qw/dist ticket_id ticket_title ticket_status/];
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

        my $res;
        if ($type eq 'Resolved') {
            $res = WWW::RT::CPAN::list_dist_resolved_tickets(dist => $dist);
        } elsif ($type eq 'Rejected') {
            $res = WWW::RT::CPAN::list_dist_rejected_tickets(dist => $dist);
        } else {
            $res = WWW::RT::CPAN::list_dist_active_tickets(dist => $dist);
        }

        $res->[0] == 200 or do { $envres->add_result(500, "Can't fetch ticket for dist '$dist'", $res); next ARG };
        my $count = 0;
        for my $t (@{ $res->[2] }) {
            if ($args{count}) {
                $count++;
            } else {
                push @res, {dist=>$dist, ticket_id=>$t->{id}, ticket_title=>$t->{title}, ticket_status=>$t->{status}};
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
