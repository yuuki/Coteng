package Coteng;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.02";
our $DBI_CLASS = 'DBI';

use Carp ();
use Module::Load qw(load);
use SQL::Maker;
use Class::Accessor::Lite::Lazy (
    rw => [qw(
        current_dbh
    )],
    rw_lazy => [qw(
        sql_builder
    )],
);

use Coteng::DBI;


sub _build_sql_builder {
    my ($self) = @_;
    return SQL::Maker->new(driver => $self->current_dbh->{Driver}{Name});
}

sub new {
    my ($class, $args) = @_;
    my $self = bless {
        connect_info => $args->{connect_info} || undef,
    }, $class;
    return $self;
}

sub db {
    my ($self, $dbname) = @_;
    $dbname || Carp::croak "dbname required";
    $self->current_dbh($self->dbh($dbname));
    $self;
}

sub dbh {
    my ($self, $dbname) = @_;

    $self->{_dbh}{$dbname} ||= do {
        my $db_info = $self->{connect_info}->{$dbname};
        my $dsn     = $db_info->{dsn} || Carp::croak "dsn required";
        my $user    = defined $db_info->{user}   ? $db_info->{user} : '';
        my $passwd  = defined $db_info->{passwd} ? $db_info->{passwd} : '';

        if (! is_class_loaded($DBI_CLASS)) {
            load $DBI_CLASS;
        }
        my $dbh = $DBI_CLASS->connect($dsn, $user, $passwd, {
            RootClass => 'Coteng::DBI'
        });
        $dbh;
    };
}

sub single_by_sql {
    my ($self, $sql, $binds, $class) = @_;

    my $row = $self->current_dbh->select_row($sql, @$binds);
    if ($class) {
        load $class;
        $row = $class->new($row);
    }
    return $row;
}

sub single_named {
    my ($self, $sql, $bind_values, $class) = @_;
    ($sql, my $binds) = SQL::NamedPlaceholder::bind_named($sql, $bind_values);
    my $row = $self->single_by_sql($sql, $binds, $class);
    return $row;
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

sub search_named {
    my ($self, $sql, $bind_values, $class) = @_;
    ($sql, my $binds) = SQL::NamedPlaceholder::bind_named($sql, $bind_values);
    my $rows = $self->search_by_sql($sql, $binds, $class);
    return $rows;
}

sub execute {
    my $self = shift;
    my $db = $self->current_dbh->query($self->_expand_args(@_));
}

sub single {
    my ($self, $table, $where, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };
    if (ref($opt) ne "HASH") {
        $opt = {};
    }

    if (ref($where) ne "HASH" && ref($where) ne "ARRAY") {
        Carp::croak "'where' required to be HASH or ARRAY";
    }

    $opt->{limit} = 1;

    my ($sql, @binds) = $self->sql_builder->select(
        $table,
        $opt->{columns} || ['*'],
        $where,
        $opt
    );
    my $row = $self->single_by_sql($sql, \@binds, $class);
    return $row;
}

sub search {
    my ($self, $table, $where, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };
    if (ref($opt) ne "HASH") {
        $opt = {};
    }

    if (ref($where) ne "HASH" && ref($where) ne "ARRAY") {
        Carp::croak "'where' required to be HASH or ARRAY";
    }

    my ($sql, @binds) = $self->sql_builder->select(
        $table,
        $opt->{'columns'} || ['*'],
        $where,
        $opt
    );
    my $rows = $self->search_by_sql($sql, \@binds, $class);
    return $rows;
}

sub fast_insert {
    my ($self, $table, $args, $prefix) = @_;

    my ($sql, @binds) = $self->sql_builder->insert(
        $table,
        $args,
        { prefix => $prefix },
    );
    $self->execute($sql, @binds);
    return $self->current_dbh->last_insert_id($table);
}

sub insert {
    my $self = shift;
    my ($table, $args, $opt) = @_;
    my $class = do {
        my $klass = pop;
        ref($klass) ? undef : $klass;
    };
    if (ref($opt) ne "HASH") {
        $opt = {};
    }

    if (ref($args) ne "HASH" && ref($args) ne "ARRAY") {
        Carp::croak "'where' required to be HASH or ARRAY";
    }

    $opt->{primary_key} ||= "id";

    my $id = $self->fast_insert($table, $args, $opt->{prefix});
    return $self->single($table, { $opt->{primary_key} => $id }, $class);
}

sub bulk_insert {
    my ($self, $table, $args) = @_;

    return undef unless scalar(@{$args || []});

    my $dbh = $self->current_dbh;
    my $can_multi_insert = $dbh->{Driver}{Name} eq 'mysql' ? 1 : 0;

    if ($can_multi_insert) {
        my ($sql, @binds) = $self->sql_builder->insert_multi($table, $args);
        $self->execute($sql, @binds);
    } else {
        # use transaction for better performance and atomicity.
        my $txn = $dbh->txn_scope();
        for my $arg (@$args) {
            $self->insert($table, $arg);
        }
        $txn->commit;
    }
}

sub update {
    my ($self, $table, $args, $where) = @_;

    my ($sql, @binds) = $self->sql_builder->update($table, $args, $where);
    $self->execute($sql, @binds);
}

sub delete {
    my ($self, $table, $where) = @_;

    my ($sql, @binds) = $self->sql_builder->delete($table, $where);
    $self->execute($sql, \@binds);
}

sub _expand_args (@) {
    my ($class, $query, @args) = @_;

    if (@args == 1 && ref $args[0] eq 'HASH') {
        ( $query, my $binds ) = SQL::NamedPlaceholder::bind_named($query, $args[0]);
        @args = @$binds;
    }

    return ($query, @args);
}

# stolen from Mouse::PurePerl
sub is_class_loaded {
    my $class = shift;

    return 0 if ref($class) || !defined($class) || !length($class);

    my $pack = \%::;

    foreach my $part (split('::', $class)) {
        $part .= '::';
        return 0 if !exists $pack->{$part};

        my $entry = \$pack->{$part};
        return 0 if ref($entry) ne 'GLOB';
        $pack = *{$entry}{HASH};
    }

    return 0 if !%{$pack};

    # check for $VERSION or @ISA
    return 1 if exists $pack->{VERSION}
             && defined *{$pack->{VERSION}}{SCALAR} && defined ${ $pack->{VERSION} };
    return 1 if exists $pack->{ISA}
             && defined *{$pack->{ISA}}{ARRAY} && @{ $pack->{ISA} } != 0;

    # check for any method
    foreach my $name( keys %{$pack} ) {
        my $entry = \$pack->{$name};
        return 1 if ref($entry) ne 'GLOB' || defined *{$entry}{CODE};
    }

    # fail
    return 0;
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
    });

    my $inserted_host = $coteng->db('db_master')->insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    }, "Your::Model::Host");
    my $last_insert_id = $coteng->db('db_master')->fast_insert(host => {
        name    => 'host001',
        ipv4    => '10.0.0.1',
        status  => 'standby',
    });
    my $host = $coteng->db('db_slave')->single(host => {
        name => 'host001',
    }, "Your::Model::Host");
    my $hosts = $coteng->db('db_slave')->search(host => {
        name => 'host001',
    }, "Your::Model::Host");

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
    ], { name => "host001" }, "Your::Model::Host");
    my $host = $coteng->db('db_slave')->single_by_sql(q[
        SELECT * FROM host where name = ? LIMIT 1
    ], [ "host001" ], "Your::Model::Host");

    my $hosts = $coteng->db('db_slave')->search_named(q[
        SELECT * FROM host where status = :status
    ], { status => "working" }, "Your::Model::Host");
    my $hosts = $coteng->db('db_slave')->search_named(q[
        SELECT * FROM host where status = ?
    ], [ "working" ], "Your::Model::Host");


    package Your::Model::Host;

    use Class::Accessor::Lite(
        rw => [qw(
            id
            name
            ipv4
            status
        )],
        new => 1,
    );


