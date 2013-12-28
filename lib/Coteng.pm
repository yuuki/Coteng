package Coteng;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp ();

use DBIx::Sunny;
use Module::Load qw(load_class);
use SQL::Maker;

use Class::Accessor::Lite::Lazy (
    rw => [qw(
        current_dbh
    )],
    rw_lazy => [qw(
        sql_builder
    )],
);

sub _build_sql_builder {
    my ($self) = @_;
    return SQL::Maker->new(driver => $self->{driver_name});
}

sub new {
    my ($class, $args) = @_;
    my $self = bless {
        connect_info    => $args->{connect_info}   || undef,
        root_dbi_class  => $args->{root_dbi_class} || undef,
        driver_name     => $args->{driver_name}    || undef,
        current_dbh     => undef,
    }, $class;
    return $self;
}

sub db {
    my ($self, $dbname) = @_;
    $dbname || Carp::croak "dbname required";
    $self->{current_dbh} ||= $self->dbh($dbname);
    $self;
}

sub dbh {
    my ($self, $dbname) = @_;

    $self->{_dbh}{$dbname} ||= do {
        my $db_info = $self->{connect_info}->{$dbname};
        my $dsn     = $db_info->{dsn} || Carp::croak "dsn required";
        my $user    = defined $db_info->{user}   ? $db_info->{user} : '';
        my $passwd  = defined $db_info->{passwd} ? $db_info->{passwd} : '';

        my $dbh = DBIx::Sunny->connect($dsn, $user, $passwd, {
            RootClass => $self->{root_dbi_class},
        });
        $dbh;
    };
}

sub single_named {
    my ($self, $query, $bind_values, $class) = @_;
    my ($sql, $binds) = SQL::NamedPlaceholder::bind_named($query, $bind_values);
    my $row = $self->current_dbh->select_row($sql, @$binds);
    if ($class) {
        load $class;
        $row = $class->new($row);
    }
    return $row;
}

sub single_by_sql {
    my ($self, $sql, $binds, $class) = @_;

    my $row = $self->current_dbh->select_row($sql, @$binds);
    if ($class) {
        load $class;
        $row = $class->new($row);
    }
    return $self->current_dbh->select_row($sql, $binds);
}

sub search_named {
    my ($self, $sql, $bind_values, $class) = @_;
    ($sql, my $binds) = SQL::NamedPlaceholder::bind_named($sql, $bind_values);
    my $rows = $self->current_dbh->select_all($sql, @$binds);
    if ($class) {
        load $class;
        $rows = [ map { $class->new($_) } @$rows ];
    }
    return $rows;
}

sub search_by_sql {
    my ($self, $sql, $binds, $class) = @_;
    my $rows = $self->current_dbh->select_all($sql, @$binds);
    if ($class) {
        load $class;
        $rows = [ map { $class->new($_) } @$rows ];
    }
    return $rows;
}

sub exucute {
    my $self = shift;
    return $self->current_dbh->query($self->_expand_args(@_));
}

sub single {
    my ($self, $table, $where, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };

    if (ref($where) ne "HASH" && ref($where) ne "ARRAY") {
        Carp::croak "'where' required to be HASH or ARRAY";
    }
    $opt->{limit} = 1;

    my ($sql, @binds) = $self->sql_builder->select(
        $table,
        $opt->{'+columns'} || ['*'],
        $where,
        $opt
    );
    my $rows = $self->single_by_sql($sql, \@binds, $class);
    return $rows;
}

sub search {
    my ($self, $table, $where, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };

    if (ref($where) ne "HASH" && ref($where) ne "ARRAY") {
        Carp::croak "'where' required to be HASH or ARRAY";
    }

    my ($sql, @binds) = $self->sql_builder->select(
        $table,
        $opt->{'+columns'} || ['*'],
        $where,
        $opt
    );
    my $rows = $self->search_by_sql($sql, \@binds, $class);
    return $rows;
}

sub insert {
    my $self = shift;
    my ($table, $args, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };

    $opt->{primary_key} ||= "id";

    my $id = $self->fast_insert($table, $args, $opt->{prefix});
    return $self->single($table, { $opt->{primary_key} => $id }, $class);
}

sub fast_insert {
    my ($self, $table, $args, $prefix) = @_;

    my ($sql, @binds) = $self->sql_builder->insert(
        $table,
        $args,
        { prefix => $prefix },
    );
    $self->execute($sql, \@binds);
    return $self->_last_insert_id($table);
}

sub update {
    my ($self, $table, $args, $where) = @_;

    my ($sql, @binds) = $self->sql_builder->update($table, $args, $where);
    my $sth = $self->execute($sql, \@binds);
    my $rows = $sth->rows;
    $sth->finish;

    return $rows;
}

sub delete {
    my ($self, $table, $where) = @_;

    my ($sql, @binds) = $self->sql_builder->delete($table, $where);
    my $sth = $self->execute($sql, \@binds);
    my $rows = $sth->rows;
    $sth->finish;

    $rows;
}

sub _expand_args (@) {
    my ($query, @args) = @_;

    if (@args == 1 && ref $args[0] eq 'HASH') {
        ( $query, my $binds ) = SQL::NamedPlaceholder::bind_named($query, $args[0]);
        @args = @$binds;
    }

    return ($query, @args);
}

sub _last_insert_id {
    my ($self, $table_name) = @_;

    my $driver = $self->driver_name;
    if ( $driver eq 'mysql' ) {
        return $self->{mysql_insertid};
    } elsif ( $driver eq 'Pg' ) {
        return $self->last_insert_id( undef, undef, undef, undef,{ sequence => join( '_', $table_name, 'id', 'seq' ) } );
    } elsif ( $driver eq 'SQLite' ) {
        return $self->func('last_insert_rowid');
    } elsif ( $driver eq 'Oracle' ) {
        return;
    } else {
        Carp::croak "Don't know how to get last insert id for $driver";
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Coteng - Lightweight Teng

=head1 SYNOPSIS

    use Coteng;

    my $coteng = Coteng->new({
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

    my $inserted_host = $coteng->db('db_master')->insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    }, "Server::Model::Host");
    my $last_insert_id = $coteng->db('db_master')->fast_insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    });
    my $host = $coteng->db('db_slave')->single(host => {
        name => 'host001',
    }, "Server::Model::Host");
    my $hosts = $coteng->db('db_slave')->search(host => {
        name => 'host001',
    }, "Server::Model::Host");

    my $updated_row_count = $coteng->db('db_master')->update(host => {
        status => "working",
    }, {
        id => 10,
    });
    my $deleted_row_count = $coteng->db('db_master')->delete(host => {
        id => 10,
    });

    ## no blessed return value

    my $hosts = $coteng->db('db_slave')->single(host => {
        name => 'host001',
    });

    # Raw SQL interface

    my $host = $coteng->db('db_slave')->single_named(q[
        SELECT * FROM host where name = :name LIMIT 1
    ], { name => "host001" }, "Server::Model::Host");
    my $host = $coteng->db('db_slave')->single_by_sql(q[
        SELECT * FROM host where name = ? LIMIT 1
    ], [ "host001" ], "Server::Model::Host");

    my $hosts = $coteng->db('db_slave')->search_named(q[
        SELECT * FROM host where status = :status
    ], { status => "working" }, "Server::Model::Host");
    my $hosts = $coteng->db('db_slave')->search_named(q[
        SELECT * FROM host where status = ?
    ], [ "working" ], "Server::Model::Host");


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

