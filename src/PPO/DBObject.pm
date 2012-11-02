package DBObject;

# DBObject - persistent perl object

# $Id: DBObject.pm,v 1.25 2011-10-18 13:00:18 paczian Exp $

use strict;
use warnings;

use Carp;
use Class::ISA;

# definition of the different attribute types
use constant DB_SCALAR => 1;
use constant DB_OBJECT => 2;
use constant DB_ARRAY_OF_SCALARS => 3;
use constant DB_ARRAY_OF_OBJECTS => 4;

# export attribute types 
our @ISA = qw( Exporter );
our @EXPORT = qw( DB_SCALAR DB_OBJECT DB_ARRAY_OF_SCALARS DB_ARRAY_OF_OBJECTS );

# included during runtime because it uses the constants
require DBSQLArray;

1;

=pod

=head1 NAME

DBObject - persistent perl object

=head1 DESCRIPTION

TODO

=head1 METHODS

=over 4

=item * B<new> (I<dbmaster>)

Constructor method to initialise a DBObject with the DB master. I<dbmaster> 
expects a reference to a DBMaster object and is mandatory. If called on an 
existing perl object it will terminate and return itself.

=cut

sub new {
  my ($class, $dbmaster) = @_;

  return $class if (ref $class);
  
  (ref $dbmaster eq 'DBMaster')  
    || die "No DBMaster reference given: ".ref($dbmaster).".";
  my ($base_class) = ($class =~ /\w*::([^:]*$)/);
  my $self = { '_master' => $dbmaster,
	       '_class'  => $base_class,
	       '_table'  => $dbmaster->backend->get_table_name($base_class),
 	     };
  bless ($self, $class);
  return $self;
}


=pod

=item * B<isa> (I<perl_class_name>)

Returns reference to self (true) if the perl object is of the class I<perl_class_name>, 
otherwise undef. I<perl_class_name> is mandatory.

=cut

sub isa {
  my ($self, $class_name) = @_;
  return undef unless (ref $self and defined $class_name);
  foreach (Class::ISA::self_and_super_path(ref $self)) {
    return $self if ($_ eq $class_name);
  }
  return undef;
}


=pod

=item * B<attributes> ()

Returns a reference to a hash representing the attributes of this DBObject. 
Must be overwritten by subclass! Usually the database generator takes care of this.

=cut

sub attributes {
  die "Abstract method 'attributes' called in ".__PACKAGE__;
}


=pod

=item * B<indices> ()

Returns a list of all indices. 
Must be overwritten by subclass! Usually the database generator takes care of this.

=cut

sub indices {
  die "Abstract method 'indices' called in ".__PACKAGE__;
}


=pod

=item * B<unique_indices> ()

Returns a list of all unique indices. 
Must be overwritten by subclass! Usually the database generator takes care of this.

=cut

sub unique_indices {
  die "Abstract method 'unique_incides' called in ".__PACKAGE__;
}

=pod 

=item * B<is_index> (I<attribute_list>)

Returns true if the attribute list is an unique index, false otherwise.

=cut

sub is_index {
  my ($self, $attributes) = @_;

  foreach my $index (@{$self->unique_indices}) {
    if (join('', sort(@$index)) eq join('', sort(@$attributes))) {
      return $self;
    }
  }

  return undef;
}


=pod

=item * B<get_mandatory> ()

Returns a reference to a hash with all mandatory attributes of this DBObject. 
Must be overwritten by subclass! Usually the database generator takes care of this.

=cut

sub mandatory_attributes {
  die "Abstract method 'mandatory_attributes' called in ".__PACKAGE__;
}


=pod

=item * B<is_mandatory> (I<attribute_name>)

Returns a reference to self (true) if the attribute called I<attribute_name> is 
mandatory, undef else. I<attribute_name> is mandatory. This method uses the 
autogenerated method B<attributes>.

=cut

sub is_mandatory {
  my ($self, $attribute_name) = @_;
  
  return $self if ($self->attributes->{$attribute_name}->[2]);
  return undef;

}


=pod

=item * B<has_default> (I<attribute_name>)

Returns the default for the attribute I<attribute_name> if defined, undef else.
I<attribute_name> is mandatory. This method uses the autogenerated method B<attributes>.

=cut

sub has_default {
  my ($self, $attribute_name) = @_;  
  return $self->attributes->{$attribute_name}->[3];
}


=pod

=item * B<create> (I<values>)

Create a new object tied to the database backend. I<values> is mandatory and expects 
a hash reference of key - value pairs. The method checks if the values correspond 
to the attributes of the DBObject and updates the database table(s).