=head1 DESCRIPTION

Coteng is a lightweight L<Teng>, just as very simple DBI wrapper.
Teng is a simple and good designed ORMapper, but it has a little complicated functions such as the row class, iterator class, the schema definition class (L<Teng::Row>, L<Teng::Iterator> and L<Teng::Schema>).
Coteng doesn't have such functions and only has very similar Teng SQL interface.

Coteng itself has no transaction and last_insert_id interface, thanks to L<DBIx::Sunny>.
(Coteng uses DBIx::Sunny as a base DB handler.)

=head1 METHODS

Coteng provides a number of methods to all your classes,

=over

=item $coteng = Coteng->new(\%args)

Creates a new Coteng instance.

    # connect new database connection.
    my $coteng = Coteng->new({
        connect_info => {
            dbname => {
                dsn     => $dsn,
                user    => $user,
                passwd  => $passwd,
            },
        },
    });

Arguments can be:

=over

=item * C<connect_info>

Specifies the information required to connect to the database.
The argument should be a reference to a nested hash in the form:

    {
        dbname => {
            dsn     => $dsn,
            user    => $user,
            passwd  => $passwd,
        },
    },

'dbname' is something you like to identify a database type such as 'db_master', 'db_slave', 'db_batch'.

=back

=item C<$row = $coteng-E<gt>db($dbname)>

Set internal current dbh object by $dbname registered in 'new' method.
Returns Coteng object ($self) to enable you to use method chain like below.

    my $row = $coteng->db('db_master')->insert();

=item C<$row = $coteng-E<gt>insert($table, \%row_data, [\%opt], [$class])>

Inserts a new record. Returns the inserted row object blessed $class.
If it's not specified $class, returns the hash reference.

    my $row = $coteng->db('db_master')->insert(host => {
        id   => 1,
        ipv4 => '192.168.0.0',
    }, { primary_key => 'host_id', prefix => 'SELECT DISTINCT' } );

