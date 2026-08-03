#!/usr/bin/env perl

use Modern::Perl;

use open qw( :std :encoding(UTF-8) );
binmode( STDOUT, ":encoding(UTF-8)" );

use FindBin qw($Bin);
use JSON qw(decode_json);

use Test::More tests => 2;
use Test::NoWarnings;
use Test::MockModule;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new();

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'POST test' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $password = 'AbcdEFG123';

    my $patron_np = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $patron_np->set_password( { password => $password, skip_validation => 1 } );
    my $userid_np = $patron_np->userid;

    my $patron = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;
    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $patron->borrowernumber,
                module_bit     => 4,
                code           => 'edit_borrowers',
            },
        }
    );

    my $test_patron_json = "$Bin/data/test_patron.json";

    open my $fh, '<', $test_patron_json or die "Cannot open $test_patron_json: $!";
    local $/;
    my $json_text = <$fh>;
    close $fh;

    my $json = decode_json($json_text);

    # Disable logging
    t::lib::Mocks::mock_preference( 'BorrowersLog', 1 );
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

    $t->post_ok( "//$userid_np:$password@/api/v1/contrib/kohasuomi/identification" => json => 1 )->status_is(403);
    $t->post_ok( "//$userid:$password@/api/v1/contrib/kohasuomi/identification" => '' )->status_is(400);


    $t->post_ok( "//$userid:$password@/api/v1/contrib/kohasuomi/identification" => json =>  $json )->status_is(201);

    $schema->storage->txn_rollback;
};