=cut

sub create {
  my ($self, $values) = @_;
  
  # check if we are called properly
  unless (ref $self) {
    die "Not called as an object method.";
  }

  foreach my $key (keys(%{$self->attributes})) {

    # check for mandatory attributes
    if ($self->is_mandatory($key)) {
      unless (exists($values->{$key}) and defined($values->{$key})) {
	die "Mandatory attribute '$key' missing.";
      }
    }

    # add default value if necessary
    if (defined $self->has_default($key) and !exists($values->{$key})) {
      $values->{$key} = $self->has_default($key);
    }

    # init array attributes to empty array if not set
    if ($self->attributes->{$key}->[0] == DB_ARRAY_OF_SCALARS or 
	$self->attributes->{$key}->[0] == DB_ARRAY_OF_OBJECTS) {
      $values->{$key} = [] unless (ref $values->{$key} eq 'ARRAY');
    }
    
  }
  
  # set attributes and send information to database
  $self->set_attributes($values);
     
  # update the internal object cache
  unless ($self->_master->no_object_cache) {
    $self->_master->cache->object_to_cache($self);
  }
 
  return $self;
}


=pod

=item * B<delete> ()

Deletes an object from the database.

=cut

sub delete {
  my ($self) = @_;

  # check if we are called properly
  unless (ref $self) {
    die "Not called as an object method.";
  }
  
  # delete object from database
  $self->_master->backend->delete_rows( $self->_table, "_id=".$self->_id );

  # delete arrays of that object
  foreach my $key (keys(%{$self->attributes})) {
    if ($self->attributes->{$key} == DB_ARRAY_OF_SCALARS or
	$self->attributes->{$key} == DB_ARRAY_OF_OBJECTS) {
      $self->_master->backend->delete_rows( $self->_table."_$key", "_source_id=".$self->_id );
    }
  }

  # update the internal object cache
  $self->_master->cache->delete_object($self);

  # destroy the perl object
  $_[0] = undef;
  return undef;
}

=pod

=item * B<set_attributes> (I<values>)

Set the attributes of an object to the values given in I<values>. I<values> is 
mandatory and expects a hash reference of key - value pairs. The method checks 
if the values correspond to the attributes of the DBObject and updates the 
database table(s).

=cut

sub set_attributes {
  my ($self, $values) = @_;

  unless (ref $self) {
    die "Not called as an object method.";
  }

  unless (defined $values and (ref($values) eq 'HASH')) {
    die "No values given or not a hash reference: '".$values."'.";
  }
  
  # separate scalars and arrays, set new object attributes
  my $data = {};
  my @arrays = ();
  foreach my $key (keys(%$values)) {

    # check if attribute exists 
    unless ($self->_knows_attribute($key)) {
      die "Object class ".ref($self)." has no attribute '$key'.";
    }

    # scalar value
    if ($self->attributes->{$key}->[0] == DB_SCALAR) {
      if (ref($values->{$key})) {
	die "Mismatched argument for attribute '$key': '".$values->{$key}."'.";
      }
      $self->{$key} = $values->{$key};
      $data->{$key} = $values->{$key};
    } 

    # object reference
    elsif ($self->attributes->{$key}->[0] == DB_OBJECT) {
      
      if (defined $values->{$key}) {
	
	# check if passed object is of the correct class
	if (ref($values->{$key}) eq $self->attributes->{$key}->[1]) {
	  
	  my ($db_id, $obj_id) = $self->_master->translate_ref_to_ids($values->{$key});
	  $self->{$key} = $values->{$key};
	  $data->{"_$key\_db"} = $db_id;
	  $data->{$key} = $obj_id;

	}
	else {
	  die "Mismatched object class for attribute '$key': '".$values->{$key}."'.";
	}
      } 
      else {

	# we got passed undef, so set to NULL
	$self->{$key} = undef;
	$data->{"_$key\_db"} = undef;
	$data->{$key} = undef;

      }

    }
    else {
      push(@arrays, $key);
    }
  }
  
  # update an existing row in the database and set the non-array attributes
  if ($self->_id) {
    
    if (keys(%$data)) {
      $self->_master->backend->update_row( $self->_table, $data, '_id='.$self->_id );
    }

  }
  # create an new entry in the database (then we are called via create)
  else {

    my $id = $self->_master->backend->insert_row( $self->_table, $data );
    
    unless ($id) {
      die "Creating new object failed.";
    }
    
    # update the perl object
    $self->{'_id'} = $id;
  }
  
  # set array attributes in database
  foreach my $key (@arrays) {
    
    # tie array if we dont have already
    unless (defined $self->{$key}) {
      $self->{$key} = [];
      tie @{$self->{$key}}, 'DBSQLArray', $self, $key;
    }

    # check if value is an array
    if (ref($values->{$key}) ne "ARRAY") {
      die "Not an array reference given for for attribute '$key': '".$values->{$key}."'.";
    }

    @{$self->{$key}} = ();
    foreach my $element (@{$values->{$key}}) {
      push @{$self->{$key}}, $element;
    }  
  }
  
  return $self;
}


