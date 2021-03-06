package resources::project;

use strict;
use warnings;
no warnings('once');

use Conf;
use parent qw(resources::resource);
use Encode qw(decode_utf8 encode_utf8);

#use Mail::Mailer;
use MGRAST::Mailer;

use HTML::Template;
use WebConfig;
use MGRAST::Metadata;

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    my %rights = $self->user ? map {$_, 1} @{$self->user->has_right_to(undef, 'view', 'project')} : ();
    $self->{name} = "project";
    $self->{rights} = \%rights;
    $self->{post_actions} = {
        'chown'          => 1,
        'updatemetadata' => 1,
        'addaccession'   => 1
    };
    $self->{get_actions} = {
        'updateright'     => 1,
        'makepublic'      => 1,
        'movemetagenomes' => 1
    };
    $self->{attributes} = { "id"             => [ 'string', 'unique object identifier' ],
    	                    "name"           => [ 'string', 'human readable identifier' ],
    	                    "libraries"      => [ 'list', [ 'reference library', 'a list of references to the related library objects' ] ],
                            "samples"        => [ 'list', [ 'reference sample', 'a list of references to the related sample objects' ] ],
                            "metagenomes"    => [ 'list', [ 'reference metagenome', 'a list of references to the related metagenome objects' ] ],
    	                    "description"    => [ 'string', 'a short, comprehensive description of the project' ],
    	                    "funding_source" => [ 'string', 'the official name of the source of funding of this project' ],
    	                    "pi"             => [ 'string', 'the first and last name of the principal investigator of the project' ],
    	                    "metadata"       => [ 'hash', 'key value pairs describing metadata' ],
    	                    "created"        => [ 'date', 'time the object was first created' ],
    	                    "version"        => [ 'integer', 'version of the object' ],
    	                    "url"            => [ 'uri', 'resource location of this object instance' ],
    	                    "status"         => [ 'cv', [ ['public', 'object is public'],
                                                          ['private', 'object is private'] ] ]
    	                  };
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->url."/".$self->name,
		    'description' => "A project is a composition of samples, libraries and metagenomes being analyzed in a global context.",
		    'type' => 'object',
		    'documentation' => $self->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				      'request'     => $self->url."/".$self->name,
				      'description' => "Returns description of parameters and attributes.",
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => "self",
				      'parameters'  => { 'options'     => {},
							             'required'    => {},
							             'body'        => {} } },
				    { 'name'        => "query",
				      'request'     => $self->url."/".$self->name,				      
				      'description' => "Returns a set of data matching the query criteria.",
				      'example'     => [ $self->url."/".$self->name."?limit=20&order=name",
    				                     'retrieve the first 20 projects ordered by name' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => { "next"   => [ "uri", "link to the previous set or null if this is the first set" ],
							 "prev"   => [ "uri", "link to the next set or null if this is the last set" ],
							 "order"  => [ "string", "name of the attribute the returned data is ordered by" ],
							 "data"   => [ "list", [ "object", [$self->attributes, "list of the project objects"] ] ],
							 "limit"  => [ "integer", "maximum number of data items returned, default is 10" ],
							 "total_count" => [ "integer", "total number of available data items" ],
							 "offset" => [ "integer", "zero based index of the first returned data item" ] },
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ],
									    'limit' => [ 'integer', 'maximum number of items requested' ],
									    'offset' => [ 'integer', 'zero based index of the first data object to be returned' ],
									    'order' => [ 'cv', [ [ 'id' , 'return data objects ordered by id' ],
												 [ 'name' , 'return data objects ordered by name' ] ] ] },
							 'required'    => {},
							 'body'        => {} } },
				    { 'name'        => "instance",
				      'request'     => $self->url."/".$self->name."/{id}",
				      'description' => "Returns a single data object.",
				      'example'     => [ $self->url."/".$self->name."/mgp128?verbosity=full",
      				                     'retrieve all data for project mgp128' ],
				      'method'      => "GET" ,
				      'type'        => "synchronous" ,  
				      'attributes'  => $self->attributes,
				      'parameters'  => { 'options'     => { 'verbosity' => [ 'cv', [ [ 'minimal', 'returns only minimal information' ],
												     [ 'verbose', 'returns all metadata' ],
												     [ 'full', 'returns all metadata and references' ] ] ] },
							 'required'    => { "id" => [ "string", "unique object identifier" ] },
							 'body'        => {} } },
				     ]
				 };

    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    
    # check for parameters
    my @parameters = $self->cgi->param;
    if ( (scalar(@{$self->rest}) == 0) &&
         ((scalar(@parameters) == 0) || ((scalar(@parameters) == 1) && ($parameters[0] eq 'keywords'))) )
    {
        $self->info();
    }
    if ($self->method eq 'POST') {
        if (scalar(@{$self->rest}) == 1) {
            if ($self->rest->[0] eq 'create') {
                $self->create_project();
            } elsif ($self->rest->[0] eq 'delete') {
                $self->delete_project();
            } else {
                $self->info();
            }
        }
        if ((scalar(@{$self->rest}) > 1) && exists($self->{post_actions}{$self->rest->[1]})) {
            $self->post_action();
        } else {
            $self->info();
        }
    } elsif ( ($self->method eq 'GET') && scalar(@{$self->rest}) ) {
         if ((scalar(@{$self->rest}) > 1) && exists($self->{get_actions}{$self->rest->[1]})) {
             $self->get_action();
         } else {
             $self->instance();
         }
    } else {
        $self->query();
    }
}

