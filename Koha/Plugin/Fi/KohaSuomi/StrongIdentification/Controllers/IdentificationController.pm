package Koha::Plugin::Fi::KohaSuomi::StrongIdentification::Controllers::IdentificationController;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Data::Dumper;

use Koha::Logger;

use Koha::Plugin::Fi::KohaSuomi::StrongIdentification::Modules::Patron;

sub add {
    my $c = shift->openapi->valid_input or return;

    my $logger = Koha::Logger->get({ interface=> 'api' });
    my $req  = $c->req->json;
    my $current_user = $c->stash('koha.user');

    try {
        my $new_patron = Koha::Plugin::Fi::KohaSuomi::StrongIdentification::Modules::Patron->new();
        $new_patron->add_patron($req);
        return $c->render(status => 201, openapi => {message => "Patron data saved successfully"});
    }
    catch {
        my $error = $_;
        $logger->error("Failed to add patron: $error");
        return $c->render(status => 500, openapi => {error => "Something went wrong, check logs for details"});
    };
}

1;