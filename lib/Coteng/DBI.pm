package Coteng::DBI;
use strict;
use warnings;

use parent 'DBIx::Sunny';

use Carp ();
use SQL::NamedPlaceholder;

sub _expand_args (@) {
    my ($query, @args) = @_;

    if (@args == 1 && ref $args[0] eq 'HASH') {
        ( $query, my $binds ) = SQL::NamedPlaceholder::bind_named($query, $args[0]);
        @args = @$binds;
    }

    return ($query, @args);
}

package Coteng::DBI::db;
use strict;
use warnings;

use parent -norequire => 'DBIx::Sunny::db';
use Module::Load qw(load_class);
use SQL::Maker;

use Class::Accessor::Lite::Lazy (
    rw_lazy => [qw(
        sql_builder
        driver_name
    )],
);

sub _build_sql_builder {
    my $self = shift;
    return SQL::Maker->new(driver => $self->driver_name);
}

sub single_named {
    my ($self, $query, $bind_values, $class) = @_;
    my ($sql, $binds) = SQL::NamedPlaceholder::bind_named($query, $bind_values);
    my $row = $self->SUPER::select_row($sql, @$binds);
    if ($class) {
        load $class;
        $row = $class->new($row);
    }
    return $row;
}

sub single_by_sql {
    my ($self, $sql, $binds, $class) = @_;

    my $row = $self->SUPER::select_row($sql, @$binds);
    if ($class) {
        load $class;
        $row = $class->new($row);
    }
    return $self->SUPER::select_row($sql, $binds);
}

sub search_named {
    my ($self, $sql, $bind_values, $class) = @_;
    ($sql, my $binds) = SQL::NamedPlaceholder::bind_named($sql, $bind_values);
    my $rows = $self->SUPER::select_all($sql, @$binds);
    if ($class) {
        load $class;
        $rows = [ map { $class->new($_) } @$rows ];
    }
    return $rows;
}

sub search_by_sql {
    my ($self, $sql, $binds, $class) = @_;
    my $rows = $self->SUPER::select_all($sql, @$binds);
    if ($class) {
        load $class;
        $rows = [ map { $class->new($_) } @$rows ];
    }
    return $rows;
}

sub exucute {
    my $self = shift;
    return $self->SUPER::query(Coteng::DBI::_expand_args(@_));
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
    my $rows = $self->search_by_sql($sql, \@binds, $class);
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

package Coteng::DBI::st;
use parent -norequire => 'DBIx::Sunny::st';

1;