# create a new empty project
sub create_project {
    my ($self) = @_;
    my $master = $self->connect_to_datasource();
    unless ($self->{user}) {
        $self->return_data( {"ERROR" => "insufficient permissions for this user call"}, 401 );
    }
    unless ($self->{cgi}->param("user")) {
        $self->return_data( {"ERROR" => "missing parameter user"}, 400 );
    }
    my $puser = $self->user->_master->User->init({login => $self->{cgi}->param('user')});
    unless (ref $puser) {
        $self->return_data( {"ERROR" => "invalid user"}, 400 );
    }
    unless ($self->{cgi}->param("name")) {
        $self->return_data( {"ERROR" => "missing parameter name"}, 400 );
    }
    my $existing = $master->Project->get_objects({name => $self->{cgi}->param('name')});
    if (scalar(@$existing)) {
        $self->return_data( {"ERROR" => "project name taken"}, 400 );
    }
    my $proj = $master->Project->create_project($puser, $self->{cgi}->param('name'));
    if (ref ($proj)) {
        my $response = {
            "OK"         => "project created",
            "project"    => "mgp".$proj->id,
            "name"       => $proj->name,
            "owner"      => "mgu".$puser->_id,
            "obfuscated" => $self->obfuscate("mgp".$proj->id)
        };
        $self->return_data($response, 200);
    } else {
        $self->return_data( {"ERROR" => "could not create project"}, 400 );
    }
}

# delete an empty project
sub delete_project {
    my ($self) = @_;
    my $master = $self->connect_to_datasource();
    unless ($self->{cgi}->param("id")) {
        $self->return_data( {"ERROR" => "missing parameter id"}, 400 );
    }
    my $id = $self->idresolve($self->{cgi}->param('id'));
    $id =~ s/^mgp//;
    unless ($self->user && ($self->user->has_star_right('edit', 'project') || $self->user->has_right(undef, 'edit', 'project', $id))) {
        $self->return_data( { "ERROR" => "insufficient permissions" }, 401 );
    }
    my $proj = $master->Project->init({id => $id});
    unless (ref $proj) {
        $self->return_data( {"ERROR" => "project not found"}, 400 );
    }
    # check if the project is empty
    if (! $proj->is_empty()) {
        $self->return_data( {"ERROR" => "project not empty"}, 400 );
    }
    my $isDeleted = $proj->delete_project($self->{user});
    if (! $isDeleted) {
        $self->return_data( {"ERROR" => "project deletion failed"}, 400 );
    } else {
        $self->return_data( {"OK" => "project deleted"}, 200 );
    }
}

