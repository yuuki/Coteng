[![Build Status](https://travis-ci.org/y-uuki/Coteng.png?branch=master)](https://travis-ci.org/y-uuki/Coteng) [![Coverage Status](https://coveralls.io/repos/y-uuki/Coteng/badge.png?branch=master)](https://coveralls.io/r/y-uuki/Coteng?branch=master)
# NAME

Coteng - Lightweight Teng

# SYNOPSIS

```perl
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
```


# DESCRIPTION

Coteng is a lightweight [Teng](https://metacpan.org/pod/Teng), just as very simple DBI Wrapper.
Teng is a simple and good designed ORMapper, but it has a little complicated functions such as the original model class and the schema definition class ([Teng::Row](https://metacpan.org/pod/Teng::Row) and [Teng::Schema](https://metacpan.org/pod/Teng::Schema)).
Coteng doesn't have such functions and only has very similar Teng SQL interface.

Coteng itself has no transaction and last\_insert\_id interface, thanks to [DBIx::Sunny](https://metacpan.org/pod/DBIx::Sunny).
(Coteng uses DBIx::Sunny as a base DB handler.)

# METHODS

- [Teng](https://metacpan.org/pod/Teng)
- [DBIx::Sunny](https://metacpan.org/pod/DBIx::Sunny)
- [SQL::Maker](https://metacpan.org/pod/SQL::Maker)

# LICENSE

Copyright (C) y\_uuki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

y\_uuki <yuki.tsubo@gmail.com>
