package MojoMojo::Controller::User;

use strict;
use base qw/Catalyst::Controller::HTML::FormFu/;

use Digest::MD5 qw/md5_hex/;
use Text::Password::Pronounceable;

my $auth_class = MojoMojo->config->{auth_class};

=head1 NAME

MojoMojo::Controller::User - Login/User Management Controller


=head1 DESCRIPTION

This controller allows user to Log In and Log out.


=head1 ACTIONS

=over 4

=item login (/.login)

Log in through the authentication system.

=cut

sub login : Global {
    my ( $self, $c ) = @_;
    $c->stash->{message} ||= $c->loc('Please enter username and password');
    if ( $c->req->params->{login} ) {
        if (
            $c->authenticate(
                {
                    login => $c->req->params->{'login'},
                    pass  => $c->req->params->{'pass'}
                }
            )
            )
        {

            $c->stash->{user} = $c->user->obj;
            $c->res->redirect( $c->uri_for( $c->stash->{path} ) )
                unless $c->stash->{template};
            return;
        }
        else {
            $c->stash->{fail} =1;
            $c->stash->{message} = $c->loc('Could not authenticate that login.');
        }
    }
    $c->stash->{template} ||= "user/login.tt";
}

=item logout (/.logout)

Log out the user

=cut

sub logout : Global {
    my ( $self, $c ) = @_;
    $c->logout;
    undef $c->stash->{user};
    $c->forward('/page/view');
}

=item users (/.users)

Show a list of the active users with a link to their page.

=cut

sub users : Global {
    my ( $elf, $c, $tag ) = @_;
    my $res = $c->model("DBIC::Person")->search(
        { active => 1 },
        {
            page => $c->req->param('page') || 1,
            rows => 20,
            order_by => 'login'
        }
    );
    $c->stash->{users}    = $res;
    $c->stash->{pager}    = $res->pager;
    $c->stash->{template} = 'user/list.tt';
}

=item prefs

Main user preferences screen.

=cut


sub page_user :Private {
    my ($self,$c)=@_;
    my $user = $c->stash->{user};
    $c->stash->{template} = 'user/prefs.tt';
    my @proto = @{ $c->stash->{proto_pages} };
    my $page_user =
        $c->model("DBIC::Person")->get_user( $proto[0]->{name} || $c->stash->{page}->name );

    unless (
           $page_user
        && $user
        && (   $page_user->id eq $user->id
            || $user->is_admin() )
        )
    {
        my $c->stash->{message}  = $c->loc('Cannot find that user.');
        $c->stash->{template} = 'message.tt';
        $c->detach('/default');
    }
    $c->stash->{page_user}=$page_user;
}

sub prefs : Global FormConfig {
    my ( $self, $c ) = @_;
    my $form =$c->stash->{form};
    $c->forward('page_user');
    my $page_user = $c->stash->{page_user};
    $form->model->default_values($c->stash->{user});
    if ( $form->submitted_and_valid ) {
        my $old_email=$page_user->email;
        $form->model->update($page_user);
        $c->stash->{message}=$c->loc('Updated preferences');
        if( $form->params->{email} ne $old_email ){
                $page_user->active(-1);
                $page_user->update;
                $c->forward('do_register',[$page_user]);
        }    }
}