'primary_key' default value is 'id'.
'prefix' default value is 'SELECT'.

If a primary key is available, it will be fetched after the insert -- so
an INSERT followed by SELECT is performed. If you do not want this, use
C<fast_insert>.

=item C<$last_insert_id = $teng-E<gt>fast_insert($table_name, \%row_data, [$prefix]);>

insert new record and get last_insert_id.

no creation row object.

=item C<$teng-E<gt>bulk_insert($table_name, \@rows_data)>

Accepts either an arrayref of hashrefs.
Each hashref should be a structure suitable for your table schema.
The second argument is an arrayref of hashrefs. All of the keys in these hashrefs must be exactly the same.

insert many record by bulk.

example:

    $coteng->db('db_master')->bulk_insert(host => [
        {
            id   => 1,
            name => 'host001',
        },
        {
            id   => 2,
            name => 'host002',
        },
        {
            id   => 3,
            name => 'host003',
        },
    ]);

=item C<$update_row_count = $coteng-E<gt>update($table_name, \%update_row_data, [\%update_condition])>

Calls UPDATE on C<$table_name>, with values specified in C<%update_ro_data>, and returns the number of rows updated. You may optionally specify C<%update_condition> to create a conditional update query.

    my $update_row_count = $coteng->db('db_master')->update(host =>
        {
            name => 'host001',
        },
        {
            id => 1
        }
    );
    # Executes UPDATE user SET name = 'host001' WHERE id = 1

=item C<$delete_row_count = $coteng-E<gt>delete($table, \%delete_condition)>

Deletes the specified record(s) from C<$table> and returns the number of rows deleted. You may optionally specify C<%delete_condition> to create a conditional delete query.

    my $rows_deleted = $coteng->db('db_master')->delete(host => {
        id => 1
    });
    # Executes DELETE FROM host WHERE id = 1

=item C<$row = $teng-E<gt>single($table_name, \%search_condition, \%search_attr, [$class])>

Returns (hash references or $class objects).

    my $row = $coteng->single(host => { id => 1 }, 'Your::Model::Host');

    my $row = $coteng->single(host => { id => 1 }, { columns => [qw(id name)] });

=item C<$rows = $coteng-E<gt>search($table_name, [\%search_condition, [\%search_attr]], [$class])>

Returns array reference of (hash references or $class objects).

    my $rows = $coteng->db('db_slave')->search(host => {id => 1}, {order_by => 'id'}, 'Your::Model::Host');

=item C<$row = $teng-E<gt>single_named($sql, [\%bind_values], [$class])>

get one record from execute named query

    my $row = $coteng->dbh('db_slave')->single_named(q{SELECT id,name FROM host WHERE id = :id LIMIT 1}, {id => 1}, 'Your::Model::Host');

=item C<$row = $coteng-E<gt>single_by_sql($sql, [\@bind_values], $class)>

get one record from your SQL.

    my $row = $coteng->single_by_sql(q{SELECT id,name FROM user WHERE id = ? LIMIT 1}, [1], 'user');

=item C<$rows = $coteng-E<gt>search_named($sql, [\%bind_values], [$class])>

execute named query

    my $itr = $coteng->db('db_slave')->search_named(q[SELECT * FROM user WHERE id = :id], {id => 1}, 'Your::Model::Host');

If you give array reference to value, that is expanded to "(?,?,?,?)" in SQL.
It's useful in case use IN statement.

    # SELECT * FROM user WHERE id IN (?,?,?);
    # bind [1,2,3]
    my $rows = $coteng->dbh('db_slave')->search_named(q[SELECT * FROM user WHERE id IN :ids], {ids => [1, 2, 3]}, 'Your::Model::Host');

=item C<$rows = $coteng-E<gt>search_by_sql($sql, [\@bind_values], [$class])>

execute your SQL

    my $rows = $coteng->dbh('db_slave')->search_by_sql(q{
        SELECT
            id, name
        FROM
            host
        WHERE
            id = ?
    }, [ 1 ]);

=item C<$sth = $coteng-E<gt>execute($sql, [\@bind_values|@bind_values])>

execute query and get statement handler.

=back

=head1 NOTE

=over

=item USING DBI CLASSES

default DBI CLASS is 'DBI'. You can change DBI CLASS via $Coteng::DBI_CLASS.

    local $Coteng::DBI_CLASS = 'Scope::Container::DBI';
    my $coteng = Coteng->new({ connect_info => ... });
    $coteng->dbh('db_master')->insert(...);

=back

=head1 SEE ALSO

=over

=item L<Teng>

=item L<DBIx::Sunny>

=item L<SQL::Maker>

=back

=head1 LICENSE

Copyright (C) y_uuki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

y_uuki E<lt>yuki.tsubo@gmail.comE<gt>

=cut

