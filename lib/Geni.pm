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
our $VERSION = '0.01';
# Profile APIs
# Returns a data structure containing the immediate family of the requested
# profile.
sub new {
	my $class = shift;
	my $self = { @_ };
	($self->{user}, $self->{pass}) = (shift, shift);
	$self->{json} = new JSON;
	if (!$self->{user} || !$self->{pass}){
		$Geni::errstr = "Username and password are required parameters to "
			. "Geni::new().";
		return 0;
	} else {
		bless $self, $class;
		$self->login() or $Geni::errstr = "Login failed!";
		return $self;
	}
}

sub get_user {
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
	my $list = Geni::List->new();
	my $j = $self->_get_results(_profile_get_tree_conflicts_url())
		or return 0;
	foreach(@{$j->{results}}){
		my $c = Geni::Conflict->new(
			geni => $self,
			focus => $_->{profile},
			type => $_->{issue_type},
			actor => $_->{actor}
		);
		$c->_add_managers(@{$_->{managers}}); 
		$list->add($c);
	}
	$list->{cur_page_num} = $j->{page};
	$list->{next_page_url} = $j->{next_page};
	$list->{geni} = $self;
	return $list;
}

# Returns a data structure containing the immediate family of the requested profile.
sub _profile_get_immediate_family_url($) {
	my ($self, $profile) = (shift, shift);
	$profile = $profile ? $profile : "profile";
	"https://www.geni.com/api/$profile/immediate-family?only_ids=true";
}
# Returns a list of requested profile merges for the current user.
sub _profile_get_merges_url {
	my $self = shift;
	"https://www.geni.com/api/profile/merges?only_ids=true"
		. ($self->{collaborators} ? "&collaborators=true" : "");
}
# Returns a list of data conflicts for the current user.
sub _profile_get_data_conflicts_url {
	my $self = shift;
	"https://www.geni.com/api/profile/data-conflicts?only_ids=true"
		. ($self->{collaborators} ? "&collaborators=true" : "");
}
# Returns a list of tree conflicts for the current user.
sub _profile_get_tree_conflicts_url {
	my $self = shift;
	"https://www.geni.com/api/profile/tree-conflicts?only_ids=true"
		. ($self->{collaborators} ? "&collaborators=true" : "");
}
# Returns a list of other profiles in our system matching a given profile.
# Only users who have upgraded to a Geni Pro Account can see this list.
sub _profile_get_tree_matches_url($) {
	"https://www.geni.com/api/$_[1]/tree-matches?only_ids=true";
}
# Will merge two profiles together if you have permission, or it will create a
# requested merge if you don’t have edit permission on both profiles.
sub _profile_do_merge_url($$) {
	"https://www.geni.com/api/$_[1]/merge/$_[2]?only_ids=true";
}
# Project APIs
# Returns a list of users collaborating on a project.
sub _project_get_collaborators_url($) {
	"https://www.geni.com/api/project-$_[1]/collaborators?only_ids=true";
}
# Returns a list of profiles tagged in a project.
sub _project_get_profiles_url($) {
	"https://www.geni.com/api/project-$_[1]/profiles?only_ids=true";
}
# Returns a list of users following a project.
sub _project_get_followers_url($) {
	"https://www.geni.com/api/project-$_[1]/followers?only_ids=true";
}

sub _get_results($$) {
	my ($self, $url) = (shift, shift);
	my $res = $self->{ua}->get($url);
	#open LOG, ">>family.log";
	#print LOG "$url\n";
	if ($res->is_success){
		my $r = $res->decoded_content;
		#print LOG "$r\n";
		my $j = $self->{json}->allow_nonref->relaxed->decode($r);#res->decoded_content);
		return $j;
	} else {
		$Geni::errstr = $res->status_line && return 0;
		#print LOG "$Geni::errstr\n";
	}
	#close LOG;
}

} # end Geni class