=pod

=item * B<init> (I<attribute hash>)

Returns a unique object, defined by the attribute values passed.
The passed attributes must be an unique index, otherwise the method dies. 
If no object matches the attributes, the method will return undef.

=cut

sub init {
  my ($self, $attributes) = @_;

  my @keys = keys(%$attributes);
  if ($self->is_index(\@keys)) {
    my $objects = $self->get_objects($attributes);
    if (scalar(@$objects) == 1) {
      return $objects->[0];
    } 
    elsif (scalar(@$objects) == 0) {
      return undef;
    } 
    else {
      die "Index error in mysql database. Non-unique return value for unique index.";
    }
  }
  
  die "There must be a unique index on the combination of attributes passed.";
}


=pod

=item * B<get_objects> (I<attribute hash>)

Returns a reference to an array of objects, defined by the attribute values passed. 
If no object matches the attributes, the method will return the reference to an 
empty array.

=cut

sub get_objects {
  my ($self, $values) = @_;

  # although this is technically a class method...
  # check that we are called as object method (via DBMaster)
  unless (ref $self) {
    die "Not called as an object method.";
  }

  my $package = $self->_master->module_name."::".$self->_class;

  # if called with _id as value try to query cache first
  if (exists $values->{'_id'}) {
    my $obj = $self->_master->cache->object_from_cache( $self->_master, 
							$self->_class, 
							$values->{'_id'}
						      );
    return [ $obj ] if (ref $obj and $obj->isa($package));
  }
  
  # check if values are passed for selection
  unless (defined($values)) {
    $values = {};
  } 
  elsif (ref($values) ne "HASH") {
    die "Second argument must be a hash";
  }
  
  # create list of non-array attributes
  my @scalar_attributes = ('_id');
  foreach my $key (keys(%{$self->attributes})) {
    if ($self->attributes->{$key}->[0] == DB_SCALAR) {
      push(@scalar_attributes, $key);
    }
    elsif ($self->attributes->{$key}->[0] == DB_OBJECT) {
      push(@scalar_attributes, $key);
      push(@scalar_attributes, '_'.$key.'_db');
    }
  }
  
  # prepare SQL where clause 
  my $conditions = "";
  if (scalar(keys(%$values)) > 0) {

    my @filter_by = ();
    foreach my $key (keys(%$values)) {

      # check if attribute exists
      unless ($key eq '_id' or $self->_knows_attribute($key)) {
	die "Object class ".ref($self)." has no attribute '$key'.";
      }

      if ($key eq '_id' or $self->attributes->{$key}->[0] == DB_SCALAR) {
	if (ref($values->{$key}) eq 'ARRAY') {
	  my $q = $values->{$key}->[0] ? $key . " " . $values->{$key}->[1] . " " . $self->_master->backend->quote($values->{$key}->[0]) : $values->{$key}->[1];
	  push(@filter_by, $q);
	} else {
	  push(@filter_by, $key . "=" . $self->_master->backend->quote($values->{$key}));
	}
      }
      elsif ($self->attributes->{$key}->[0] == DB_OBJECT) {
	
	if (ref $values->{$key}) {
	  
	  my ($db_id, $obj_id) = $self->_master->translate_ref_to_ids($values->{$key});
	  
	  push(@filter_by, '_'.$key."_db=" . $self->_master->backend->quote($db_id));
	  push(@filter_by, $key."=" . $self->_master->backend->quote($obj_id));
	  
	}
	else {
	  
	  push(@filter_by, '_'.$key."_db IS NULL");
	  push(@filter_by, $key." IS NULL");
	  
	}
      }
      else {
	die "Attribute '$key' is neither a scalar nor an object.";
      }
    }

    $conditions = join(" AND ", @filter_by);
  }
 
  my $objects = [];

  # fetch non-array attributes from database
  my $data = $self->_master->backend->get_rows( $self->_table, \@scalar_attributes, 
						$conditions, { 'row_as_hash' => 1 } );
  foreach my $result (@$data) {

    # try to retrieve a cached version
    my $object = $self->_master->cache->object_from_cache( $self->_master, 
							   $self->_class, 
							   $result->{'_id'}
							 );
    
    unless (ref $object and $object->isa($package)) {
      
      # create a new object from result hash
      $object = $package->_new_from_hash($self->_master, $result);
      
      # update object cache
      unless ($self->_master->no_object_cache) {
	$self->_master->cache->object_to_cache($object);
      }
    }
    
    push(@$objects, $object);
  }
  
  return $objects;
}

