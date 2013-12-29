[![Build Status](https://travis-ci.org/y-uuki/Coteng.png?branch=master)](https://travis-ci.org/y-uuki/Coteng) [![Coverage Status](https://coveralls.io/repos/y-uuki/Coteng/badge.png?branch=master)](https://coveralls.io/r/y-uuki/Coteng?branch=master)
# NAME

Coteng - Lightweight Teng

# SYNOPSIS

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



# DESCRIPTION

Coteng is a lightweight [Teng](http://search.cpan.org/perldoc?Teng), just as very simple DBI wrapper.
Teng is a simple and good designed ORMapper, but it has a little complicated functions such as the row class, iterator class, the schema definition class ([Teng::Row](http://search.cpan.org/perldoc?Teng::Row), [Teng::Iterator](http://search.cpan.org/perldoc?Teng::Iterator) and [Teng::Schema](http://search.cpan.org/perldoc?Teng::Schema)).
Coteng doesn't have such functions and only has very similar Teng SQL interface.

Coteng itself has no transaction and last\_insert\_id interface, thanks to [DBIx::Sunny](http://search.cpan.org/perldoc?DBIx::Sunny).
(Coteng uses DBIx::Sunny as a base DB handler.)

# METHODS

Coteng provides a number of methods to all your classes,

- $coteng = Coteng->new(\\%args)

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

    - `connect_info`

        Specifies the information required to connect to the database.
        The argument should be a reference to a nested hash in the form:

            {
                dbname => {
                    dsn     => $dsn,
                    user    => $user,
                    passwd  => $passwd,
                },
            },

        'dbname' is something you like to identify a database type such as 'db\_master', 'db\_slave', 'db\_batch'.

- `$row = $coteng->db($dbname)`

    Set internal current dbh object by $dbname registered in 'new' method.
    Returns Coteng object ($self) to enable you to use method chain like below.

        my $row = $coteng->db('db_master')->insert();

- `$row = $coteng->insert($table, \%row_data, [\%opt], [$class])`

    Inserts a new record. Returns the inserted row object blessed $class.
    If it's not specified $class, returns the hash reference.

        my $row = $coteng->db('db_master')->insert(host => {
            id   => 1,
            ipv4 => '192.168.0.0',
        }, { primary_key => 'host_id', prefix => 'SELECT DISTINCT' } );

    'primary\_key' default value is 'id'.
    'prefix' default value is 'SELECT'.

    If a primary key is available, it will be fetched after the insert -- so
    an INSERT followed by SELECT is performed. If you do not want this, use
    `fast_insert`.

- `$last_insert_id = $teng->fast_insert($table_name, \%row_data, [$prefix]);`

    insert new record and get last\_insert\_id.

    no creation row object.

- `$teng->bulk_insert($table_name, \@rows_data)`

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

- `$update_row_count = $coteng->update($table_name, \%update_row_data, [\%update_condition])`

    Calls UPDATE on `$table_name`, with values specified in `%update_ro_data`, and returns the number of rows updated. You may optionally specify `%update_condition` to create a conditional update query.

        my $update_row_count = $coteng->db('db_master')->update(host =>
            {
                name => 'host001',
            },
            {
                id => 1
            }
        );
        # Executes UPDATE user SET name = 'host001' WHERE id = 1

- `$delete_row_count = $coteng->delete($table, \%delete_condition)`

    Deletes the specified record(s) from `$table` and returns the number of rows deleted. You may optionally specify `%delete_condition` to create a conditional delete query.

        my $rows_deleted = $coteng->db('db_master')->delete(host => {
            id => 1
        });
        # Executes DELETE FROM host WHERE id = 1

- `$row = $teng->single($table_name, \%search_condition, \%search_attr, [$class])`

    Returns (hash references or $class objects).

        my $row = $coteng->single(host => { id => 1 }, 'Your::Model::Host');

        my $row = $coteng->single(host => { id => 1 }, { columns => [qw(id name)] });

- `$rows = $coteng->search($table_name, [\%search_condition, [\%search_attr]], [$class])`

    Returns array reference of (hash references or $class objects).

        my $rows = $coteng->db('db_slave')->search(host => {id => 1}, {order_by => 'id'}, 'Your::Model::Host');

- `$row = $teng->single_named($sql, [\%bind_values], [$class])`

    get one record from execute named query

        my $row = $coteng->dbh('db_slave')->single_named(q{SELECT id,name FROM host WHERE id = :id LIMIT 1}, {id => 1}, 'Your::Model::Host');

- `$row = $coteng->single_by_sql($sql, [\@bind_values], $class)`

    get one record from your SQL.

        my $row = $coteng->single_by_sql(q{SELECT id,name FROM user WHERE id = ? LIMIT 1}, [1], 'user');

- `$rows = $coteng->search_named($sql, [\%bind_values], [$class])`

    execute named query

        my $itr = $coteng->db('db_slave')->search_named(q[SELECT * FROM user WHERE id = :id], {id => 1}, 'Your::Model::Host');

    If you give array reference to value, that is expanded to "(?,?,?,?)" in SQL.
    It's useful in case use IN statement.

        # SELECT * FROM user WHERE id IN (?,?,?);
        # bind [1,2,3]
        my $rows = $coteng->dbh('db_slave')->search_named(q[SELECT * FROM user WHERE id IN :ids], {ids => [1, 2, 3]}, 'Your::Model::Host');

- `$rows = $coteng->search_by_sql($sql, [\@bind_values], [$class])`

    execute your SQL

        my $rows = $coteng->dbh('db_slave')->search_by_sql(q{
            SELECT
                id, name
            FROM
                host
            WHERE
                id = ?
        }, [ 1 ]);

- `$sth = $coteng->execute($sql, [\@bind_values|@bind_values])`

    execute query and get statement handler.

# NOTE

- USING DBI CLASSES

    default DBI CLASS is 'DBI'. You can change DBI CLASS via $Coteng::DBI\_CLASS.

        local $Coteng::DBI_CLASS = 'Scope::Container::DBI';
        my $coteng = Coteng->new({ connect_info => ... });
        $coteng->dbh('db_master')->insert(...);

# SEE ALSO

- [Teng](http://search.cpan.org/perldoc?Teng)
- [DBIx::Sunny](http://search.cpan.org/perldoc?DBIx::Sunny)
- [SQL::Maker](http://search.cpan.org/perldoc?SQL::Maker)

# LICENSE

Copyright (C) y\_uuki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

y\_uuki <yuki.tsubo@gmail.com>
