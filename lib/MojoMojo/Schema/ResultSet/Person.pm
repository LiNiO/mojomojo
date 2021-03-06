package MojoMojo::Schema::ResultSet::Person;

use strict;
use warnings;
use base qw/MojoMojo::Schema::Base::ResultSet/;

=head1 NAME

MojoMojo::Schema::ResultSet::Person

=head1 METHODS

=over 4

=item get_person

Get a person by login.

=cut

sub get_person {
    my ( $self, $login ) = @_;
    my ($person) = $self->search( { login => $login } );
}

=item get_user

Same as L</get_person>.

=cut

sub get_user {
    my ( $self, $user ) = @_;
    return $self->search( { login => $user } )->next();
}

=item registration_profile

returns a L<Data::FormValidator> profile for registration.

=cut

sub registration_profile {
    my ( $self, $schema ) = @_;
    return {
        email => {
            constraint => 'email',
            name       => 'Invalid format'
        },
        login => [
            {
                constraint => qr/^\w{3,10}$/,
                name       => 'only letters, 3-10 chars'
            },
            {
                constraint => sub { $self->user_free( $schema, @_ ) },
                name       => 'Username taken'
            }
        ],
        name => {
            constraint => qr/^\S+\s+\S+/,
            name       => 'Full name please'
        },
        pass => {
            constraint => \&pass_matches,
            params     => [qw( pass confirm)],
            name       => "Password doesn't match"
        }
    };
}

=item user_free

Check if a username is already in user. Returns 1 for free, 0 for in use.

=cut

sub user_free {
    my ( $class, $schema, $login ) = @_;
    $login ||= $class;
    my $user = $class->result_source->resultset->get_user($login);
    return ( $user ? 0 : 1 );
}

=back

=head1 LICENSE

This library is free software . You can redistribute it and/or modify 
it under the same terms as perl itself.

=cut

1;