=pod

=back

=head1 INTERNAL METHODS

Internal or overwritten default perl methods. Do not use from outside!

=over 4

=item * B<_new_from_hash> (I<dbmaster>, I<values_hash>)

Constructor method to initialise a DBObject with the DB master. I<dbmaster> 
expects a reference to a DBMaster object and is mandatory. If called on an 
existing perl object it will terminate and return itself.

This method takes the values hash, adds the necessary keys and blesses it as
class. 

=cut

sub _new_from_hash {
  my ($class, $dbmaster, $self) = @_;

  return $class if (ref $class);
  
  (ref $dbmaster eq 'DBMaster')  
    || die "No DBMaster reference given: ".ref($dbmaster).".";

  $self->{ '_master' } = $dbmaster;
  $class =~ /\w*::([^:]*$)/;
  $self->{ '_class'  } = $1;
  $self->{ '_table'  } = $dbmaster->backend->get_table_name($1);

  bless ($self, $class);
  return $self;
}


=pod

=item * B<_id> ()

Returns the internal id of the object. Note that you cannot use this method to set the internal id.

=cut

sub _id {
  return $_[0]->{'_id'};
}

=pod

=item * B<_master> ()

Returns the associated DB master.

=cut

sub _master {
  return $_[0]->{'_master'};
}

=pod

=item * B<_dbh> ()

Returns the associated db handle via the DB master. Added for convenience.

=cut

sub _dbh {
  return $_[0]->_master->db_handle;
}

=pod

=item * B<_class> ()

Returns the base name of class of this DBObject. This refers to the object table 
name in the database system and not the fully qualified perl object class.
Note: to get the full table name (with the database name prefix) use B<_table>.

=cut

sub _class {
  return $_[0]->{'_class'};
}


=pod

=item * B<_table> ()

Returns the name of the database table that belongs to this DBObject. 

=cut

sub _table {
  return $_[0]->{'_table'};
}


=pod

=item * B<_knows_attribute> (I<attribute>)

Returns a reference to self (true) if the object class has an attribute of the 
name I<attribute>, else undef.

=cut

sub _knows_attribute {
  my ($self, $attribute) = @_;
  if (exists($self->attributes->{$attribute})) {
    return $self;
  }
  else {
    return undef;
  }
}


=pod

=item * B<AUTOLOAD> ()

This version of AUTOLOAD supplies get/set methods for all attributes of a DBObject.

=cut

sub AUTOLOAD {
  my $self = shift;
  
  unless (ref $self) {
    die "Not called as an object method.";
  }

  # assemble method call from AUTOLOAD call
  my $call = our $AUTOLOAD;
  return if $AUTOLOAD =~ /::DESTROY$/;
  $call =~ s/.*://;  

  # check if DBObject contains the attribute called $call
  if ($self->_knows_attribute($call)) {
    
    # generic set 
    if (scalar(@_)) {
      my $value = shift;
      $self->set_attributes({ $call => $value });
    }

    # register AUTOLOADS for scalar attributes
    if ($self->attributes->{$call}->[0] == DB_SCALAR) {
      no strict "refs";   
      *$AUTOLOAD = sub { $_[0]->set_attributes({ $call => $_[1] }) if ($_[1]); return $_[0]->{$call} };
    }
    
    # check if array attribute is already initialised
    elsif ($self->attributes->{$call}->[0] == DB_ARRAY_OF_SCALARS or
	   $self->attributes->{$call}->[0] == DB_ARRAY_OF_OBJECTS) {
      unless (exists($self->{$call})) {
	$self->{$call} = [];
	tie @{$self->{$call}}, 'DBSQLArray', $self, $call;
      }
    }
    
    # check if the object attribute already contains the object
    elsif ($self->attributes->{$call}->[0] == DB_OBJECT) {

      if (defined $self->{$call} and 
	  ref($self->{$call}) ne $self->attributes->{$call}->[1]) {
	
	my ($refclass) = ($self->attributes->{$call}->[1] =~ /\w+::(\w+)/);
	
	# resolve object
	my $object = $self->_master->fetch_by_ref( $self->{'_'.$call.'_db'}, $refclass, $self->{$call} );
	unless (ref $object) {
	  die "Unable to fetch attribute '$call' of " . ref($self) . " id " . $self->{_id} . " from db '".$self->_master->{references_dbs}->{$self->{'_'.$call.'_db'}}->{database}."' of type '".$refclass."' with id ".$self->{$call}.".";
	}
	$self->{$call} = $object;
      }
      
    }
    
    return $self->{$call};
    
  }
  else {
    die "Object class ".ref($self)." has no attribute '$call'.";
  }
  
}

