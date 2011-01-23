use 5.001;
use strict;
use warnings;
use HTTP::Cookies;
use HTTP::Response;
use LWP::UserAgent;
use JSON;
use vars qw($VERSION $errstr);

##############################################################################
# Geni class
##############################################################################
{
package Geni;
my $VERSION = '0.01';
# Profile APIs
# Returns a data structure containing the immediate family of the requested
# profile.
sub _profile_get_immediate_family_url {
	"https://www.geni.com/api/profile/immediate-family?only_ids=true";
}
# Returns a list of requested profile merges for the current user.
sub _profile_get_merges_url {
	"https://www.geni.com/api/profile/merges?only_ids=true";
}
# Returns a list of data conflicts for the current user.
sub _profile_get_data_conflicts_url {
	"https://www.geni.com/api/profile/data-conflicts?only_ids=true";
}
# Returns a list of tree conflicts for the current user.
sub _profile_get_tree_conflicts_url {
	"https://www.geni.com/api/profile/tree-conflicts?only_ids=true";
}
# Returns a list of other profiles in our system matching a given profile.
# Only users who have upgraded to a Geni Pro Account can see this list.
sub _profile_get_tree_matches_url {
	"https://www.geni.com/api/profile/tree-matches?only_ids=true";
}
# Will merge two profiles together if you have permission, or it will create a
# requested merge if you don’t have edit permission on both profiles.
sub _profile_do_merge_url($$) {
	"https://www.geni.com/api/profile-$_[0]/merge/profile-$_[1]?only_ids=true";
}
# Project APIs
# Returns a list of users collaborating on a project.
sub _project_get_collaborators_url {
	"https://www.geni.com/api/project-6/collaborators?only_ids=true";
}
# Returns a list of profiles tagged in a project.
sub _project_get_profiles_url {
	"https://www.geni.com/api/project-6/profiles?only_ids=true";
}
# Returns a list of users following a project.
sub _project_get_followers_url {
	"https://www.geni.com/api/project-6/followers?only_ids=true";
}

sub new {
	my $class = shift;
	my $self = {};
	($self->{user}, $self->{pass}) = (shift, shift);
	$self->{json} = new JSON;
	if (!$self->{user} || !$self->{pass}){
		$Geni::errstr = "Username and password are required parameters to "
			. "Geni::new().";
		return 0;
	} else {
		bless $self, $class;
		return $self;
	}
}

sub username {
	my $self = shift;
	return $self->{user};
}

sub login {
	my $self = shift;
	$self->{ua} = LWP::UserAgent->new();
	$self->{ua}->cookie_jar(HTTP::Cookies->new());
	my $res = $self->{ua}->post("https://www.geni.com/login/in?username="
		. $self->{user} . "&password=" . $self->{pass});
	return $res->content =~ /home">redirected/;
}

sub get_tree_conflicts {
	my $self = shift;
	my $res;
	my $list = Geni::List->new();
	if ($_{collaborators}){
		$res = $self->{ua}->get($self->_profile_get_tree_conflicts_url());
	} else {
		$res = $self->{ua}->get($self->_profile_get_tree_conflicts_url()
			. "?collaborators=true");
	}
	if ($res->is_success){
		my $content = $res->decoded_content;
		$res = $self->{json}->allow_nonref->relaxed->decode($content);
		for (@{$res->{results}}){
			my $c = Geni::Conflict->new(
				new_id => $_->{profile},
				type => $_->{issue_type},
				actor => $_->{actor}
			);
			$c->add_managers(@{$res->{managers}}); 
			$list->add($c);
		}
		return $list;
	}
	return 0;
}
} # end Geni class

##############################################################################
# Geni::Conflict class
##############################################################################
{
package Geni::Conflict;

sub new {
	my $class = shift;
	my $self = { @_ };
	bless $self, $class;
	return $self;
}

sub get_profile {
	my $self = shift;
	return Geni::Profile->new($self->{new_id});
}

sub get_managers {
	my $self = shift;
	my $list = Geni::List->new();
	foreach(@{$self->{managers}}){
		$list->add(Geni::Profile->new($_));
	}
	return $list;
}

sub get_type {
	my $self = shift;
	return $self->{type};
}

sub get_actor {
	my $self = shift;
	return Geni::Profile->new($self->{actor});
}

sub add_managers {
	my $self = shift;
	push @{$self->{managers}}, @_;
	return $self;
}
} # end Geni::Conflict class

##############################################################################
# Geni::Profile class
##############################################################################
{
package Geni::Profile;

sub new {
	my $class = shift;
	my $self = {
		id => shift
	};
	bless $self, $class;
	return $self;
}
} # end Geni::Profile class


##############################################################################
# Geni::List class
##############################################################################
{
package Geni::List;

sub new {
	my $class = shift;
	my $self = {};
	@{$self->{items}} = @_;
	bless $self, $class;
	return $self;
}

sub get_next {
	my $self = shift;
	return shift @{$self->{items}}
}

sub has_next {
	my $self = shift;
	return $#{$self->{items}} > 0;
}

sub add {
	my $self = shift;
	push @{$self->{items}}, @_;
}

sub count {
	my $self = shift;
	return $#{$self->{items}};
}

} # end Geni::List class


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geni - Perl extension for Geni.com

=head1 SYNOPSIS

	use Geni;
	my $geni = new Geni($username, $password);
	my @conflicts = $geni->conflicts();

=head1 DESCRIPTION

Use this module to manipulate Geni profiles.

=head1 METHODS

=head2 $geni->new($username, $password)
=cut

=head2 $geni->login()
=cut

=head2 $geni->username()

Returns Geni username.

=cut

=head1 SEEALSO

GitHub

=head1 AUTHOR

Erin Spiceland <lt>erin@thespicelands.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2011 by Erin Spiceland

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
