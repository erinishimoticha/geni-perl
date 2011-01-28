use 5.001;
use strict;
use warnings;
use HTTP::Cookies;
use HTTP::Response;
use LWP::UserAgent;
use JSON;
use utf8;
use vars qw($VERSION $errstr);

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

##############################################################################
# Geni class
##############################################################################
{
package Geni;
our $VERSION = '0.01';
our $geni;
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
		$Geni::geni = $self;
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

sub get_tree_conflicts() {
	my $self = shift;
	my $list = Geni::List->new();
	$self->_populate_tree_conflicts($list) or
		$Geni::errstr = "Attempt to [re]populate tree conflict list failed." && return 0;
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
sub _profile_get_tree_conflicts_url($) {
	my $self = shift;
	"https://www.geni.com/api/profile/tree-conflicts?only_ids=true"
		. ($self->{collaborators} ? "&collaborators=true" : "") . "&page=" . (shift or '1');
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

sub _check_public_url($) {
	"https://www.geni.com/api/profile-$_[1]/check-public";
}

sub _get_results($) {
	my ($self, $url) = (shift, shift);
	my $res = $self->{ua}->get($url);
	if ($res->is_success){
		return $self->{json}->allow_nonref->relaxed->decode($res->decoded_content);
	} else {
		$Geni::errstr = $res->status_line;
		return 0;
	}
}

sub _post_results($) {
	my ($self, $url) = (shift, shift);
	my $res = $self->{ua}->post($url);
	if ($res->is_success){
		return $self->{json}->allow_nonref->relaxed->decode($res->decoded_content);
	} else {
		$Geni::errstr = $res->status_line;
		return 0;
	}
}

sub _populate_tree_conflicts($$){
	my ($self, $list) = (shift, shift);
	my $j = $self->_get_results(
			$list->{next_page_url} or $self->_profile_get_tree_conflicts_url(1)
		) or return 0;
	foreach(@{$j->{results}}){
		my $c = Geni::Conflict->new(
			focus => $_->{profile},
			type => $_->{issue_type},
			actor => $_->{actor}
		);
		$c->_add_managers(@{$_->{managers}}); 
		$list->add($c);
	}
	$list->{cur_page_num} = $j->{page};
	$list->{next_page_url} = $j->{next_page};
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
	$self->{profile} = Geni::Profile->new(id => $self->{focus});
	$self->{parents} = Geni::List->new();
	$self->{siblings} = Geni::List->new();
	$self->{spouses} = Geni::List->new();
	$self->{children} = Geni::List->new();
	$self->{parents}->{type} = "parents";
	$self->{siblings}->{type} = "siblings";
	$self->{spouses}->{type} = "spouses";
	$self->{children}->{type} = "children";
	bless $self, $class;
	return $self;
}

sub get_profile {
	my $self = shift;
	if (!$self->{resolved}) {
		$self->_resolve(
			$Geni::geni->_profile_get_immediate_family_url($self->{focus})
		);
	}
	return $self->{profile};
}

sub get_managers {
	my $self = shift;
	if (!$self->{resolved}) {
		$self->_resolve(
			$Geni::geni->_profile_get_immediate_family_url($self->{focus})
		);
	}
	my $list = Geni::List->new();
	foreach my $id (@{$self->{managers}}){
		$id =~ /^profile-/i
			? $list->add(Geni::Profile->new( id => $id))
			: $list->add(Geni::Profile->new( guid => $id));
	}
	return $list;
}

sub get_type {
	my $self = shift;
	return $self->{type};
}

sub get_actor {
	my $self = shift;
	return Geni::Profile->new(id => $self->{actor});
}

sub fetch_list {
	my $self = shift;
	if (!$self->{resolved}) {
		$self->_resolve(
			$Geni::geni->_profile_get_immediate_family_url($self->get_profile()->get_id())
		);
	}
	if ( defined $self->{spouses} && $self->{spouses}->count() > 0 ) {
		return delete $self->{spouses};
	} elsif ( defined $self->{parents} && $self->{parents}->count() > 0 ) {
		return delete $self->{parents};
	} elsif ( defined $self->{children} && $self->{children}->count() > 0 ) {
		return delete $self->{children};
	} elsif ( defined $self->{siblings} && $self->{siblings}->count() > 0 ) {
		return delete $self->{siblings};
	} else {
		return 0;
	}
}


sub _resolve($){
	my $self = shift;
	my $url = shift;
	my (%temp_edges, $temp_profile);
	my $j = $Geni::geni->_get_results($url)
		or return 0;
	my @managers = delete @{$j->{focus}->{managers}}[0..5000];
	$self->{profile} = Geni::Profile->new(
			map { $_, ${$j->{focus}}{$_} } keys %{$j->{focus}});
	$self->{profile}->_add_managers(@managers);
	foreach my $nodetype (keys %{$j->{nodes}}) {
		if ($nodetype =~ /union-(\d+)/i) {
			foreach my $member (keys %{$j->{nodes}->{$nodetype}->{edges}}){
				# if the focal profile is listed as a child in this union
				if (defined ${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->get_id() }}{"rel"} &&
					${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->get_id() }}{"rel"} eq "child"){

					# if the current profile is a child, we've found a sibling or duplicate of our focal profile
					if (${$j->{nodes}->{$nodetype}->{edges}->{$member}}{"rel"} eq "child") {
						%temp_edges = %{$j->{nodes}->{$member}->{edges}};
						$temp_profile = Geni::Profile->new(
							map { $_, ${$j->{nodes}->{$member}}{$_} } keys %{$j->{nodes}->{$member}});
						%{$temp_profile->{edges}} = %temp_edges;
						$self->{siblings}->add($temp_profile);

					# if the current profile is a child, we've found a parent of our focal profile
					}elsif (${$j->{nodes}->{$nodetype}->{edges}->{$member}}{"rel"} eq "partner") {
						%temp_edges = %{$j->{nodes}->{$member}->{edges}};
						$temp_profile = Geni::Profile->new(
							map { $_, ${$j->{nodes}->{$member}}{$_} } keys %{$j->{nodes}->{$member}});
						%{$temp_profile->{edges}} = %temp_edges;
						$self->{parents}->add($temp_profile);
					}

				# if the focal profile is listed as a partner in this union
				} elsif (defined ${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->get_id() }}{"rel"} &&
					${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->get_id() }}{"rel"} eq "partner"){

					# if the current profile is a child, we've found a child of our focal profile
					if (${$j->{nodes}->{$nodetype}->{edges}->{$member}}{"rel"} eq "child") {
						%temp_edges = %{$j->{nodes}->{$member}->{edges}};
						$temp_profile = Geni::Profile->new(
							map { $_, ${$j->{nodes}->{$member}}{$_} } keys %{$j->{nodes}->{$member}});
						%{$temp_profile->{edges}} = %temp_edges;
						$self->{children}->add($temp_profile);

					# if the current profile is a child, we've found a spouse or duplicate of our focal profile
					}elsif (${$j->{nodes}->{$nodetype}->{edges}->{$member}}{"rel"} eq "partner") {
						%temp_edges = %{$j->{nodes}->{$member}->{edges}};
						$temp_profile = Geni::Profile->new(
							map { $_, ${$j->{nodes}->{$member}}{$_} } keys %{$j->{nodes}->{$member}});
						%{$temp_profile->{edges}} = %temp_edges;
						$self->{spouses}->add($temp_profile);
					}
				}
			}
		}
	}
	$self->{resolved} = 1;
}