=pod

=item * B<get_objects_for_ids> (I<ids>)

Retrieves a list of objects efficiently.

=cut

sub get_objects_for_ids {
  my ($self, $ids) = @_;

  # check if we have the correct parameters
  unless (ref($self)) {
    die "Not called as an object method.";
  }
  unless (defined($ids) && ref($ids) eq 'ARRAY') {
    die "get_objects_for_ids called with incorrect parameters.";
  }

  my $objects = [];

  my ($table) = ref($self) =~ /\w+::(\w+)/;
  my $data = $self->_master->backend->get_rows_for_ids( $table, $ids );
  foreach my $result (@$data) {
    
    # create a new object from result hash
    my $object = &_new_from_hash(ref($self), $self->_master, $result);
    
    push(@$objects, $object);
    
    # update object cache
    unless ($self->_master->no_object_cache) {
      $self->_master->cache->object_to_cache($object);
    }
  }
  
  return $objects;
}

=pod

=item * B<resolve> (I<attribute>, I<$objects>)

Resolves object attributes of a list of objects efficiently.

=cut
 
sub resolve {
  my ($self, $attribute, $objects) = @_;

  # check if we have the correct parameters
  unless (ref $self) {
    die "Not called as an object method.";
  }
  unless (defined($attribute) && defined($objects) && ref($objects) eq 'ARRAY') {
    die "resolve called with incorrect parameters.";
  }

  # check if DBObject contains the attribute called $attribute
  if ($self->_knows_attribute($attribute)) {

    # check if the passed attribute is an object
    if ($self->attributes->{$attribute}->[0] == DB_OBJECT) {
      
      # check if all passed objects have the correct type and store
      # all ids for each db reference
      my $ids = {};
      foreach my $object (@$objects) {

	# check type
	if (ref($object) ne ref($self)) {
	  die "Resolve failed: All objects in the objects array must be of type ".ref($self).".";
	}

	# check if the attribute has already been resolved
	next if (ref($object->{$attribute}) eq $object->attributes->{$attribute}->[1]);
	
	# store the data
	$ids->{$object->{"_".$attribute."_db"}}->{$object->{$attribute}} = 1;
      }

      # all ids to be retrieved have been stored, resolve the objects
      my $children = {};
      foreach my $db (keys(%$ids)) {

	# get the correct dbmaster
	my $master = DBMaster->new(-database => $self->_master->{'references_dbs'}->{$db}->{'database'},
				   -backend  => $self->_master->{'references_dbs'}->{$db}->{'backend_type'},
				   -connect_data => $self->_master->{'references_dbs'}->{$db}->{'backend_data'} );
	
	my ($table) = ($self->attributes->{$attribute}->[1] =~ /\w+::(\w+)/);
	my @ids_array = keys(%{$ids->{$db}});
	my $data = $master->backend->get_rows_for_ids( $table, \@ids_array );
	foreach my $result (@$data) {
	  
	  # create a new object from result hash
	  my $object = &_new_from_hash($self->attributes->{$attribute}->[1], $master, $result);
	  
	  # store object in parent
	  $children->{$db}->{$object->{_id}} = $object;

	  # update object cache
	  unless ($self->_master->no_object_cache) {
	    $self->_master->cache->object_to_cache($object);
	  }
	}
      }

      # put the children into the parents
      foreach my $object (@$objects) {
	$object->{$attribute} = $children->{$object->{"_".$attribute."_db"}}->{$object->{$attribute}};
      }
      
    } else {
      die "Cannot resolve scalar attribute $attribute. Only object attributes can be resolved.";
    }
  } else {
    die "Object class ".ref($self)." has no attribute '$attribute'.";
  }
  
  return $objects;
}

sub _webserviceable {
  return 0;
}
