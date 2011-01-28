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
		$self->login() or $Geni::errstr = "Login failed!" && return 0;
		$Geni::geni = $self;
		return $self;
	}
}

sub user {
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

sub tree_conflicts() {
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
sub _project_profiles_url($) {
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

sub profile {
	my $self = shift;
	if (!$self->{resolved}) {
		$self->_resolve(
			$Geni::geni->_profile_get_immediate_family_url($self->{focus})
		);
	}
	return $self->{profile};
}

sub managers {
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

sub type {
	my $self = shift;
	return $self->{type};
}

sub actor {
	my $self = shift;
	return Geni::Profile->new(id => $self->{actor});
}

sub fetch_list {
	my $self = shift;
	if (!$self->{resolved}) {
		$self->_resolve(
			$Geni::geni->_profile_get_immediate_family_url($self->profile()->id())
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
				if (defined ${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->id() }}{"rel"} &&
					${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->id() }}{"rel"} eq "child"){

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
				} elsif (defined ${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->id() }}{"rel"} &&
					${$j->{nodes}->{$nodetype}->{edges}->{ $self->{profile}->id() }}{"rel"} eq "partner"){

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
	# TODO: Do this if the current user is a curator
	#if (defined $self->{public} && $self->{public} eq "false") {
	#	$self->_check_public();
	#}
	return $self;
}

sub id {
	my $self = shift;
	return $self->{id} ? $self->{id} : $self->{guid};
}

sub first_name {
	my $self = shift;
	return $self->{first_name};
}

sub middle_name {
	my $self = shift;
	return $self->{middle_name};
}

sub last_name {
	my $self = shift;
	return $self->{last_name};
}

sub maiden_name {
	my $self = shift;
	return $self->{maiden_name};
}

sub display_name {
	my $self = shift;
	return $self->{name};
}

sub birth_date {
	my $self = shift;
	return $self->{birth_date};
}

sub birth_location {
	my $self = shift;
	return $self->{birth_location};
}

sub death_date {
	my $self = shift;
	return $self->{death_date};
}

sub death_location{
	my $self = shift;
	return $self->{death_location};
}

sub locked {
	my $self = shift;
	return $self->{locked};
}

sub big_tree {
	my $self = shift;
	return ($self->{big_tree} =~ /true/i);
}

sub claimed {
	my $self = shift;
	return ($self->{claimed} =~ /true/i);
}

sub public {
	my $self = shift;
	return ($self->{public} =~ /true/i);
}

sub gender {
	my $self = shift;
	return $self->{first_name};
}

sub creator {
	my $self = shift;
	return Geni::Profile->new(id => $self->{created_by});
}

sub guid {
	my $self = shift;
	return $self->{guid};
}

sub managers {
	my $self = shift;
	return $self->{managers};
}

sub _add_managers {
	my $self = shift;
	push @{$self->{managers}}, @_;
	return $self;
}

sub _check_public {
	my $self = shift;
	if (defined $Geni::geni && defined $self->{public} && $self->{public} eq "false") {
		my $j = $Geni::geni->_post_results($Geni::geni->_check_public_url($self->id()));
		return $j->{public} =~ /true/i;
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

sub focus {
	my $self = shift;
	return $self->{focus};
}

sub parents {
	my $self = shift;
	return @{$self->{parents}};
}

sub children {
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

=head2 Geni

=head3 Geni->new($username, $password)

Returns a Geni object or 0 if login credentials were not supplied or login
fails. Optional argument "collaborators" specifies whether to retrieve
collaborator conflicts or only your own.

=head3 $geni->user()

Get username the script is currently logged in as.

=head3 $geni->tree_conflicts()

Returns a Geni::List of Geni::Conflict objects.  Access by using
$list->has_next() and $list->next().

	my $list = $geni->tree_conflicts();
	while(my $conflict = $list->next()){
		# do something
	}

=head2 Geni::Conflict

This object should only be created internally by this module. It is used to group profiles that may be duplicates of each other and document the relationships between those profiles.

=head3 $conflict->profile()

Returns a Geni::Profile object describing the focal profile of this conflict.

=head3 $conflict->managers()

TODO: Make sure this is accurate

Returns a Geni::List of Geni::Profile objects describing the managers involved in this conflict.

=head3 $conflict->type()

Returns the type of conflict in the form "parent" or "partner".

=head3 $conflict->actor()

Returns a Geni::Profile describing the last Geni user who acted upon this conflict.

=head3 $conflict->fetch_list()

Returns a Geni::List of Geni::Profile objects describing, respectively, the spouses, parents, children, and siblings of the conflict's focal profile.

=head2 Geni::Profile

Describes a single Geni profile.

=head3 $profile->id()

Get the new-style ID of the profile, which is in the form "profile-0000000000", or if it is not known, the old-style ID, which is in the form "G00000000000000000".

=head3 $profile->first_name()
=head3 $profile->middle_name()
=head3 $profile->last_name()
=head3 $profile->maiden_name()
=head3 $profile->display_name()
=head3 $profile->gender()
=head3 $profile->birth_date()
=head3 $profile->birth_location()
=head3 $profile->death_date()
=head3 $profile->death_location()
=head3 $profile->locked()

Returns 1 if profile is locked, 0 if profile is not locked.

=head3 $profile->big_tree()

Returns 1 if the profile is in the Big Tree, 0 if it is not. 

=head3 $profile->claimed()

Returns 1 if the profile is claimed, i. e., a living Geni user, 0 if it is not. 

=head3 $profile->public()

Returns 1 if the profile is public, 0 if it is private.

=head3 $profile->creator()

Returns the Geni::Profile of the profile's creator.

=head3 $profile->guid()

Returns the profile's old-style ID in the form "G00000000000000000" if we have it.

=head3 $profile->managers()

TODO: Change this to a Geni::List of Geni::Profile objects.

Returns an array of profile ids representing the managers of the profile.

=head2 Geni::Family

This class may not ever be used and may be deleted.

=head2 Geni::List

TODO: see if there is any need for an existing iterable type class instead of defining our own, and weigh the benefits of an additional dependency.

A class representing an iterable group of items of the same type.

=head3 $list->has_next()

Return 1 if there are items left in the list, 0 if the list is empty.

=head3 $list->next()

Delete and return the next object in the list.

=head3 $list->add()

Add an item to the end of the list.

=head3 $list->count()

Return the number of items remaining in the list.

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