sub post_action {
    my ($self) = @_;
    
    # get rest parameters
    my $rest = $self->rest;
    # get database
    my $master = $self->connect_to_datasource();
    
    # check id format
    my $tempid = $self->idresolve($rest->[0]);
    my ($id) = $tempid =~ /^mgp(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }
    
    # edit rights
    unless ($self->user && ($self->user->has_star_right('edit', 'project') || $self->user->has_right(undef, 'edit', 'project', $id))) {
        $self->return_data( { "ERROR" => "insufficient permissions" }, 401 );
    }
    
    # get project
    my $project = $master->Project->init({id => $id});
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "id not found: " . $rest->[0]}, 404 );
    }
    
    # add ownership of all project data to another user
    if ($rest->[1] eq 'chown') {
        # only admins can do this
        unless ($self->user->has_star_right('edit', 'user')) {
            $self->return_data( {"ERROR" => "insufficient permissions"}, 401 );
        }
        # get target user
        my $umaster = $self->user->_master;
        my $puser = $umaster->User->init({login => $self->{cgi}->param('user')});
        unless (ref $puser) {
            $self->return_data( {"ERROR" => "invalid user"}, 400 );
        }
        my $pscope = $puser->get_user_scope();
        # add project rights to the user
        $umaster->Rights->create({
            scope     => $pscope,
            data_type => 'project',
            data_id   => $project->id,
            name      => 'edit',
            granted   => 1,
            delegated => 0
        });
        $umaster->Rights->create({
            scope     => $pscope,
            data_type => 'project',
            data_id   => $project->id,
            name      => 'view',
            granted   => 1,
            delegated => 0
        });
        # add metagenome rights to the user
        my $mgs = $project->metagenomes();
        foreach my $mg (@$mgs) {
            $umaster->Rights->create({
                scope     => $pscope,
                data_type => 'metagenome',
                data_id   => $mg->{metagenome_id},
                name      => 'edit',
                granted   => 1,
                delegated => 0
            });
            $umaster->Rights->create({
                scope     => $pscope,
                data_type => 'metagenome',
                data_id   => $mg->{metagenome_id},
                name      => 'view',
                granted   => 1,
                delegated => 0
            });
            # update the shock nodes with ACLs
            my $nodes = $self->get_shock_query({'id' => 'mgm'.$mg->{metagenome_id}}, $self->mgrast_token);
            foreach my $n (@$nodes) {
                if ($n->{attributes}{type} ne 'metagenome') {
                    next;
                }
                $self->edit_shock_acl($n->{id}, $self->mgrast_token, $puser, 'put', 'all');
            }
        }
        $self->return_data( {"OK" => "user added as owner"}, 200 );
    }
    # update basic project metadata
    elsif ($rest->[1] eq 'updatemetadata') {
        # get paramaters
        my $metadbm = MGRAST::Metadata->new->_handle();
        my @keys = (
            'project_name',
            'project_description',
            'project_funding',
            'PI_email',
            'PI_firstname',
            'PI_lastname',
            'PI_organization',
            'PI_organization_country',
            'PI_organization_url',
            'PI_organization_address',
            'email',
            'firstname',
            'lastname',
            'organization',
            'organization_country',
            'organization_url',
            'organization_address'
        );
        my $keyval = {};
        foreach my $key (@keys) {
            if ($self->cgi->param($key)) {
                $keyval->{$key} = decode_utf8($self->cgi->param($key));
            }
        }
        # update DB
        foreach my $key (keys(%$keyval)) {
	  if ($key eq 'project_name') {
	    $project->name($keyval->{$key});
	  } else {
            $project->data($key, $keyval->{$key});
	  }
        }
        # update elasticsearch
        foreach my $mgid (@{$project->metagenomes(1)}) {
            $self->upsert_to_elasticsearch_metadata($mgid);
        }
        # return success
        $self->return_data( {"OK" => "metadata updated"}, 200 );
    }
    # add external db accesion ID
    elsif ($rest->[1] eq 'addaccession') {
        my $dbname    = $self->cgi->param('dbname') || "";
        my $accession = $self->cgi->param('accession') || "";
        my $has_file  = $self->cgi->param('receipt') || "";
        my $proj_id   = "mgp".$project->id;
        my $response  = {
            "OK"         => "accession added",
            "project"    => $proj_id
        };
        if ($has_file) {
            # EBI receipt
            my $fhdl = $self->cgi->upload('receipt');
            unless ($fhdl) {
                $self->return_data({"ERROR" => "Storing object failed - could not obtain filehandle"}, 507);
            }
            my $text = do { local $/; <$fhdl> };
            my $receipt = $self->parse_ebi_receipt($text);
            unless ($receipt->{success} eq 'true') {
                $self->return_data( {"ERROR" => "Receipt was not successful"}, 404 );
            }
            unless ($receipt->{study}{mgrast_accession} eq $proj_id) {
                $self->return_data( {"ERROR" => "Receipt is for wrong project (".$receipt->{study}{mgrast_accession}.") not $proj_id"}, 404 );
            }
            my $key = 'ebi_id';
            $project->data($key, $receipt->{study}{ena_accession});
            $response->{ena_accession} = $receipt->{study}{ena_accession};
            $response->{samples} = [];
            $response->{libraries} = [];
            $response->{metagenomes} = [];
            foreach my $s (@{$receipt->{samples}}) {
                my ($sid) = $s->{mgrast_accession} =~ /^mgs(\d+)$/;
                my $sample = $master->MetaDataCollection->init( {ID => $sid} );
                $sample->data($key, $s->{ena_accession});
                push @{$response->{samples}}, $s;
            }
            foreach my $l (@{$receipt->{experiments}}) {
                my ($lid) = $l->{mgrast_accession} =~ /^mgl(\d+)$/;
                my $library = $master->MetaDataCollection->init( {ID => $lid} );
                $library->data($key, $l->{ena_accession});
                push @{$response->{libraries}}, $l;
            }
            foreach my $m (@{$receipt->{runs}}) {
                my ($mid) = $m->{mgrast_accession} =~ /^mgm(.+)$/;
                my $job = $master->Job->get_objects({ metagenome_id => $mid });
                if (scalar(@$job)) {
                    $job = $job->[0];
                    $job->data($key, $m->{ena_accession});
                    push @{$response->{metagenomes}}, $m;
                }
            }
        } elsif ($dbname && $accession) {
            # project only update
            my $key = lc($dbname).'_id';
            $project->data($key, $accession);
            $response->{$key} = $accession;
        } else {
            $self->return_data( {"ERROR" => "Missing required options: dbname and accession, or reciept"}, 404 );
        }
        
        # return success
        $self->return_data($response);
    }
}

