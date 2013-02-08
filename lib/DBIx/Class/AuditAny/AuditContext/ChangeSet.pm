package DBIx::Class::AuditAny::AuditContext::ChangeSet;
use strict;
use warnings;

# VERSION
# ABSTRACT: Default 'ChangeSet' context object class for DBIx::Class::AuditAny

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'DBIx::Class::AuditAny::AuditContext';

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object);


use Time::HiRes qw(gettimeofday tv_interval);

sub _build_tiedContexts { [] }
sub _build_local_datapoint_data { 
	my $self = shift;
	return { map { $_->name => $_->get_value($self) } $self->get_context_datapoints('set') };
}

has 'changes', is => 'ro', isa => ArrayRef, default => sub {[]};
has 'finished', is => 'rw', isa => Bool, default => sub{0}, init_arg => undef;

has 'changeset_ts', is => 'ro', isa => InstanceOf['DateTime'], lazy => 1, default => sub { (shift)->get_dt };
has 'start_timeofday', is => 'ro', default => sub { [gettimeofday] };

has 'changeset_finish_ts', is => 'rw', isa => Maybe[InstanceOf['DateTime']], default => sub{undef};
has 'changeset_elapsed', is => 'rw', default => sub{undef};

sub BUILD {
	my $self = shift;
	
	# Init
	$self->changeset_ts;
}

sub add_changes { push @{(shift)->changes}, @_ }
sub all_changes { @{(shift)->changes} }
sub count_changes { scalar(@{(shift)->changes}) }
sub all_column_changes { map { $_->all_column_changes } (shift)->all_changes }

sub finish {
	my $self = shift;
	die "Not active changeset" unless ($self == $self->AuditObj->active_changeset);
	$self->AuditObj->finish_changeset;
	return $self->mark_finished;
}

sub mark_finished {
	my $self = shift;
	return if ($self->finished);
	
	$self->changeset_finish_ts($self->get_dt);
	$self->changeset_elapsed(tv_interval($self->start_timeofday));
	
	return $self->finished(1);
}

1;