=item password (/prefs/password')

Change password action.

B<template:> user/password.tt

=cut

sub password : Path('/prefs/password') FormConfig {
    my ( $self, $c ) = @_;
    $c->forward('page_user');
    my $page_user = $c->stash->{page_user};
    my $form=$c->stash->{form};
    if ( $form->submitted_and_valid) {
        # FIXME: Should be moved into a formfu validator
        unless ( $page_user->valid_pass( $form->params->{current} ) ) {
            $c->stash->{message} = $c->loc('Invalid password.');
            return;
        }
        $page_user->pass( $form->params->{pass} );
        $page_user->update();
        $c->stash->{message} = $c->loc('Your password has been updated');
    }
}

sub recover_pass : Global {
    my ( $self, $c ) = @_;
    return unless ( $c->req->method eq 'POST' );
    my $id = $c->req->param('recover');
    $c->stash->{user} =
        $c->model('DBIC::Person')->search( [ email => $id, login => $id ] )->first;
    my $user=$c->stash->{user};
    unless ($c->stash->{user}) {
        $c->flash->{message} = 'Could not recover password.';
        return $c->res->redirect( $c->uri_for('login') );
    }
    $c->stash->{password}  =  Text::Password::Pronounceable->generate( 6, 10 );
    if (
        $c->email(
            header => [
                From    => $c->config->{system_mail},
                To      => $user->login . ' <' . $user->email . '>',
                Subject => 'Your new password on ' . $c->config->{name},
            ],
            body => $c->view('TT')->render( $c, 'mail/reset_password.tt' ),
        )
        )
    {
        $user->pass($c->stash->{password});
        $user->update();
        $c->stash->{message} = $c->loc('Emailed you your new password.');
    }
    else {
        $c->stash->{message} = $c->loc('Error occurred while emailing you your new password.');
    }
    $c->forward('login');
}

=item register (/.register)

Show new user registration form.

B<template:> user/register.tt

=cut

sub register : Global FormConfig {
    my ( $self, $c ) = @_;

    if ( !$c->pref('open_registration') ) {
        $c->stash->{template} = 'message.tt';
        return $c->stash->{message} = $c->loc('Registration is closed!');
    }

    $c->stash->{template} = 'user/register.tt';
    $c->stash->{message} =
        $c->loc('Please fill in the following information to register. All fields are mandatory.');
    my $form = $c->stash->{form};
    $c->stash->{user} = $c->model('DBIC::Person')->new_result( {} );
    $c->stash->{template}  = 'user/register.tt';

    $form->model->default_values($c->stash->{user});
    if ( $form->submitted_and_valid ) {
        $c->stash->{user}->active(-1);
        $form->model->update( $c->stash->{user} );
        $c->stash->{user}->insert();
        $c->forward( 'do_register', [$c->stash->{user}] );

    }
}

=item do_register (/.register)

New user registration processing.

B<template:> user/password.tt /  user/validate.tt

=cut

sub do_register : Private {
    my ( $self, $c, $user ) = @_;
    $c->forward('/user/login');
    $c->pref('entropy') || $c->pref( 'entropy', rand );
    $c->stash->{secret} = md5_hex( $user->email . $c->pref('entropy') );
    if (
        $c->email(
            header => [
                From    => $c->config->{system_mail},
                To      => $user->email,
                Subject => $c->loc('~[x~] New User Validation',$c->pref('name')||'MojoMojo'),
            ],
            body => $c->view('TT')->render( $c, 'mail/validate.tt' ),
        )
        )
    {
    }
    else {
        $c->stash->{error} = $c->loc('An error occourred. Sorry.');
    }
    $c->stash->{user}     = $user;
    $c->stash->{template} = 'user/validate.tt';
}

=item validate (/.validate)

Validation of user email. Will accept a md5_hex mailed to the user
earlier. Non-validated users will only be able to log out.

=cut

sub validate : Global {
    my ( $self, $c, $user, $check ) = @_;
    $user = $c->model("DBIC::Person")->find( { login => $user } );
    if ( $user and $check eq md5_hex( $user->email . $c->pref('entropy') ) ) {
        $user->active(1);
        $user->update();
        if ( $c->stash->{user} ) {
            $c->res->redirect( $c->uri_for( '/', $c->stash->{user}->link, '.edit' ) );
        }
        else {
            $c->stash->{message} =
                $c->loc('Welcome, x your email is validated. Please log in.',$user->name);
            $c->stash->{template} = 'user/login.tt';
        }
        return;
    }
    $c->stash->{template} = 'user/validate.tt';
}

=item reconfirm

Send the confirmation mail again to another address.

=cut

sub reconfirm : Local {
    my ( $self, $c ) = @_;
    $c->detach('/default') unless $c->req->method eq 'POST';
    if ( $c->user->obj->email ne $c->req->param('email') ) {
        if ( $c->model('DBIC::Person')->search( { email => $c->req->param('email') } )->count )
        {
            return $c->stash->{error} = $c->loc('That mail is already in use');
        }
    }
    my $user = $c->user->obj;
    $user->email( $c->req->params->{email} );
    $user->active(-1);
    $user->update();
    $c->forward( 'do_register', [$user] );
    $c->flash->{message} = $c->loc('confirmation message resent');
    $c->res->redirect( $c->uri_for('/') );
}

=item profile .profile

Show user profile.

=cut

sub profile : Global {
    my ( $self, $c ) = @_;
    my $page  = $c->stash->{page};
    my $login = (
          $c->stash->{proto_pages}[-1]
        ? $c->stash->{proto_pages}[-1]->{name}
        : $page->name
    );
    my $user = $c->model('DBIC::Person')->get_user($login);
    if ($user) {
        $c->stash->{person}   = $user;
        $c->stash->{template} = 'user/profile.tt';
    }
    else {
        $c->stash->{template} = 'message.tt';
        $c->stash->{message}  = $c->loc('User x not found!',$login);
    }
}

sub editprofile : Global FormConfig {
    my ( $self, $c ) = @_;
    my $form=$c->stash->{form};
    my $page = $c->stash->{page};
    my $user = $c->model('DBIC::Person')->get_user(
          $c->stash->{proto_pages}[-1]
        ? $c->stash->{proto_pages}[-1]->{name_orig}
        : $page->name
    );
    if (
           $user
        && $c->stash->{user}
        && (   $c->stash->{user}->is_admin
            || $user->id eq $c->stash->{user}->id )
        )
    {
        if ($form->submitted_and_valid) {
            $form->model->update($user);
            $c->res->redirect($c->uri_for('profile'));
        }
        $form->model->default_values($user) unless $form->submitted;
    }
    else {
        $c->stash->{template} = 'message.tt';
        $c->stash->{message}  = $c->loc('User not found!');
    }

}

sub do_editprofile : Global {
    my ( $self, $c ) = @_;
    $c->form(
        required           => [qw(name email)],
        optional           => [ $c->model("DBIC::Person")->result_source->columns ],
        defaults           => { gender => undef },
        constraint_methods => { born => ymd_to_datetime(qw(birth_year birth_month birth_day)) },
        untaint_all_constraints => 1,
    );

    if ( $c->form->has_missing ) {
        $c->stash->{message} =
              $c->loc('You have to fill in all required fields.')
            . $c->loc('the following are missing:').' <b>'
            . join( ', ', $c->form->missing() ) . '</b>';
    }
    elsif ( $c->form->has_invalid ) {
        $c->stash->{message} =
            $c->loc('Some fields are invalid. Please correct them and try again:');
    }
    else {
        my $page = $c->stash->{page};
        my $user = $c->model('DBIC::Person')->get_user(
              $c->stash->{proto_pages}[-1]
            ? $c->stash->{proto_pages}[-1]->{name_orig}
            : $page->name
        );
        $user->set_columns( $c->form->{valid} );
        $user->update();
        return $c->forward('profile');
    }
    $c->forward('editprofile');
}

=back

=head1 AUTHOR

David Naughton <naughton@cpan.org>, 
Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This library is free software . You can redistribute it and/or modify
it under the same terms as perl itself.

=cut

1;