sub _add_managers {
	my $self = shift;
	push @{$self->{managers}}, @_;
	return $self;
}

} # end Geni::Conflict class

##############################################################################
# Geni::Profile class
# managers (array), big_tree (true, false), first_name, middle_name, last_name
# maiden_name, birth_date, birth_location, death_date, death_location, gender, 
# url, public, locked (true, false), created_by, guid, name, id
##############################################################################
{
package Geni::Profile;
our $VERSION = $Geni::VERSION;

sub new {
	my $class = shift;
	my $self;
	$self = { @_ };
	bless $self, $class;
	if (defined $self->{public} && $self->{public} eq "false") {
		$self->_check_public();
	}
	return $self;
}

sub get_id {
	my $self = shift;
	return $self->{id} ? $self->{id} : $self->{guid};
}

sub get_first_name {
	my $self = shift;
	return $self->{first_name};
}

sub get_middle_name {
	my $self = shift;
	return $self->{middle_name};
}

sub get_last_name {
	my $self = shift;
	return $self->{last_name};
}

sub get_maiden_name {
	my $self = shift;
	return $self->{maiden_name};
}

sub get_display_name {
	my $self = shift;
	return $self->{name};
}

sub get_birth_date {
	my $self = shift;
	return $self->{birth_date};
}

sub get_birth_location {
	my $self = shift;
	return $self->{birth_location};
}

sub get_death_date {
	my $self = shift;
	return $self->{death_date};
}

sub get_death_location{
	my $self = shift;
	return $self->{death_location};
}

sub get_locked {
	my $self = shift;
	return $self->{locked};
}

sub is_in_big_tree {
	my $self = shift;
	return ($self->{big_tree} =~ /true/i);
}

sub is_claimed {
	my $self = shift;
	return ($self->{claimed} =~ /true/i);
}

sub is_public {
	my $self = shift;
	return ($self->{public} =~ /true/i);
}

sub get_gender {
	my $self = shift;
	return $self->{first_name};
}

sub get_creator {
	my $self = shift;
	return Geni::Profile->new(id => $self->{created_by});
}

sub get_guid {
	my $self = shift;
	return $self->{guid};
}

sub _add_managers {
	my $self = shift;
	push @{$self->{managers}}, @_;
	return $self;
}

sub _check_public {
	my $self = shift;
	if (defined $Geni::geni && defined $self->{public} && $self->{public} eq "false") {
		my $j = $Geni::geni->_post_results($Geni::geni->_check_public_url($self->get_id()));
	}
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

sub add {
	my $self = shift;
	if ((shift) == "child"){
		push @{$self->{children}}, (shift);
	} else {
		push @{$self->{parents}}, (shift);
	}
}

sub get_focus {
	my $self = shift;
	return $self->{focus};
}

sub get_parents {
	my $self = shift;
	return @{$self->{parents}};
}

sub get_children {
	my $self = shift;
	return @{$self->{childred}};
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
	if ($self->count() == 1) {
		if(${$self->{items}}[0] && ref(${$self->{items}}[0]) eq "Geni::Conflict"){
			$Geni::geni->_populate_tree_conflicts($self);
		}
	}
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

=head2 $geni->get_user()

Get username the script is currently logged in as.

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
