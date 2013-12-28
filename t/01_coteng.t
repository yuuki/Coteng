use strict;
use warnings;

use t::cotengtest;
use Test::More;

subtest use => sub {
    use_ok "Coteng";
};

subtest new => sub {
    my $db = Coteng->new({
        connect_info => {
            db_master => {
                dsn     => 'dbi:SQLite::memory:',
                user    => 'nobody',
                passwd  => 'nobody',
            },
            db_slave => {
                dsn     => 'dbi:SQLite::memory:',
                user    => 'nobody',
                passwd  => 'nobody',
            },
        },
        driver_name => 'SQLite',
        root_dbi_class => "Scope::Container::DBI",
    });

    if (ok $db) {
        isa_ok $db, "Coteng";
        is_deeply $db->{connect_info}{db_master}, {
            dsn     => 'dbi:SQLite::memory:',
            user    => 'nobody',
            passwd  => 'nobody',
        };
        is_deeply $db->{connect_info}{db_slave}, {
            dsn     => 'dbi:SQLite::memory:',
            user    => 'nobody',
            passwd  => 'nobody',
        };
        is $db->{driver_name}, 'SQLite';
        is $db->{root_dbi_class}, "Scope::Container::DBI";
    }
};

subtest dbh => sub {
    my $db = Coteng->new({
        connect_info => {
            db_master => {
                dsn => 'dbi:SQLite::memory:',
            },
            db_slave => {
                dsn => 'dbi:SQLite::memory:',
            },
        },
        driver_name => 'SQLite',
    });
    isa_ok $db->dbh('db_master'), 'DBIx::Sunny::db';
    isa_ok $db->dbh('db_slave'),  'DBIx::Sunny::db';
};


my $dbh = setup_dbh();
create_table($dbh);

my $coteng = Coteng->new({
    connect_info => {
        db_master => {
            dsn => 'dbi:SQLite::memory:',
        },
    },
    driver_name => 'SQLite',
});
$coteng->{current_dbh} = $dbh;

subtest single => sub {
    my $id = insert_mock($dbh, name => "mock1");

    my $row = $coteng->single(mock => {
        id => $id,
    });
    isa_ok $row, "HASH";
    use Data::Dumper;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;
    warn Dumper $row;
    warn Dumper $row->{name};
    is $row->{name}, "mock1";
};

subtest search => sub {
    my $id = insert_mock($dbh, name => "mock2");

    my $rows = $coteng->search(mock => {
        name => "mock1",
    });
    isa_ok $rows, "ARRAY";
    is scalar(@$rows), 1;
    isa_ok $rows->[0], "HASH";
};

subtest fast_insert => sub {
};

subtest insert => sub {
};

subtest update => sub {
};

subtest delete => sub {
};

subtest single_named => sub {
};

subtest single_by_sql => sub {
};

subtest search_named => sub {
};

subtest search_by_sql => sub {
};

subtest execute => sub {
};


done_testing;