sub get_action {
    my ($self) = @_;
    
    # get rest parameters
    my $rest = $self->rest;
    # get database
    my $master = $self->connect_to_datasource();
    
    # check id format
    my $tempid = $self->idresolve($rest->[0]);
    my ($id) = $tempid =~ /^mgp(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }
    
    # edit rights
    unless ($self->user && ($self->user->has_star_right('edit', 'project') || $self->user->has_right(undef, 'edit', 'project', $id))) {
        $self->return_data( { "ERROR" => "insufficient permissions" }, 401 );
    }
    
    if ($rest->[1] eq 'updateright') {
        $self->updateRight($id);
        return;
    }
    
    # get project
    my $project = $master->Project->init( {id => $id} );
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "id not found: ".$rest->[0]}, 404 );
    }
    
    # make the project public
    if ($rest->[1] eq 'makepublic') {
        my $mgs = $project->metagenomes();
        unless (scalar(@$mgs)) {
            $self->return_data( {"ERROR" => "Cannot publish a project without metagenomes"}, 400 );
        }
        
        # check metadata
        my $mddb = MGRAST::Metadata->new();
        my $all_errors = {};
        foreach my $mg (@$mgs) {
            my $errors = $mddb->verify_job_metadata($mg);
            if (scalar(@$errors)) {
                $all_errors->{$mg->{metagenome_id}} = $errors;
            }
        }
        if (scalar(keys(%$all_errors))) {
            $self->return_data( {"ERROR" => "metadata has errors", "errors" => $all_errors }, 400 );
        }

        # make all metagenomes public
        foreach my $job (@$mgs) {
            # update shock nodes
            my $nodes = $self->get_shock_query({'id' => 'mgm'.$job->{metagenome_id}}, $self->mgrast_token);
            foreach my $n (@$nodes) {
                my $attr = $n->{attributes};
                if ($attr->{type} ne 'metagenome') {
                    next;
                }
                $attr->{status} = 'public';
                $self->update_shock_node($n->{id}, $attr, $self->mgrast_token);
                $self->edit_shock_public_acl($n->{id}, $self->mgrast_token, 'put', 'read');
            }
            # update db
            $job->public(1);
            $job->set_publication_date();
            # update elasticsearch
            $self->upsert_to_elasticsearch_metadata($job->metagenome_id);
        }

        # make project public
        $project->public(1);

        # return success
        my $response = {
            "OK"         => "project published",
            "project"    => "mgp".$project->id,
            "name"       => $project->name,
            "owner"      => "mgu".$self->user->_id
        };
        $self->return_data($response, 200);
    }

    # move metagenomes to a different project
    elsif ($rest->[1] eq 'movemetagenomes') {
        # get second project
        my $tempid2 = $self->idresolve($self->cgi->param('target'));
        my ($id2) = $tempid2 =~ /^mgp(\d+)$/;
        if (! $id2) {
            $self->return_data( {"ERROR" => "invalid id format: " . $self->cgi->param('target')}, 400 );
        }
        # check permissions
        unless ($self->user->has_star_right('edit', 'project') || $self->user->has_right(undef, 'edit', 'project', $id2)) {
            $self->return_data( {"ERROR" => "insufficient permissions"}, 401 );
        }
        my $project2 = $master->Project->init( {id => $id2} );
        unless (ref($project2)) {
            $self->return_data( {"ERROR" => "id not found: $id2"}, 404 );
        }
        
        # mg ids in project 1
        my %job_1_hash = map { $_, 1 } @{ $project->all_metagenome_ids(1) };
        my @move_over = $self->cgi->param("move");
        # test for existance before doing any moving
        foreach my $m (@move_over) {
            $m =~ s/^mgm//;
            unless ($job_1_hash{$m}) {
                $self->return_data( {"ERROR" => "metagenome not part of source project: ".$m}, 400 );
            }
        }
        # need to retrieve job twice as we alter DB by direct SQL without touching job object
        foreach my $m (@move_over) {
            $m =~ s/^mgm//;
            # remove
            my $rjob = $master->Job->get_objects( { metagenome_id => $m });
            if (scalar(@$rjob)) {
                $project->remove_job($rjob->[0]);
            }
            # add
            my $ajob = $master->Job->get_objects( { metagenome_id => $m });
            if (scalar(@$ajob)) {
                $project2->add_job($ajob->[0]);
            }
            # update elasticsearch
            $self->upsert_to_elasticsearch_metadata($m);
        }
        $self->return_data( {"OK" => "metagenomes moved"}, 200 );
    }
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
    
    # get rest parameters
    my $rest = $self->rest;
    # get database
    my $master = $self->connect_to_datasource();
    
    # check id format
    my $tempid = $self->idresolve($rest->[0]);
    my ($id) = $tempid =~ /^mgp(\d+)$/;
    if ((! $id) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: " . $rest->[0]}, 400 );
    }
    
    # get data
    my $project = $master->Project->init( {id => $id} );
    unless (ref($project)) {
        $self->return_data( {"ERROR" => "id $id does not exists"}, 404 );
    }
    
    # check rights
    unless ($project->{public} || exists($self->rights->{$id}) || exists($self->rights->{'*'})) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }
    
    # return cached if exists
    unless ($self->cgi->param('nocache')) {
        $self->return_cached();
    }
    
    # prepare data
    my $data = $self->prepare_data( [$project] );
    $data = $data->[0];
    $self->json->utf8();
    $self->return_data($data, undef, 1); # cache this!
}

