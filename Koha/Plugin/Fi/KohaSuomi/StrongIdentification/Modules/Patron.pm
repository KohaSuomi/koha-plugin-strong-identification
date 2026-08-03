package Koha::Plugin::Fi::KohaSuomi::StrongIdentification::Modules::Patron;

use Modern::Perl;
use JSON qw(decode_json);

use C4::Context;
use Koha::Patrons;

sub new {
    my ($class, $params) = @_;
    my $self = {};

    $self->{_params} = $params;
    bless($self, $class);

    return $self;
}

sub add_patron {
    my ($class, $params) = @_;

    my $json = $params->[0];

    my $libraries = _get_libraries();

    # TO DO: We need a new patron category (following is dummy category)
    # and a decision if we use syspref PatronSelfRegistrationDefaultCategory
    # my $categorycode = C4::Context->preference("PatronSelfRegistrationDefaultCategory");
    my $categorycode = "ITSEREK";

    my $patron_data = {
        surname        => $json->{surname},
        firstname      => $json->{firstname},
        preferred_name => $json->{other_name},
        dateofbirth    => $json->{date_of_birth},
        branchcode     => $libraries->{$json->{library_id}},
        categorycode   => $categorycode,
        address        => $json->{address},
        zipcode        => $json->{postal_code},
        city           => $json->{city},
        email          => $json->{email},
        mobile         => $json->{mobile},
        lang           => $json->{lang}
    };

    # TO DO: How do we handle guarantor-guarantee cases?
    # When is ssn added?

    my $new_patron = Koha::Patron->new( $patron_data );
    $new_patron->store();
}

sub _get_libraries {
    my $libraries = Koha::Libraries->search()->unblessed;
    my %libraries_hash;
    foreach my $library (@$libraries){
        $libraries_hash{$library->{branchname}} = $library->{branchcode};
    }
    return  \%libraries_hash;
}

1;