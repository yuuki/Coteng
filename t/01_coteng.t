use strict;
use warnings;

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
    isa_ok $db->dbh('db_master'), 'Coteng::DBI::db';
    isa_ok $db->dbh('db_slave'),  'Coteng::DBI::db';
};

done_testing;