# the resource is called without an id parameter, but with at least one query parameter
sub query {
    my ($self) = @_;

    # get database
    my $master   = $self->connect_to_datasource();
    my $projects = [];
    my $total    = 0;

    # check pagination
    my $limit  = defined($self->cgi->param('limit')) ? $self->cgi->param('limit') : 10;
    my $offset = $self->cgi->param('offset') || 0;
    my $order  = $self->cgi->param('order')  || "id";

    if ($limit == 0) {
        $limit = 18446744073709551615;
    }

    # check if we just want the private projects
    if ($self->cgi->param('private')) {
      unless ($self->user) {
	$self->return_data({"ERROR" => "private option requires authentication"}, 400);
      }
      my $ids = [];
      if ($self->cgi->param('edit')) {
	$ids = $self->user->has_right_to(undef, 'edit', 'project');
      } else {
	$ids = $self->user->has_right_to(undef, 'view', 'project');
      }
      if (scalar(@$ids) && $ids->[0] eq '*') {
	shift @$ids;
      }
      my $list = join(",", @$ids);
      $total = scalar(@$ids);
      $projects = $master->Project->get_objects( {$order => [undef, "id IN ($list) ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    }
    # get all items the user has access to
    elsif (exists $self->rights->{'*'}) {
        $total    = $master->Project->count_all();
        $projects = $master->Project->get_objects( {$order => [undef, "_id IS NOT NULL ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    } else {
        my $public = $master->Project->get_public_projects(1);
        my $list   = join(',', (@$public, keys %{$self->rights}));
        $total     = scalar(@$public) + scalar(keys %{$self->rights});
        $projects  = $master->Project->get_objects( {$order => [undef, "id IN ($list) ORDER BY $order LIMIT $limit OFFSET $offset"]} );
    }
    $limit = ($limit > scalar(@$projects)) ? scalar(@$projects) : $limit;
    
    # prepare data to the correct output format
    my $data = $self->prepare_data($projects);

    # check for pagination
    $data = $self->check_pagination($data, $total, $limit);
    $self->json->utf8();
    $self->return_data($data);
}

# reformat the data into the requested output format
sub prepare_data {
  my ($self, $data) = @_;
  
  my $objects = [];
  foreach my $project (@$data) {
    my $url = $self->url;
    my $obj = {};
    $obj->{id}      = "mgp".$project->id;
    $obj->{name}    = $project->name;
    $obj->{pi}      = $project->pi;
    $obj->{status}  = $project->public ? 'public' : 'private';
    $obj->{version} = 1;
    $obj->{url}     = $url.'/project/'.$obj->{id};
    $obj->{created} = "";
    
    if ($self->cgi->param('verbosity')) {
      if ($self->cgi->param('verbosity') eq 'permissions' || ($self->cgi->param('verbosity') eq 'full')) {
	unless (scalar(@$data) == 1) {
	  $self->return_data({"ERROR" => "verbosity option permissions only allowed for single projects"}, 400);
	}
	if ($self->user) {
	  my $rightmaster = $self->user->_master->backend;
	  my $project_permissions = $rightmaster->get_rows("Rights LEFT OUTER JOIN Scope ON Rights.scope=Scope._id LEFT OUTER JOIN UserHasScope ON Scope._id=UserHasScope.scope LEFT OUTER JOIN User ON User._id=UserHasScope.user WHERE Rights.data_type='project' AND Rights.data_id='".$project->{id}."';", ["Rights.name, User.firstname, User.lastname, Rights.data_id, Scope.name, Scope.description"]);
	  my $mgids = $project->all_metagenome_ids;
	  my $metagenome_permissions = scalar(@$mgids) ? $rightmaster->get_rows("Rights LEFT OUTER JOIN Scope ON Rights.scope=Scope._id LEFT OUTER JOIN UserHasScope ON Scope._id=UserHasScope.scope LEFT OUTER JOIN User ON User._id=UserHasScope.user WHERE Rights.data_type='metagenome' AND Rights.data_id IN ('".join("', '", @$mgids)."');", ["Rights.name, User.firstname, User.lastname, Rights.data_id, Scope.name, Scope.description"]) : [];
	  $obj->{permissions} = { metagenome => [], project => [] };
	  $obj->{permissions}->{metagenome} = $metagenome_permissions;
	  $obj->{permissions}->{project} = $project_permissions;
	} else {
	  $obj->{permissions} = { metagenome => [], project => [] };
	}
	if ($self->cgi->param('verbosity') eq 'permissions') {
	  return [ $obj ];
	}
      }
      
      if ($self->cgi->param('verbosity') eq 'full') {
	my @colls     = @{ $project->collections };
	my @samples   = map { ["mgs".$_->{ID}, $url."/sample/mgs".$_->{ID}] } grep { $_ && ref($_) && ($_->{type} eq 'sample') } @colls;
	my @libraries = map { ["mgl".$_->{ID}, $url."/library/mgl".$_->{ID}] } grep { $_ && ref($_) && ($_->{type} eq 'library') } @colls;
	$obj->{samples}   = \@samples;
	$obj->{libraries} = \@libraries;
      }

      if (($self->cgi->param('verbosity') eq 'verbose') || ($self->cgi->param('verbosity') eq 'full') || ($self->cgi->param('verbosity') eq 'summary')) {
	my $metadata  = $project->data();
	my $desc = $metadata->{project_description} || $metadata->{study_abstract} || " - ";
	my $fund = $metadata->{project_funding} || " - ";
	$obj->{metadata}       = $metadata;
	$obj->{description}    = $desc;
	$obj->{funding_source} = $fund;
	
	if ($self->cgi->param('verbosity') eq 'summary' || ($self->cgi->param('verbosity') eq 'full')) {
	  my $jdata = $project->metagenomes_summary();
	  my $ratingdata = $project->metagenome_ratings();
	  $obj->{ratings} = $ratingdata;
	  $obj->{metagenomes} = [];
	  foreach my $row (@$jdata) {
	    push(@{$obj->{metagenomes}}, { metagenome_id => 'mgm'.$row->[0],
					   name => $row->[1],
					   basepairs => $row->[2],
					   sequences => $row->[3],
					   biome => $row->[4],
					   feature => $row->[5],
					   material => $row->[6],
					   location => $row->[7],
					   country => $row->[8],
					   coordinates => $row->[9],
					   sequence_type => $row->[10],
					   sequencing_method => $row->[11],
					   viewable => $row->[12],
					   created_on => $row->[13],
					   attributes => $row->[14],
					   sample => $row->[15],
					   library => $row->[16] });
	  }
	} else {
	  my $mgmap = $project->metagenomes_id_name();
	  $obj->{metagenomes} = [];
	  foreach my $key (keys(%$mgmap)) {
	     push(@{$obj->{metagenomes}}, { metagenome_id => 'mgm'.$key,
					    name => $mgmap->{$key} });
	  }
	}
      } elsif ($self->cgi->param('verbosity') ne 'minimal') {
	$self->return_data( {"ERROR" => "invalid value for option verbosity"}, 400 );
      }
    }
    push @$objects, $obj;      
  }
  return $objects;
}

sub updateRight {
  my ($self, $pid) = @_;
  
  my $type = $self->cgi->param('type');
  my $name = $self->cgi->param('name');
  my $scope = $self->cgi->param('scope');
  my $action = $self->cgi->param('action');
  my $id = $self->cgi->param('id');
  my $user = $self->cgi->param('user');

  $id =~ s/^mgm//;
  $id =~ s/^mgp//;

  # check for valid params
  if ($type ne "project" && $type ne "metagenome") {
    $self->return_data( {"ERROR" => "Invalid type parameter. Valid types are metagenome and project."}, 400 );
  }
  if ($name ne "edit" && $name ne "view") {
    $self->return_data( {"ERROR" => "Invalid name parameter. Valid names are view and edit."}, 400 );
  }

  # get the user database
  my $umaster = $self->user->_master;

  # check if a new user is added
  if ($user) {

    # create a reviewer token
    if ($user eq 'reviewer') {
      my $description = "Reviewer_".$pid;
      my @chars=('a'..'z','A'..'Z','0'..'9','_');
      my $token = "";
      foreach (1..50) {
	$token.=$chars[rand @chars];
      }
      
      # create scope for token
      my $token_scope = $umaster->Scope->create( { name => "token:".$token, description => $description } );
      unless (ref($token_scope)) {
	$self->return_data( {"ERROR" => "Unable to create reviewer access token."}, 500 );
      }
      
      # add right to scope
      my $right = $umaster->Rights->create( { granted => 1,
					      name => 'view',
					      data_type => 'project',
					      data_id => $pid,
					      scope => $token_scope,
					      delegated => 1, } );
      unless (ref $right) {
	$self->return_data( {"ERROR" => "Unable to create reviewer access token."}, 500 );
      }
      
       $self->return_data( {"token" => $token}, 200 );
      
    } 
    # get the user by email
    else {

      # check for a valid email address
      unless ($user =~ /\@{1}/) {
	$self->return_data( {"ERROR" => "Invalid email address."}, 400 );
      }

      # get the project name for the email message
      my $master = $self->connect_to_datasource();
      my $project = $master->Project->init( {id => $pid} );
      unless (ref $project) {
	$self->return_data( {"ERROR" => "Unable to access project."}, 500 );
      }
      my $project_name = $project->{name};

      # check if this user exists
      my $existing = $umaster->User->init({ email => $user });
      if (ref $existing) {
	$user = $existing;
      
	# send email
	my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobGranted.tmpl',
					die_on_bad_params => 0);
	$ubody->param('FIRSTNAME', $user->firstname);
	$ubody->param('LASTNAME', $user->lastname);
	$ubody->param('WHAT', "the metagenome project $project_name");
	$ubody->param('WHOM', $self->user->firstname.' '.$self->user->lastname);
	$ubody->param('LINK', "http://www.mg-rast.org/mgmain.html?mgpage=project&project=$pid");
	$ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
	
	$user->send_email( $WebConfig::ADMIN_EMAIL,
			   $WebConfig::APPLICATION_NAME.' - new data available',
			   $ubody->output
			 );
	
	# grant rights if necessary
	my $rights = [ 'view' ];
	if ($self->cgi->param('editable')) {
	  push(@$rights, 'edit');
	}
	my $return_data = [];
	foreach my $name (@$rights) {
	  push(@$return_data, [$name, $user->{firstname}, $user->{lastname}, $pid, "user:".$user->{login}, "automatically created user scope"]);
	  unless(scalar(@{$umaster->Rights->get_objects( { name => $name,
							   data_type => 'project',
							   data_id => $pid,
							   scope => $user->get_user_scope } )})) {
	    my $right = $umaster->Rights->create( { granted => 1,
						    name => $name,
						    data_type => 'project',
						    data_id => $pid,
						    scope => $user->get_user_scope,
						    delegated => 1, } );
	    
	    unless (ref $right) {
	      $self->return_data( {"ERROR" => "Unable to create permission."}, 500 );
	    }
	  }
	}
	
	my $pscope = $umaster->Scope->init( { application => undef,
					      name => 'MGRAST_project_'.$pid } );
	if ($pscope) {
	  my $uhs = $umaster->UserHasScope->get_objects( { user => $user, scope => $pscope } );
	  unless (scalar(@$uhs)) {
	    $umaster->UserHasScope->create( { user => $user, scope => $pscope, granted => 1 } );
	  }
	}
	
	$self->return_data( {"project" => $return_data}, 200 );
	
      }
      # no user found with this email, send a claim token
      else {
	
	# create a claim token
	my $description = "token_scope|from_user:".$self->user->{_id}."|init_date:".time."|email:".$user;
	my @chars=('a'..'z','A'..'Z','0'..'9','_');
	my $token = "";
	foreach (1..50) {
	  $token.=$chars[rand @chars];
	}
	
	# create scope for token
	my $token_scope = $umaster->Scope->create( { name => "token:".$token, description => $description } );
	unless (ref($token_scope)) {
	  $self->return_data( {"ERROR" => "Unable to create permission."}, 500 );
	}
	
	# add rights to scope
	my $rights = [ 'view' ];
	if ($self->cgi->param('editable')) {
	  push(@$rights, 'edit');
	}
	my $rsave = [];
	my $return_data = [];
	foreach my $name (@$rights) {
	  push(@$return_data, [$name, undef, undef, $pid, $token_scope->{name}, $token_scope->{description}]);
	  my $right = $umaster->Rights->create( { granted => 1,
						  name => $name,
						  data_type => 'project',
						  data_id => $pid,
						  scope => $token_scope,
						  delegated => 1, } );
	  unless (ref $right) {
	    $token_scope->delete();
	    foreach my $r (@$rsave) {
	      $r->delete();
	    }
	    $self->return_data( {"ERROR" => "Unable to create permission."}, 500 );
	  }
	  
	  push(@$rsave, $right);
	}
	
	# send token mail
	my $ubody = HTML::Template->new(filename => TMPL_PATH.'EmailSharedJobToken.tmpl',
					die_on_bad_params => 0);
	$ubody->param('WHAT', "the metagenome project $project_name");
	$ubody->param('REGISTER', "http://www.mg-rast.org/mgmain.html?mgpage=register");
	$ubody->param('WHOM', $self->user->firstname.' '.$self->user->lastname);
	$ubody->param('LINK', "http://www.mg-rast.org/mgmain.html?mgpage=token&token=$token");
	$ubody->param('APPLICATION_NAME', $WebConfig::APPLICATION_NAME);
	
	my $email_success = MGRAST::Mailer::send_email( smtp_host => $Conf::smtp_host, 
							from => $WebConfig::ADMIN_EMAIL,
							to => $user,
							subject => $WebConfig::APPLICATION_NAME,
							body => $ubody->output);
	
	
	if ($email_success) {
	  $self->return_data( {"project" => $return_data}, 200 );
	} else {
	  $token_scope->delete();
	  foreach my $r (@$rsave) {
	    $r->delete();
	  }
	  $self->return_data( {"ERROR" => 'Unable to create permission.'}, 500 );
	}
      }
    }
  }
  # END OF TOKEN SECTION #

  # check if the user is trying to remove their own right
  if ($self->user->get_user_scope_name() eq $scope && $type eq 'project' && $action eq 'remove') {
    $self->return_data( {"ERROR" => "You cannot remove your own project permissions"}, 400 );
  }

  # get the desired scope
  my $rscope = $umaster->Scope->get_objects({ name => $scope });
  if (ref $rscope and scalar(@$rscope)) {
    $rscope = $rscope->[0];
  } else {
    $self->return_data( {"ERROR" => "Scope not found"}, 400 );
  }

  # check if the permission already exists
  my $right = $umaster->Rights->get_objects({ data_type => $type, name => $name, scope => $rscope, data_id => $id });
  if (ref $right and scalar(@$right)) {
    $right = $right->[0];
  } else {
    $right = undef;
  }

  # check for add or remove of permission
  if ($action eq 'add') {
    if (ref $right) {
      $right->granted(1);
    } else {
      my $new_right = $self->user->_master->Rights->create({ data_type => $type, name => $name, scope => $rscope, data_id => $id, granted => 1, delegated => 1 });
      unless (ref $new_right) {
	$self->return_data( {"ERROR" => "Could not create permission"}, 500 );
      }
    }
  } elsif ($action eq 'remove') {
    if (ref($right)) {
      $right->delete;
    } else {
      $self->return_data( {"ERROR" => "permission not found"}, 400 );
    }
  } else {
    $self->return_data( {"ERROR" => "Invalid action parameter. Valid actions are 'add' and 'remove'."}, 400 );
  }

  # all went well, return success
  $self->return_data( {"OK" => "The permission has been updated."}, 200 );
}

1;
