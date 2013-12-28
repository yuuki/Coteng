package Coteng;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp ();

use Coteng::DBI;

sub new {
    my ($class, $args) = @_;
    my $self = bless {
        connect_info    => $args->{connect_info}   || undef,
        root_dbi_class  => $args->{root_dbi_class} || undef,
        driver_name     => $args->{driver_name}    || undef,
    }, $class;
    return $self;
}

sub dbh {
    my ($self, $dbname) = @_;

    $self->{_dbh}{$dbname} ||= do {
        my $db_info = $self->{connect_info}->{$dbname};
        my $dsn     = $db_info->{dsn} || Carp::croak "dsn required";
        my $user    = defined $db_info->{user}   ? $db_info->{user} : '';
        my $passwd  = defined $db_info->{passwd} ? $db_info->{passwd} : '';

        my $dbh = Coteng::DBI->connect($dsn, $user, $passwd, {
            RootClass => $self->{root_dbi_class},
        });
        if ($self->{driver_name}) {
            $dbh->driver_name($self->{driver_name});
        }
        $dbh;
    };
}


1;
__END__

=encoding utf-8

=head1 NAME

Coteng - Lightweight Teng

=head1 SYNOPSIS

    use Coteng;

    my $db = Coteng->new({
        connect_info => {
            db_master => {
                dsn     => 'dbi:mysql:dbname=server;host=dbmasterhost',
                user    => 'nobody',
                passwd  => 'nobody',
            },
            db_slave => {
                dsn     => 'dbi:mysql:dbname=server;host=dbslavehost',
                user    => 'nobody',
                passwd  => 'nobody',
            },
        },
        driver_name => 'mysql',
        root_dbi_class => "Scope::Container::DBI",
    });

    my $inserted_host = $db->dbh('db_master')->insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    }, "Server::Model::Host");
    my $last_insert_id = $db->dbh('db_master')->fast_insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    });
    my $host = $db->dbh('db_slave')->single(host => {
        name => 'host001',
    }, "Server::Model::Host");
    my $hosts = $db->dbh('db_slave')->search(host => {
        name => 'host001',
    }, "Server::Model::Host");

    my $updated_row_count = $db->dbh('db_master')->update(host => {
        status => "working",
    }, {
        id => 10,
    });
    my $deleted_row_count = $db->dbh('db_master')->delete(host => {
        id => 10,
    });

    ## no blessed return value

    my $hosts = $db->dbh('db_slave')->single(host => {
        name => 'host001',
    });

    # Raw SQL interface

    my $host = $db->dbh('db_slave')->single_named(q[
        SELECT * FROM host where name = :name LIMIT 1
    ], { name => "host001" }, "Server::Model::Host");
    my $host = $db->dbh('db_slave')->single_by_sql(q[
        SELECT * FROM host where name = ? LIMIT 1
    ], [ "host001" ], "Server::Model::Host");

    my $hosts = $db->dbh('db_slave')->search_named(q[
        SELECT * FROM host where status = :status
    ], { status => "working" }, "Server::Model::Host");
    my $hosts = $db->dbh('db_slave')->search_named(q[
        SELECT * FROM host where status = ?
    ], [ "working" ], "Server::Model::Host");


    use DBIx::Rainy::DBI;

    my $dbh = DBIx::Rainy::DBI->connect('dbi:mysql:dbname=db_master;host=dbmasterhost', 'nobody', 'nobody', {
        RootClass => "Scope::Container::DBI",
    });
    my $host = $dbh->single(host => {
        name => 'host002',
    }, "Server::Model::Host");

=head1 DESCRIPTION

Coteng is a lightweight L<Teng>, just as very simple DBI Wrapper.
Teng is a simple and good designed ORMapper, but it has a little complicated functions such as the original model class and the schema definition class (L<Teng::Row> and L<Teng::Schema>).
Coteng doesn't have such functions and only has very similar Teng SQL interface.

=head1 METHODS

=over 4

=back

=head SEE ALSO

=over

=item L<Teng>

=item L<SQL::Maker>

=back

=head1 LICENSE

Copyright (C) y_uuki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

y_uuki E<lt>yuki.tsubo@gmail.comE<gt>

=cut