##############################################################################
# Geni::Conflict class
##############################################################################
{
package Geni::Conflict;
our $VERSION = $Geni::VERSION;

sub new {
	my $class = shift;
	my $self = { @_ };
	bless $self, $class;
	return $self;
}

sub get_profile {
	my $self = shift;
	return Geni::Profile->new(new_id => $self->{focus}, geni => $self->{geni});
}

sub get_managers {
	my $self = shift;
	my $list = Geni::List->new();
	foreach my $id (@{$self->{managers}}){
		$id =~ /^profile-/i
			? $list->add(Geni::Profile->new( new_id => $_, geni => $self->{geni}))
			: $list->add(Geni::Profile->new( old_id => $_, geni => $self->{geni}));
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

sub get_page_num {
	my $self = shift;
	return $self->{cur_page_num};
}

sub fetch_conflict_array {
	my $self = shift;
	my $profile = $self->get_profile();
	print "profile is $profile\n";
	if($#{$profile->{relationships}} <= 0){
		#print "url from within conflicts ", $self->{geni}->_profile_get_immediate_family_url($profile->get_id()), "\n";
		my $j = $self->{geni}->_get_results($self->{geni}->_profile_get_immediate_family_url($profile->get_id()))
			or return 0;
		my @managers = delete(@{$j->{focus}->{managers}}[0..5000]);
		print "focus is ", @{$j->{focus}}, "\n";
		#$self->{profile} = Geni::Profile->new(@{$j->{focus}});#, geni => $self->{geni});
		#$self->{profile}->_add_managers(@managers);
		foreach my $node (@{$j->{nodes}}){
			print "node is $_\n";
		}
		
		#foreach(@{$j->{results}}){
		#	print ".\n";
		#	my $c = Geni::Conflict->new(
		#		geni => $self,
		#		new_id => $_->{profile},
		#		type => $_->{issue_type},
		#		actor => $_->{actor}
		#	);
		#	$c->_add_managers(@{$_->{managers}}); 
		#	$list->add($c);
		#}
		return @{$j->{results}};
	}
	return 0;
}

sub _add_managers {
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
our $VERSION = $Geni::VERSION;

sub new {
	my $class = shift;
	print "odd numbered array is @_\n";
	my $self = { @_ };
	bless $self, $class;
	return $self;
}

sub get_id(){
	my $self = shift;
	return $self->{new_id} ? $self->{new_id} : $self->{old_id};
}

sub _add_managers {
	my $self = shift;
	push @{$self->{managers}}, @_;
	return $self;
}


} # end Geni::Profile class

##############################################################################
# Geni::Family class
##############################################################################
{
package Geni::Family;
our $VERSION = $Geni::VERSION;

sub new {
	my $class = shift;
	my $self = { @_ };
	bless $self, $class;
	return $self;
}

sub get_focus {
	my $self = shift;
	return $self->{focus};
}

sub get_parents {
	my $self = shift;
	return @{$self->{parents}};
}

sub get_siblings {
	my $self = shift;
	return @{$self->{siblings}};
}

} # end Geni::Family class

##############################################################################
# Geni::List class
##############################################################################
{
package Geni::List;
our $VERSION = $Geni::VERSION;

sub new {
	my $class = shift;
	my $self = {};
	@{$self->{items}} = @_;
	bless $self, $class;
	return $self;
}

sub get_next {
	my $self = shift;
	return shift @{$self->{items}};
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
=head1 NAME

Geni - Perl extension for Geni.com

=head1 SYNOPSIS

	use Geni;

	my $geni = new Geni($username, $password, collaborators => 1);

=head1 DESCRIPTION

Use this module to manipulate Geni profiles and examine profile conflicts.
This module contains four classes:  Geni, Geni::List, Geni::Profile, and
Geni::Conflict.

=head1 METHODS

=head2 Geni->new($username, $password)

Returns a Geni object or 0 if login credentials were not supplied or login
fails. Optional argument "collaborators" specifies whether to retrieve
collaborator conflicts or only your own.

=cut

=head2 $geni->get_tree_conflicts()

Returns a Geni::List of Geni::Conflict objects.  Access by using
$list->has_next() and $list->next().

	my $list = $geni->conflicts();
	while(my $conflict = $list->get_next()){
		# do something
	}

=cut

=head2 $geni->get_user()

Returns Geni username.

=cut

=head1 SEEALSO

GitHub: https://github.com/erinspice/geni-perl

=head1 AUTHOR

Erin Spiceland <lt>erin@thespicelands.com<gt>
Erin is a software developer and part-time amateur genealogist, as well as
a Geni Curator.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2011 by Erin Spiceland

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
